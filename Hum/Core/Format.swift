import Foundation

/// Number formatting shared by every surface. Units are SI symbols, so they are not localized.
enum Format {
    /// Stands in for a value inside a localized template, so the value can be styled apart.
    static let marker = "\u{1}"

    /// 0...1 → "23%"
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    /// Already a percentage (Activity Monitor style, may exceed 100) → "38.2%"
    static func percentValue(_ value: Double) -> String {
        if value >= 100 { return "\(Int(value.rounded()))%" }
        return String(format: "%.1f%%", value)
    }

    /// Memory uses binary units (what Activity Monitor shows).
    static func memory(_ bytes: UInt64) -> String { memory(Double(bytes)) }

    static func memory(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        if gb >= 1 { return gb >= 100 ? "\(Int(gb.rounded())) GB" : String(format: "%.1f GB", gb) }
        let mb = bytes / 1_048_576
        if mb >= 1000 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return "\(Int(mb.rounded())) MB" }
        return "\(Int((bytes / 1024).rounded())) KB"
    }

    /// Storage and traffic use decimal units (what Finder shows).
    static func storage(_ bytes: Int64) -> String { storage(Double(bytes)) }
    static func storage(_ bytes: UInt64) -> String { storage(Double(bytes)) }

    static func storage(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = bytes
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        if i == 0 { return "\(Int(value)) B" }
        if value >= 100 || i <= 1 { return "\(Int(value.rounded())) \(units[i])" }
        return String(format: "%.1f %@", value, units[i])
    }

    /// Network / disk throughput → "2.4 MB/s", "120 KB/s", or "19 Mbps" in bits.
    static func rate(_ bytesPerSecond: Double, unit: SpeedUnit = .auto, showUnit: Bool = true) -> String {
        let (value, suffix) = scaledRate(bytesPerSecond, unit: unit)
        let number: String
        if value >= 100 || suffix.hasPrefix("B") || suffix == "bps" { number = "\(Int(value.rounded()))" }
        else if value >= 10 { number = String(format: "%.0f", value) }
        else { number = String(format: "%.1f", value) }
        return showUnit ? "\(number) \(suffix)" : number
    }

    /// A rate in the chosen unit style: "120 KB/s", "120 KB" or "120K"; just the number without a unit.
    static func rate(_ bytesPerSecond: Double, unit: SpeedUnit, style: RateUnitStyle, showUnit: Bool) -> String {
        guard showUnit else { return rate(bytesPerSecond, unit: unit, showUnit: false) }
        switch style {
        case .perSecond: return rate(bytesPerSecond, unit: unit)
        case .bytes: return rate(bytesPerSecond, unit: unit).replacingOccurrences(of: "ps", with: "").replacingOccurrences(of: "/s", with: "")
        case .letter: return rateCompact(bytesPerSecond, unit: unit)
        }
    }

    /// The widest value a rate can show in that style, for fixed-width layouts.
    static func rateTemplate(unit: SpeedUnit, style: RateUnitStyle, showUnit: Bool) -> String {
        guard showUnit else { return "999" }
        let bits = unit == .bits
        switch style {
        case .perSecond: return bits ? "999 Mbps" : "999 MB/s"
        case .bytes: return bits ? "999 Mb" : "999 MB"
        case .letter: return "999M"
        }
    }

    /// Menu bar shorthand → "2.4M", "120K".
    static func rateCompact(_ bytesPerSecond: Double, unit: SpeedUnit = .auto) -> String {
        let (value, suffix) = scaledRate(bytesPerSecond, unit: unit)
        let letter = suffix.first.map(String.init) ?? ""
        let short = letter == "B" || letter == "b" ? "B" : letter
        if value >= 10 || short == "B" { return "\(Int(value.rounded()))\(short)" }
        return String(format: "%.1f%@", value, short)
    }

    static func rateParts(_ bytesPerSecond: Double, unit: SpeedUnit = .auto) -> (String, String) {
        let full = rate(bytesPerSecond, unit: unit)
        let parts = full.split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? full, parts.count > 1 ? parts[1] : "")
    }

    private static func scaledRate(_ bytesPerSecond: Double, unit: SpeedUnit) -> (Double, String) {
        if unit == .bits {
            var v = bytesPerSecond * 8
            let units = ["bps", "Kbps", "Mbps", "Gbps"]
            var i = 0
            while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
            return (v, units[i])
        }
        var v = max(0, bytesPerSecond)
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        if unit == .bytes, i == 0 { return (v / 1000, "KB/s") }
        return (v, units[i])
    }

    static func temperature(_ celsius: Double, unit: TemperatureUnit, showUnit: Bool = false) -> String {
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        let n = Int(value.rounded())
        if showUnit { return unit == .celsius ? "\(n) °C" : "\(n) °F" }
        return "\(n)°"
    }

    static func temperatureNumber(_ celsius: Double, unit: TemperatureUnit) -> String {
        "\(Int((unit == .celsius ? celsius : celsius * 9 / 5 + 32).rounded()))"
    }

    static func watts(_ w: Double) -> String {
        w >= 100 ? "\(Int(w.rounded())) W" : String(format: "%.1f W", w)
    }

    static func rpm(_ r: Double) -> String { "\(Int(r.rounded())) rpm" }

    static func frequency(_ mhz: Double) -> String {
        mhz >= 1000 ? String(format: "%.2f GHz", mhz / 1000) : "\(Int(mhz.rounded())) MHz"
    }

    /// Minutes → "0:42"
    static func clockDuration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func load(_ v: Double) -> String { String(format: "%.2f", v) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "今天 9:41" / "昨天 22:14" / "10月15日 8:02"
    static func dayAndTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.Time.today(time(date)) }
        if cal.isDateInYesterday(date) { return L10n.Time.yesterday(time(date)) }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd Hm")
        return f.string(from: date)
    }

    static func uptime(since boot: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(boot) / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return L10n.Overview.uptimeDays(days, hours) }
        if hours > 0 { return L10n.Overview.uptimeHours(hours, minutes % 60) }
        return L10n.Overview.uptimeMinutes(max(1, minutes))
    }
}
