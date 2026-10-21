import Foundation

/// Words for alert events and rules: the record's rows, the overview banner, notifications and
/// the chart labels.
enum AlertText {
    private static var unit: TemperatureUnit { SettingsStore.shared.prefs.general.temperatureUnit }

    private static func percent(_ value: Double) -> String { Format.percent(value / 100) }

    /// "30 秒", "4 分钟", "1 小时 12 分".
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return L10n.Alerts.seconds(max(1, s)) }
        if s < 3600 { return L10n.Alerts.minutes(s / 60) }
        return L10n.Sleep.hoursMinutes(s / 3600, (s % 3600) / 60)
    }

    /// Free space in whole gigabytes, as the rule's limit reads ("18 GB", "20 GB").
    private static func gigabytes(_ bytes: Double) -> String {
        bytes < 1e12 ? L10n.Settings.gigabytes(Int((bytes / 1e9).rounded())) : Format.storage(bytes)
    }

    private static func pressure(_ level: Double) -> String {
        Int(level) >= MemoryPressure.critical.rawValue ? L10n.Settings.red : L10n.Settings.yellow
    }

    private static func culprit(_ e: AlertEvent) -> String? {
        guard let name = e.culprit, let value = e.culpritValue else { return nil }
        return L10n.Alerts.culpritDetail(name, value)
    }

    /// A row in "最近触发": "CPU 使用率 94%，超过 90% 已 1 分钟".
    static func headline(_ e: AlertEvent) -> String {
        switch e.rule {
        case .cpu: return L10n.Alerts.cpuHeadline(percent(e.value), percent(e.limit), duration(e.held))
        case .gpu: return L10n.Alerts.gpuHeadline(percent(e.value), percent(e.limit), duration(e.held))
        case .memory: return L10n.Alerts.memoryHeadline(pressure(e.value))
        case .disk: return L10n.Alerts.diskHeadline(e.subject ?? "", gigabytes(e.value), gigabytes(e.limit))
        case .battery: return L10n.Alerts.batteryHeadline(percent(e.value), percent(e.limit))
        case .temperature:
            return L10n.Alerts.tempHeadline(Format.temperature(e.value, unit: unit, showUnit: true),
                                            Format.temperature(e.limit, unit: unit, showUnit: true))
        case .network:
            guard let ended = e.ended else { return L10n.Alerts.networkDown }
            return L10n.Alerts.networkDownFor(duration(ended.timeIntervalSince(e.date) + e.held))
        case .bluetoothLow: return L10n.Alerts.bluetoothLowHeadline(e.subject ?? "", Format.percent(e.value), Format.percent(e.limit))
        case .bluetoothDisconnect: return L10n.Alerts.bluetoothDisconnectTitle(e.subject ?? "")
        }
    }

    /// The grey line under a row: who was busiest, how long is left, or how it ended.
    static func detail(_ e: AlertEvent) -> String? {
        switch e.rule {
        case .cpu, .gpu, .memory, .temperature:
            return culprit(e) ?? (e.ended != nil ? L10n.Alerts.recovered : nil)
        case .disk:
            guard e.ended != nil else { return nil }
            return e.endValue.map { L10n.Alerts.diskRecovered(Format.storage($0)) } ?? L10n.Alerts.recovered
        case .battery, .bluetoothLow:
            if e.ended != nil { return L10n.Alerts.recovered }
            return e.timeLeft.map { L10n.Alerts.untilEmpty(estimate($0)) }
        case .network:
            guard e.ended != nil else { return nil }
            switch Int(e.endValue ?? 0) {
            case 1: return L10n.Alerts.reconnected(L10n.Panel.wifi)
            case 2: return L10n.Alerts.reconnected(L10n.Panel.ethernet)
            case 3: return L10n.Alerts.reconnected(L10n.Alerts.vpn)
            default: return L10n.Alerts.reconnectedPlain
            }
        case .bluetoothDisconnect:
            return e.ended != nil ? L10n.Alerts.reconnectedPlain : nil
        }
    }

    /// The overview's banner: "CPU 使用率 94%，已超过 90% 1 分钟".
    static func banner(_ e: AlertEvent) -> String {
        switch e.rule {
        case .cpu: return L10n.Alerts.cpuBanner(percent(e.value), percent(e.limit), duration(e.held))
        case .gpu: return L10n.Alerts.gpuBanner(percent(e.value), percent(e.limit), duration(e.held))
        default: return headline(e)
        }
    }

    static func notificationTitle(_ e: AlertEvent) -> String {
        switch e.rule {
        case .cpu: return L10n.Alerts.cpuTitle
        case .gpu: return L10n.Alerts.gpuTitle
        case .memory: return L10n.Alerts.memoryTitle
        case .disk: return L10n.Alerts.diskTitle
        case .battery: return L10n.Alerts.batteryTitle
        case .temperature: return L10n.Alerts.tempTitle
        case .network: return L10n.Alerts.networkTitle
        case .bluetoothLow: return L10n.Alerts.bluetoothLowTitle(e.subject ?? "")
        case .bluetoothDisconnect: return L10n.Alerts.bluetoothDisconnectTitle(e.subject ?? "")
        }
    }

    /// "94%，已超过 90% 1 分钟。Xcode 占用最多（71%）。"
    static func notificationBody(_ e: AlertEvent) -> String {
        var sentences: [String] = []
        switch e.rule {
        case .cpu, .gpu: sentences.append(L10n.Alerts.overFor(percent(e.value), percent(e.limit), duration(e.held)))
        case .memory: sentences.append(L10n.Alerts.memoryBody)
        case .disk: sentences.append(L10n.Alerts.diskBody(e.subject ?? "", gigabytes(e.value)))
        case .battery: sentences.append(L10n.Alerts.batteryBody(percent(e.value)))
        case .temperature: sentences.append(L10n.Alerts.tempBody(Format.temperature(e.value, unit: unit, showUnit: true)))
        case .network: sentences.append(L10n.Alerts.networkBody)
        case .bluetoothLow: sentences.append(L10n.Alerts.bluetoothLowBody(Format.percent(e.value)))
        case .bluetoothDisconnect: sentences.append(L10n.Alerts.bluetoothDisconnectBody)
        }
        if let name = e.culprit, let value = e.culpritValue { sentences.append(L10n.Alerts.culpritSentence(name, value)) }
        return sentences.joined(separator: L10n.Alerts.sentenceGap)
    }

    /// "约 2 天", "约 4 小时".
    static func estimate(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours < 1 { return L10n.Bluetooth.underHour }
        if hours < 48 { return L10n.Bluetooth.hours(Int(hours.rounded())) }
        let days = hours / 24
        if days < 14 { return L10n.Bluetooth.days(Int(days.rounded())) }
        return L10n.Bluetooth.weeks(Int((days / 7).rounded()))
    }

    /// What the chart's alert label says about a rule that is on ("90%", "压力变红时").
    static func pill(_ rule: Alerts.Rule, _ p: Preferences) -> String {
        let a = p.alerts
        switch rule {
        case .cpu: return percent(a.cpuThreshold)
        case .gpu: return percent(a.gpuThreshold)
        case .memory: return a.memoryLevel == .critical ? L10n.Alerts.pillPressureRed : L10n.Alerts.pillPressureYellow
        case .disk: return L10n.Alerts.pillFreeBelow(L10n.Settings.gigabytes(Int(a.diskFreeGB)))
        case .battery: return L10n.Alerts.pillBelow(percent(a.batteryPercent))
        case .temperature: return Format.temperature(a.tempThreshold, unit: unit, showUnit: true)
        case .network, .bluetoothDisconnect: return L10n.Alerts.pillDisconnect
        case .bluetoothLow: return Format.percent(p.bluetooth.lowLevel)
        }
    }

    /// The rule's switch label and popover title ("CPU 使用率提醒").
    static func name(_ rule: Alerts.Rule) -> String {
        switch rule {
        case .cpu: return L10n.Settings.ruleCPUSwitch
        case .gpu: return L10n.Settings.ruleGPUSwitch
        case .memory: return L10n.Settings.ruleMemorySwitch
        case .network: return L10n.Settings.ruleNetworkSwitch
        case .disk: return L10n.Settings.ruleDiskSwitch
        case .battery: return L10n.Settings.ruleBatterySwitch
        case .bluetoothLow: return L10n.Settings.bluetoothLowAlertA11y
        case .bluetoothDisconnect: return L10n.Settings.bluetoothDisconnectAlertA11y
        case .temperature: return L10n.Settings.ruleTempSwitch
        }
    }
}
