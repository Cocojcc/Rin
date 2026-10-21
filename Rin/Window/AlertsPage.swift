import AppKit
import SwiftUI
import UserNotifications

/// Every alert rule in one place, what fired lately, and how alerts reach you.
struct AlertsPage: View {
    var settings = SettingsStore.shared
    var alerts = Alerts.shared
    /// Triggers that were new when the page opened keep their dot while it is up.
    @State private var fresh: Set<UUID> = []
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    /// The rule a chart or a module's settings sent us to, tinted for a moment.
    @State private var highlighted: Alerts.Rule?

    private static let recentShown = 6

    var body: some View {
        let prefs = settings.prefs
        let enabledCount = Alerts.Rule.allCases.filter { prefs[keyPath: $0.enabledKey] && prefs.isEnabled($0.module) }.count
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: L10n.Sidebar.alerts)
            Section(title: L10n.Alerts.rules, right: L10n.Alerts.rulesOn(enabledCount)) {
                VStack(spacing: 0) {
                    DividedRows {
                        ForEach(Alerts.Rule.allCases, id: \.self) { AlertRuleRow(rule: $0, highlighted: highlighted == $0) }
                        addRow
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .opacity(prefs.alerts.enabled ? 1 : 0.5)
            }
            Section(title: L10n.Alerts.recent, right: alerts.events.isEmpty ? nil : L10n.Alerts.thisWeek(alerts.thisWeek)) {
                VStack(spacing: 0) {
                    if alerts.events.isEmpty {
                        Text(L10n.Alerts.noneYet).ui(13).foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                    DividedRows {
                        ForEach(alerts.events.prefix(Self.recentShown)) { e in
                            EventRow(event: e, fresh: fresh.contains(e.id)) { alerts.show(e) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
            Section(title: L10n.Alerts.delivery) {
                VStack(spacing: 0) {
                    DividedRows {
                        row(L10n.Alerts.enabled) { RinSwitch(isOn: pref(\.alerts.enabled), label: L10n.Alerts.enabled) }
                        if authorization == .denied {
                            row(L10n.Settings.notificationsOff) {
                                WellButton(title: L10n.Settings.openNotificationSettings) { openNotificationSettings() }
                            }
                        }
                        row(L10n.Settings.notificationStyle) {
                            Segmented(label: L10n.Settings.notificationStyle,
                                      options: [(NotificationStyle.banner, L10n.Settings.banner), (.alert, L10n.Settings.alertStyle)],
                                      selection: Binding(get: { prefs.alerts.style }, set: { style in
                                          guard style != settings.prefs.alerts.style else { return }
                                          settings.prefs.alerts.style = style
                                          // Banner vs. alert is a system setting per app; open the page where it is changed.
                                          openNotificationSettings()
                                      }))
                        }
                        row(L10n.Settings.playSound) { RinSwitch(isOn: pref(\.alerts.sound), label: L10n.Settings.playSound) }
                        row(L10n.Settings.colorMenubar) { RinSwitch(isOn: pref(\.alerts.colorMenubar), label: L10n.Settings.colorMenubar) }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
        }
        .onAppear {
            takeNew()
            if let focus = Navigator.shared.alertFocus {
                Navigator.shared.alertFocus = nil
                highlighted = focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
                }
            }
        }
        .onChange(of: alerts.unseenCount) { _, count in if count > 0 { takeNew() } }
        .task { await refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAuthorization() }
        }
    }

    /// "+ 添加提醒": a menu of the rules that are off; picking one turns it on.
    @ViewBuilder private var addRow: some View {
        let off = Alerts.Rule.allCases.filter { !settings.prefs[keyPath: $0.enabledKey] && settings.prefs.isEnabled($0.module) }
        Menu {
            ForEach(off, id: \.self) { rule in
                Button(AlertText.name(rule)) {
                    settings.prefs[keyPath: rule.enabledKey] = true
                    settings.prefs.alerts.enabled = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                LineIcon(d: Icons.plus, size: 14, viewBox: 14, lineWidth: 1.5).foregroundStyle(Theme.sub)
                Text(L10n.Alerts.add).ui(13, 500).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(off.isEmpty)
        .accessibilityLabel(L10n.Alerts.add)
    }

    /// New triggers get their dot here and stop counting on the sidebar badge.
    private func takeNew() {
        fresh.formUnion(alerts.events.filter { !$0.seen }.map(\.id))
        alerts.markAllSeen()
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).ui(13)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 42)
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorization = s.authorizationStatus
    }
}

/// One trigger: module tile, what happened and the detail, when, and a chevron to its page.
private struct EventRow: View {
    var event: AlertEvent
    var fresh: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    LineIcon(d: Icons.module(event.rule.module), size: 14, lineWidth: 1.5)
                        .foregroundStyle(Theme.sub)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            if fresh {
                                Circle().fill(Theme.danger).frame(width: 6, height: 6)
                                    .accessibilityLabel(L10n.Alerts.newA11y)
                            }
                            Text(AlertText.headline(event)).ui(13, fresh ? 500 : 400).lineLimit(1)
                        }
                        if let detail = AlertText.detail(event) {
                            Text(detail).ui(12).foregroundStyle(Theme.sub).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(Format.dayAndTime(event.date)).ui(12).lineLimit(1)
                    LineIcon(d: Icons.linkChevron, width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.4)
                }
                .foregroundStyle(hovering ? Theme.text : Theme.sub)
            }
            .foregroundStyle(Theme.text)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverAnimation(hovering)
        .accessibilityElement(children: .combine)
    }
}

/// The overview's red strip while a rule fires: what is wrong, mute for an hour, and a way to it.
struct AlertBanner: View {
    var event: AlertEvent
    var alerts = Alerts.shared

    var body: some View {
        HStack(spacing: 10) {
            LineIcon(d: Icons.bell, size: 15, lineWidth: 1.5).accessibilityHidden(true)
            Text(AlertText.banner(event)).ui(15, 500).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { alerts.snooze(event.rule) } label: {
                Text(L10n.Alerts.snooze).ui(12)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Button { alerts.show(event) } label: {
                Text(L10n.Alerts.view).ui(12, 500).foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.raised).raisedShadow())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.danger)
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 8))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.dangerBg))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isStaticText)
    }
}
