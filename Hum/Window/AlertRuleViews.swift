import SwiftUI

/// "全部 ›"-style link: grey text and a chevron, tinted under the pointer. The hover box reaches
/// past the text, as the design's negative margins.
struct ChevronLink: View {
    var title: String
    var a11y: String
    /// Space before the link when it follows other text.
    var leading: CGFloat = 0
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).ui(12)
                LineIcon(d: Icons.linkChevron, width: 6, height: 10, viewBox: CGSize(width: 6, height: 10), lineWidth: 1.4)
            }
            .foregroundStyle(Theme.sub)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lgHover) }
            }
            .hoverAnimation(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(a11y)
        .padding(.vertical, -3)
        .padding(.trailing, -6)
        .padding(.leading, leading == 0 ? -6 : leading)
    }
}

/// "全部提醒 ›" to the Alerts page.
struct AllAlertsLink: View {
    var onOpen: (() -> Void)? = nil

    var body: some View {
        ChevronLink(title: L10n.Alerts.all, a11y: L10n.Alerts.allA11y) {
            onOpen?()
            MainWindowController.shared.show(.alerts)
        }
    }
}

// MARK: - Rules

/// A rule as a sentence with its values as raised menus: "CPU 使用率高于 [90%] 持续 [1 分钟]".
/// `short` drops the subject for the chart popover ("高于 [90%] 持续 [1 分钟]").
struct AlertRuleSentence: View {
    var rule: Alerts.Rule
    var short = false
    var settings = SettingsStore.shared

    var body: some View {
        let unit = settings.prefs.general.temperatureUnit
        HStack(spacing: 4) {
            switch rule {
            case .cpu:
                Text(short ? L10n.Alerts.above : L10n.Settings.ruleCPU)
                InlineChoice(label: L10n.Settings.ruleCPU, options: Self.percents, selection: pref(\.alerts.cpuThreshold))
                Text(L10n.Settings.ruleFor)
                InlineChoice(label: L10n.Settings.ruleFor, options: Self.durations, selection: pref(\.alerts.cpuMinutes))
            case .gpu:
                Text(short ? L10n.Alerts.above : L10n.Settings.ruleGPU)
                InlineChoice(label: L10n.Settings.ruleGPU, options: Self.percents, selection: pref(\.alerts.gpuThreshold))
                Text(L10n.Settings.ruleFor)
                InlineChoice(label: L10n.Settings.ruleFor, options: Self.durations, selection: pref(\.alerts.gpuMinutes))
            case .memory:
                Text(short ? L10n.Alerts.pressureTurns : L10n.Settings.ruleMemory)
                InlineChoice(label: L10n.Settings.ruleMemory, options: [(MemoryPressure.warning, L10n.Settings.yellow), (.critical, L10n.Settings.red)],
                             selection: pref(\.alerts.memoryLevel))
            case .network:
                Text(short ? L10n.Alerts.whenDisconnected : L10n.Settings.ruleNetwork)
            case .disk:
                Text(short ? L10n.Alerts.freeBelow : L10n.Settings.ruleDisk)
                InlineChoice(label: L10n.Settings.ruleDisk, options: [5, 10, 20, 50].map { (Double($0), L10n.Settings.gigabytes($0)) },
                             selection: pref(\.alerts.diskFreeGB))
            case .battery:
                Text(short ? L10n.Alerts.levelBelow : L10n.Settings.ruleBattery)
                InlineChoice(label: L10n.Settings.ruleBattery, options: [10, 15, 20, 30].map { (Double($0), Format.percent(Double($0) / 100)) },
                             selection: pref(\.alerts.batteryPercent))
            case .bluetoothLow:
                Text(short ? L10n.Alerts.levelBelow : L10n.Settings.bluetoothLowAlert)
                InlineChoice(label: L10n.Settings.bluetoothLowAlert, options: [10, 15, 20, 25, 30].map { (Double($0) / 100, L10n.Settings.percentValue($0)) },
                             selection: pref(\.bluetooth.lowLevel))
            case .bluetoothDisconnect:
                Text(short ? L10n.Alerts.whenDisconnected : L10n.Settings.bluetoothDisconnectAlert)
            case .temperature:
                Text(short ? L10n.Alerts.above : L10n.Settings.ruleTemp)
                InlineChoice(label: L10n.Settings.ruleTemp, options: [85, 90, 95, 100].map { (Double($0), Format.temperature(Double($0), unit: unit, showUnit: true)) },
                             selection: pref(\.alerts.tempThreshold))
            }
        }
        .ui(13)
        .padding(.vertical, 7)
    }

    static let percents: [(Double, String)] = [70, 80, 90, 95].map { (Double($0), Format.percent(Double($0) / 100)) }

    static var durations: [(Double, String)] {
        [(0.5, L10n.Alerts.seconds(30)), (1, L10n.Alerts.minutes(1)), (2, L10n.Alerts.minutes(2)), (5, L10n.Alerts.minutes(5))]
    }
}

/// A rule with its switch: the Alerts page (with the module icon) and a module's 提醒 tab.
struct AlertRuleRow: View {
    var rule: Alerts.Rule
    var showsIcon = true
    var minHeight: CGFloat = 44
    var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if showsIcon {
                    LineIcon(d: Icons.module(rule.module), size: 14, lineWidth: 1.5).foregroundStyle(Theme.sub).accessibilityHidden(true)
                }
                AlertRuleSentence(rule: rule)
            }
            Spacer(minLength: 8)
            HumSwitch(isOn: pref(rule.enabledKey), label: AlertText.name(rule))
        }
        .frame(minHeight: minHeight)
    }
}

// MARK: - Chart label

/// Top right of a module's chart: the rule's value as a raised bell label when it is on, a grey
/// bell when it is off. Either opens the rule's quick settings.
struct ChartAlertBadge: View {
    var rule: Alerts.Rule
    var settings = SettingsStore.shared
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let p = settings.prefs
        let on = p.alerts.enabled && p[keyPath: rule.enabledKey]
        Button { open.toggle() } label: {
            if on {
                HStack(spacing: 4) {
                    LineIcon(d: Icons.bell, size: 12, lineWidth: 1.5).foregroundStyle(Theme.danger)
                    Text(AlertText.pill(rule, p)).ui(12, 500).foregroundStyle(Theme.text).lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Theme.raised).raisedShadow())
                .contentShape(Capsule())
            } else {
                LineIcon(d: Icons.bell, size: 12, lineWidth: 1.5)
                    .foregroundStyle(hovering ? Theme.text : Theme.sub)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(hovering ? Theme.lgHover : Theme.well))
                    .hoverAnimation(hovering)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(on ? L10n.Alerts.edit : L10n.Alerts.add)
        .accessibilityLabel(on ? L10n.Alerts.editA11y(AlertText.pill(rule, p)) : L10n.Alerts.add)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            // Drawn at the window's scale, like everything around it.
            UIScaled { AlertQuickSettings(rule: rule) { open = false } }
        }
    }
}

/// The popover from a chart's alert label: the rule's switch and values, then a way to all rules.
struct AlertQuickSettings: View {
    var rule: Alerts.Rule
    var close: () -> Void
    var settings = SettingsStore.shared
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    LineIcon(d: Icons.bell, size: 13, lineWidth: 1.5).foregroundStyle(Theme.danger)
                    Text(AlertText.name(rule)).ui(13, 500)
                }
                Spacer(minLength: 0)
                HumSwitch(isOn: Binding(get: { settings.prefs[keyPath: rule.enabledKey] }, set: { on in
                    settings.prefs[keyPath: rule.enabledKey] = on
                    if on { settings.prefs.alerts.enabled = true }
                }), label: AlertText.name(rule))
            }
            AlertRuleSentence(rule: rule, short: true).padding(.top, 5)
            HStack {
                AllAlertsLink(onOpen: close).padding(.leading, 6)
                Spacer(minLength: 8)
                Button(action: close) {
                    Text(L10n.Alerts.done).ui(12, 500).foregroundStyle(accent.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(Capsule().fill(accent.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(width: 252)
        .foregroundStyle(Theme.text)
        .environment(\.accent, settings.prefs.general.accent.colors)
    }
}
