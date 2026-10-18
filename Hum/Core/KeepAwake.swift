import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation

/// Holds the Mac awake with a power assertion, like `caffeinate`, until the chosen end.
@Observable
final class KeepAwake {
    static let shared = KeepAwake()

    enum Mode: Hashable {
        case indefinite
        case minutes(Int)
        /// Until the next time the clock reads this hour (the "到 18:00" chip).
        case untilHour(Int)
        case whileCharging
        case custom(Date)

        static let presets: [Mode] = [.indefinite, .minutes(15), .minutes(30), .minutes(60), .untilHour(18), .whileCharging]

        /// A fixed end time, for the modes that have one.
        func end(from start: Date) -> Date? {
            switch self {
            case .indefinite, .whileCharging: return nil
            case .minutes(let m): return start.addingTimeInterval(TimeInterval(m * 60))
            case .untilHour(let h): return KeepAwake.next(hour: h, minute: 0, after: start)
            case .custom(let date): return date
            }
        }
    }

    /// Battery level at which keep-awake gives up when `offWhenLow` is on.
    static let lowBattery = 0.2

    private(set) var isOn = false
    /// The chosen mode; kept while off so the chips show what 开启 will start.
    private(set) var mode: Mode = .indefinite
    private(set) var started: Date?
    private(set) var endsAt: Date?

    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0

    private init() {}

    func start(_ mode: Mode) {
        let now = Date()
        self.mode = mode
        if !isOn { started = now }
        endsAt = mode.end(from: now)
        isOn = true
        applyAssertion()
        if timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        check()
    }

    func select(_ mode: Mode) {
        if isOn { start(mode) } else { self.mode = mode }
    }

    func stop() {
        isOn = false
        started = nil
        endsAt = nil
        timer?.invalidate()
        timer = nil
        releaseAssertion()
    }

    /// Re-creates the assertion after the display option changed.
    func preferencesChanged() {
        if isOn { applyAssertion() }
    }

    var holdsDisplay: Bool { SettingsStore.shared.prefs.sleep.keepDisplay }

    private func applyAssertion() {
        releaseAssertion()
        let type = holdsDisplay ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        // An identifier rather than copy: pmset and Activity Monitor print it as is.
        let name = (Bundle.main.bundleIdentifier ?? "com.zoro.hum") + ".keep-awake"
        if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id) == kIOReturnSuccess {
            assertion = id
        }
    }

    private func releaseAssertion() {
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
    }

    /// The end time every second; the power source every ten.
    private func check() {
        guard isOn else { return }
        if let endsAt, Date() >= endsAt { stop(); return }
        ticks += 1
        guard ticks % 10 == 1 else { return }
        let power = Self.power()
        if mode == .whileCharging, power.onBattery { stop(); return }
        if SettingsStore.shared.prefs.sleep.offWhenLow, power.onBattery, let level = power.level, level < Self.lowBattery {
            stop()
        }
    }

    private static func power() -> (onBattery: Bool, level: Double?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let onBattery = (IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return (onBattery, nil) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let max = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            return (onBattery, Double(current) / Double(Swift.max(max, 1)))
        }
        return (onBattery, nil)
    }

    static func next(hour: Int, minute: Int, after date: Date) -> Date {
        let cal = Calendar.current
        var parts = cal.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        let today = cal.date(from: parts) ?? date
        return today > date ? today : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
