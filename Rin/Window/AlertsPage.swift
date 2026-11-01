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
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(title: L10n.Sidebar.alerts)
            Columns(gap: 44) {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Alerts.rules) {
                        Text(L10n.Alerts.rulesOn(enabledCount))
                        addButton
                    }
                    VStack(spacing: 0) {
                        DividedRows {
                            ForEach(Alerts.Rule.allCases, id: \.self) { AlertRuleRow(rule: $0, minHeight: 42, highlighted: highlighted == $0) }
                        }
                    }
                    .opacity(prefs.alerts.enabled ? 1 : 0.5)
                }
            } b: {
                VStack(alignment: .leading, spacing: 0) {
                    HeadRow(title: L10n.Alerts.recent) {
                        if !alerts.events.isEmpty { Text(L10n.Alerts.thisWeek(alerts.thisWeek)) }
                    }
                    if alerts.events.isEmpty {
                        Text(L10n.Alerts.noneYet).ui(14).foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    VStack(spacing: 0) {
                        DividedRows {
                            ForEach(alerts.events.prefix(Self.recentShown)) { e in
                                EventRow(event: e, fresh: fresh.contains(e.id)) { alerts.show(e) }
                            }
                        }
                    }
                    SettingsGroup(title: L10n.Alerts.delivery) {
                        SettingsRow(title: L10n.Alerts.enabled) { RinSwitch(isOn: pref(\.alerts.enabled), label: L10n.Alerts.enabled) }
                        if authorization == .denied {
                            SettingsRow(title: L10n.Settings.notificationsOff) {
                                WellButton(title: L10n.Settings.openNotificationSettings) { openNotificationSettings() }
                            }
                        }
                        SettingsRow(title: L10n.Settings.notificationStyle) {
                            Segmented(label: L10n.Settings.notificationStyle,
                                      options: [(NotificationStyle.banner, L10n.Settings.banner), (.alert, L10n.Settings.alertStyle)],
                                      selection: Binding(get: { prefs.alerts.style }, set: { style in
                                          guard style != settings.prefs.alerts.style else { return }
                                          settings.prefs.alerts.style = style
                                          // Banner vs. alert is a system setting per app; open the page where it is changed.
                                          openNotificationSettings()
                                      }))
                        }
                        SettingsRow(title: L10n.Settings.playSound) { RinSwitch(isOn: pref(\.alerts.sound), label: L10n.Settings.playSound) }
                        SettingsRow(title: L10n.Settings.colorMenubar) { RinSwitch(isOn: pref(\.alerts.colorMenubar), label: L10n.Settings.colorMenubar) }
                    }
                    .padding(.top, 36)
                }
            }
            .padding(.top, 30)
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

    /// "+" beside the count: a menu of the rules that are off; picking one turns it on.
    @ViewBuilder private var addButton: some View {
        let off = Alerts.Rule.allCases.filter { !settings.prefs[keyPath: $0.enabledKey] && settings.prefs.isEnabled($0.module) }
        Menu {
            ForEach(off, id: \.self) { rule in
                Button(AlertText.name(rule)) {
                    settings.prefs[keyPath: rule.enabledKey] = true
                    settings.prefs.alerts.enabled = true
                }
            }
        } label: {
            LineIcon(d: Icons.plusLarge, size: 14, lineWidth: 1.5)
                .foregroundStyle(Theme.sub)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(off.isEmpty)
        .opacity(off.isEmpty ? 0.4 : 1)
        .help(L10n.Alerts.add)
        .accessibilityLabel(L10n.Alerts.add)
        .padding(EdgeInsets(top: -5, leading: 0, bottom: -5, trailing: -6))
    }

    /// New triggers get their dot here and stop counting on the sidebar badge.
    private func takeNew() {
        fresh.formUnion(alerts.events.filter { !$0.seen }.map(\.id))
        alerts.markAllSeen()
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

/// One trigger: a red dot while it holds (grey once over), what happened, then its detail and
/// when on a smaller line; opens the module's page.
private struct EventRow: View {
    var event: AlertEvent
    var fresh: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(event.ended == nil ? Theme.danger : Theme.low).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AlertText.headline(event)).ui(14, fresh ? 500 : 400).lineLimit(1)
                        .accessibilityLabel(fresh ? L10n.Alerts.newA11y + AlertText.headline(event) : AlertText.headline(event))
                    HStack(spacing: 10) {
                        Text(AlertText.detail(event) ?? "").lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                        Text(Format.dayAndTime(event.date)).lineLimit(1).fixedSize()
                    }
                    .ui(12)
                    .foregroundStyle(Theme.sub)
                }
            }
            .foregroundStyle(Theme.text)
            .frame(height: 66)
            .padding(.horizontal, 8)
            .background { if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) } }
            .padding(.horizontal, -8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverAnimation(hovering)
        .accessibilityElement(children: .combine)
    }
}
