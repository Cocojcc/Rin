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
                Text(title).ui(13)
                LineIcon(d: Icons.chevronRight, size: 14, lineWidth: 1.5)
            }
            .foregroundStyle(hovering ? Theme.text : Theme.sub)
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
            case .publicIP:
                Text(L10n.Settings.rulePublicIP)
                PublicIPIntervalChoice(selection: pref(\.alerts.publicIPInterval))
                if !L10n.Settings.rulePublicIPSuffix.isEmpty {
                    Text(L10n.Settings.rulePublicIPSuffix)
                }
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
        .ui(14)
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 6)
    }

    static let percents: [(Double, String)] = [70, 80, 90, 95].map { (Double($0), Format.percent(Double($0) / 100)) }

    static var durations: [(Double, String)] {
        [(0.5, L10n.Alerts.seconds(30)), (1, L10n.Alerts.minutes(1)), (2, L10n.Alerts.minutes(2)), (5, L10n.Alerts.minutes(5))]
    }
}

/// A rule with its switch: the Alerts page and a module's 提醒 tab. Off rules read grey.
struct AlertRuleRow: View {
    var rule: Alerts.Rule
    var showsIcon = true
    var minHeight: CGFloat = 42
    /// Pointed out after arriving from a chart or a module's settings.
    var highlighted = false
    var settings = SettingsStore.shared

    var body: some View {
        let on = settings.prefs[keyPath: rule.enabledKey]
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if showsIcon {
                    LineIcon(d: Icons.module(rule.module), size: 16, lineWidth: 1.5)
                        .foregroundStyle(on ? Theme.hue(rule.module) ?? Theme.sub : Theme.sub)
                        .accessibilityHidden(true)
                }
                AlertRuleSentence(rule: rule).foregroundStyle(on ? Theme.text : Theme.sub)
            }
            Spacer(minLength: 8)
            if settings.prefs.isEnabled(rule.module) {
                RinSwitch(isOn: pref(rule.enabledKey), label: AlertText.name(rule))
            } else {
                Text(L10n.Alerts.moduleOff).ui(12).foregroundStyle(Theme.sub).lineLimit(1).fixedSize()
            }
        }
        .opacity(settings.prefs.isEnabled(rule.module) ? 1 : 0.5)
        .frame(minHeight: minHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.color(for: rule.module).opacity(highlighted ? 0.12 : 0))
                .padding(.horizontal, -8)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Chart label

/// Raised interval chip for the public IP rule: quick presets plus a custom seconds/minutes popover.
private struct PublicIPIntervalChoice: View {
    @Binding var selection: Double
    @State private var customOpen = false
    @State private var draft = ""
    @State private var unit: Unit = .seconds
    @FocusState private var focused: Bool

    private enum Unit: Hashable { case seconds, minutes }

    private static let presets: [Double] = [3, 5, 10, 30, 60, 300, 600]

    private var currentSeconds: Int { max(1, Int(selection.rounded())) }
    private var isCustom: Bool { !Self.presets.contains(where: { Int($0) == currentSeconds }) }

    private var parsedSeconds: Double? {
        guard let n = Int(draft), n >= 1 else { return nil }
        let limit = unit == .minutes ? 60 : 3600
        guard n <= limit else { return nil }
        return Double(unit == .minutes ? n * 60 : n)
    }

    var body: some View {
        Menu {
            ForEach(Self.presets, id: \.self) { seconds in
                let title = AlertText.interval(seconds)
                Button {
                    selection = seconds
                } label: {
                    if Int(seconds) == currentSeconds { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
            Divider()
            Button {
                openCustom()
            } label: {
                if isCustom { Label(L10n.Settings.customEllipsis, systemImage: "checkmark") } else { Text(L10n.Settings.customEllipsis) }
            }
        } label: {
            Text(AlertText.interval(selection))
                .ui(14, 500)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.chip))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.Settings.publicIPIntervalA11y)
        .popover(isPresented: $customOpen, arrowEdge: .bottom) { customPopover }
    }

    private func openCustom() {
        let s = currentSeconds
        if s >= 60 && s % 60 == 0 {
            unit = .minutes
            draft = "\(s / 60)"
        } else {
            unit = .seconds
            draft = "\(s)"
        }
        DispatchQueue.main.async { customOpen = true }
    }

    private func applyCustom() {
        guard let seconds = parsedSeconds else { return }
        selection = seconds
        customOpen = false
    }

    private var customPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.publicIPCustomTitle).ui(12, 500).foregroundStyle(Theme.sub)
            HStack(spacing: 8) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .ui(14)
                    .monospacedDigit()
                    .frame(width: 68)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
                    .focused($focused)
                    .onSubmit { applyCustom() }
                    .onChange(of: draft) { _, v in
                        let digits = v.filter { $0.isASCII && $0.isNumber }
                        if digits != v { draft = digits }
                    }
                    .accessibilityLabel(L10n.Settings.publicIPIntervalA11y)
                Segmented(label: L10n.Settings.publicIPCustomTitle,
                          options: [(Unit.seconds, L10n.Settings.unitSeconds), (.minutes, L10n.Settings.unitMinutes)],
                          selection: $unit)
                    .fixedSize()
            }
            Text(unit == .seconds ? L10n.Settings.publicIPRangeSeconds : L10n.Settings.publicIPRangeMinutes)
                .ui(12)
                .foregroundStyle(Theme.sub)
            PrimaryButton(title: L10n.Settings.apply, height: 28, radius: 7, fontSize: 12) { applyCustom() }
                .disabled(parsedSeconds == nil)
                .opacity(parsedSeconds == nil ? 0.45 : 1)
        }
        .foregroundStyle(Theme.text)
        .padding(14)
        .frame(width: 224)
        .onAppear { focused = true }
    }
}
