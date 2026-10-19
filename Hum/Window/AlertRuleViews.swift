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

// MARK: - Rules

/// A rule as a sentence with its values as raised menus: "CPU 使用率高于 [90%] 持续 [1 分钟]".
struct AlertRuleSentence: View {
    var rule: Alerts.Rule
    var settings = SettingsStore.shared

    var body: some View {
        let unit = settings.prefs.general.temperatureUnit
        HStack(spacing: 4) {
            switch rule {
            case .cpu:
                Text(L10n.Settings.ruleCPU)
                InlineChoice(label: L10n.Settings.ruleCPU, options: Self.percents, selection: pref(\.alerts.cpuThreshold))
                Text(L10n.Settings.ruleFor)
                InlineChoice(label: L10n.Settings.ruleFor, options: Self.durations, selection: pref(\.alerts.cpuMinutes))
            case .gpu:
                Text(L10n.Settings.ruleGPU)
                InlineChoice(label: L10n.Settings.ruleGPU, options: Self.percents, selection: pref(\.alerts.gpuThreshold))
                Text(L10n.Settings.ruleFor)
                InlineChoice(label: L10n.Settings.ruleFor, options: Self.durations, selection: pref(\.alerts.gpuMinutes))
            case .memory:
                Text(L10n.Settings.ruleMemory)
                InlineChoice(label: L10n.Settings.ruleMemory, options: [(MemoryPressure.warning, L10n.Settings.yellow), (.critical, L10n.Settings.red)],
                             selection: pref(\.alerts.memoryLevel))
            case .network:
                Text(L10n.Settings.ruleNetwork)
            case .disk:
                Text(L10n.Settings.ruleDisk)
                InlineChoice(label: L10n.Settings.ruleDisk, options: [5, 10, 20, 50].map { (Double($0), L10n.Settings.gigabytes($0)) },
                             selection: pref(\.alerts.diskFreeGB))
            case .battery:
                Text(L10n.Settings.ruleBattery)
                InlineChoice(label: L10n.Settings.ruleBattery, options: [10, 15, 20, 30].map { (Double($0), Format.percent(Double($0) / 100)) },
                             selection: pref(\.alerts.batteryPercent))
            case .bluetoothLow:
                Text(L10n.Settings.bluetoothLowAlert)
                InlineChoice(label: L10n.Settings.bluetoothLowAlert, options: [10, 15, 20, 25, 30].map { (Double($0) / 100, L10n.Settings.percentValue($0)) },
                             selection: pref(\.bluetooth.lowLevel))
            case .bluetoothDisconnect:
                Text(L10n.Settings.bluetoothDisconnectAlert)
            case .temperature:
                Text(L10n.Settings.ruleTemp)
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
    /// Pointed out after arriving from a chart or a module's settings.
    var highlighted = false
    var settings = SettingsStore.shared
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if showsIcon {
                    LineIcon(d: Icons.module(rule.module), size: 14, lineWidth: 1.5).foregroundStyle(Theme.sub).accessibilityHidden(true)
                }
                AlertRuleSentence(rule: rule)
            }
            Spacer(minLength: 8)
            if settings.prefs.isEnabled(rule.module) {
                HumSwitch(isOn: pref(rule.enabledKey), label: AlertText.name(rule))
            } else {
                Text(L10n.Alerts.moduleOff).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
            }
        }
        .opacity(settings.prefs.isEnabled(rule.module) ? 1 : 0.5)
        .frame(minHeight: minHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.accent.opacity(highlighted ? 0.12 : 0))
                .padding(.horizontal, -8)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Chart label

/// Top right of a module's chart: the rule's value as a raised bell label when it is on, a grey
/// bell when it is off. Either opens the Alerts page with the rule pointed out.
struct ChartAlertBadge: View {
    var rule: Alerts.Rule
    var settings = SettingsStore.shared
    @State private var hovering = false

    var body: some View {
        let p = settings.prefs
        let on = p.alerts.enabled && p[keyPath: rule.enabledKey]
        Button { MainWindowController.shared.showAlerts(focus: rule) } label: {
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
    }
}
