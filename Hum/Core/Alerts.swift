import AppKit
import Foundation
import Observation
import UserNotifications

/// One time a rule fired, kept for the Alerts page's "最近触发" list. Readings are stored raw
/// and turned into text when shown, so the list follows the app's language.
struct AlertEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var rule: Alerts.Rule
    var date: Date
    /// The reading: percent (CPU, GPU, battery), 0...1 (Bluetooth), bytes free (disk), °C, or a
    /// memory pressure level.
    var value: Double
    /// The rule's limit when it fired, in the same unit.
    var limit: Double
    /// Seconds the condition had held.
    var held: Double = 0
    /// The device or volume it is about.
    var subject: String?
    /// The busiest process at the time and its share ("71%", "3.2 GB").
    var culprit: String?
    var culpritValue: String?
    /// Seconds until empty (battery, Bluetooth), when known.
    var timeLeft: Double?
    /// When the condition cleared, and the reading then.
    var ended: Date?
    var endValue: Double?
    var seen = false
}

/// Evaluates the alert rules after every sample, colors the menu bar, posts notifications that
/// name the process behind the problem and keeps a record of what fired. A rule fires once per
/// episode, at most every 10 minutes.
@Observable
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    enum Rule: String, CaseIterable, Codable {
        case cpu, gpu, memory, network, disk, battery, bluetoothLow, bluetoothDisconnect, temperature

        var module: Module {
            switch self {
            case .cpu: return .cpu
            case .gpu: return .gpu
            case .memory: return .memory
            case .disk: return .disk
            case .battery: return .battery
            case .temperature: return .sensors
            case .network: return .network
            case .bluetoothLow, .bluetoothDisconnect: return .bluetooth
            }
        }

        var enabledKey: WritableKeyPath<Preferences, Bool> {
            switch self {
            case .cpu: return \.alerts.cpuOn
            case .gpu: return \.alerts.gpuOn
            case .memory: return \.alerts.memoryOn
            case .network: return \.alerts.networkOn
            case .disk: return \.alerts.diskOn
            case .battery: return \.alerts.batteryOn
            case .bluetoothLow: return \.alerts.bluetoothLowOn
            case .bluetoothDisconnect: return \.alerts.bluetoothDisconnectOn
            case .temperature: return \.alerts.tempOn
            }
        }

        func isOn(_ p: Preferences) -> Bool { p.alerts.enabled && p[keyPath: enabledKey] }

        /// The rule a module page's chart offers.
        static func primary(for module: Module) -> Rule {
            switch module {
            case .cpu: return .cpu
            case .gpu: return .gpu
            case .memory: return .memory
            case .network: return .network
            case .disk: return .disk
            case .battery: return .battery
            case .bluetooth: return .bluetoothLow
            case .sensors: return .temperature
            }
        }
    }

    /// Menu bar tint per module while a rule holds.
    private(set) var active: [Module: BarTone] = [:]
    /// Newest first.
    private(set) var events: [AlertEvent] = []
    /// Rules silenced from the overview banner or a notification, until the date.
    private(set) var snoozed: [Rule: Date] = [:]

    @ObservationIgnored private var since: [Rule: Date] = [:]
    /// The event of each rule's current episode.
    @ObservationIgnored private var open: [Rule: UUID] = [:]
    @ObservationIgnored private var lastFired: [Rule: Date] = [:]
    @ObservationIgnored private var authorized = false
    @ObservationIgnored private var askedAuthorization = false
    @ObservationIgnored private var everConnected = false
    /// Bluetooth devices already reported low (until they charge back up), and the ones
    /// connected at the last reading.
    @ObservationIgnored private var lowReported: [String: UUID] = [:]
    @ObservationIgnored private var lastConnected: [String: String]?
    @ObservationIgnored private var disconnected: [String: UUID] = [:]
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSave = Date.distantPast

    private static let cooldown: TimeInterval = 600
    static let snoozeLength: TimeInterval = 3600
    private static let keptEvents = 100
    private static let keptDays: TimeInterval = 30 * 86400
    private static let viewAction = "view"
    private static let snoozeAction = "snooze"
    private static let category = "hum.alert"

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Hum", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("alerts.json")
    }

    // MARK: Record

    /// Triggers not looked at yet (the sidebar badge).
    var unseenCount: Int { events.lazy.filter { !$0.seen }.count }

    var thisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return events.filter { week.contains($0.date) }.count
    }

    /// The newest episode still going and not snoozed (the overview banner).
    var current: AlertEvent? {
        let now = Date()
        return events.first { $0.ended == nil && $0.rule != .bluetoothDisconnect && (snoozed[$0.rule].map { $0 <= now } ?? true) }
    }

    /// The live episode of a rule, if it holds now.
    func firing(_ rule: Rule) -> AlertEvent? {
        guard let id = open[rule] else { return nil }
        return events.first { $0.id == id }
    }

    func markAllSeen() {
        guard events.contains(where: { !$0.seen }) else { return }
        for i in events.indices { events[i].seen = true }
        save()
    }

    func markSeen(_ id: UUID) {
        guard let i = events.firstIndex(where: { $0.id == id }), !events[i].seen else { return }
        events[i].seen = true
        save()
    }

    func snooze(_ rule: Rule) {
        snoozed[rule] = Date().addingTimeInterval(Self.snoozeLength)
        if let id = open[rule] { markSeen(id) }
    }

    /// Opens the page an event is about.
    func show(_ event: AlertEvent) {
        markSeen(event.id)
        MainWindowController.shared.show(.monitor(event.rule.module))
    }

    // MARK: Set up

    func setUp() {
        load()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let view = UNNotificationAction(identifier: Self.viewAction, title: L10n.Alerts.view, options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: L10n.Alerts.snooze, options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [view, snooze], intentIdentifiers: [])])
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard !askedAuthorization else { return }
        askedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.authorized = granted }
        }
    }

    // MARK: Evaluate

    func evaluate() {
        let prefs = SettingsStore.shared.prefs
        let a = prefs.alerts
        let s = Monitor.shared.snapshot
        guard a.enabled else {
            if !active.isEmpty { active = [:] }
            for rule in Rule.allCases { close(rule, at: s.date, value: nil) }
            since = [:]
            return
        }
        requestAuthorizationIfNeeded()
        let now = s.date
        var next: [Module: BarTone] = [:]

        /// Starts, updates and ends one rule's episode. `make` fills in the event when it fires.
        func check(_ rule: Rule, enabled: Bool, condition: Bool, after: TimeInterval, tone: BarTone, endValue: Double? = nil,
                   update: ((inout AlertEvent) -> Void)? = nil, make: () -> AlertEvent) {
            guard enabled, condition else {
                since[rule] = nil
                close(rule, at: now, value: endValue)
                return
            }
            let start = since[rule] ?? now
            since[rule] = start
            guard now.timeIntervalSince(start) >= after else { return }
            next[rule.module] = tone
            if let id = open[rule], let i = events.firstIndex(where: { $0.id == id }) {
                events[i].held = now.timeIntervalSince(start)
                update?(&events[i])
                dirty = true
                return
            }
            guard open[rule] == nil else { return }
            if let last = lastFired[rule], now.timeIntervalSince(last) < Self.cooldown {
                open[rule] = UUID()   // this episode stays quiet
                return
            }
            lastFired[rule] = now
            var event = make()
            event.held = now.timeIntervalSince(start)
            record(event, open: rule)
            notify(event, sound: a.sound)
        }

        let top = s.processes.byCPU.first
        check(.cpu, enabled: a.cpuOn, condition: s.cpu.total * 100 >= a.cpuThreshold, after: a.cpuMinutes * 60, tone: .warn,
              update: { $0.value = s.cpu.total * 100 }) {
            AlertEvent(rule: .cpu, date: now, value: s.cpu.total * 100, limit: a.cpuThreshold,
                       culprit: top?.name, culpritValue: top.map { Format.percentValue($0.cpu) })
        }

        // Per-process GPU usage is only read while a GPU view is open, so the culprit may be missing.
        let gpuTop = s.processes.byGPU.first
        check(.gpu, enabled: a.gpuOn, condition: s.gpu.utilization * 100 >= a.gpuThreshold, after: a.gpuMinutes * 60, tone: .warn,
              update: { $0.value = s.gpu.utilization * 100 }) {
            AlertEvent(rule: .gpu, date: now, value: s.gpu.utilization * 100, limit: a.gpuThreshold,
                       culprit: gpuTop?.name, culpritValue: gpuTop.map { Format.percentValue($0.gpu) })
        }

        let memTop = s.processes.byMemory.first
        check(.memory, enabled: a.memoryOn, condition: s.memory.pressure.rawValue >= a.memoryLevel.rawValue, after: 10,
              tone: a.memoryLevel == .critical ? .crit : .warn) {
            AlertEvent(rule: .memory, date: now, value: Double(s.memory.pressure.rawValue), limit: Double(a.memoryLevel.rawValue),
                       culprit: memTop?.name, culpritValue: memTop.map { Format.memory($0.memory) })
        }

        let root = s.disk.root
        let limitBytes = a.diskFreeGB * 1_000_000_000
        check(.disk, enabled: a.diskOn, condition: root.map { Double($0.available) < limitBytes } ?? false, after: 0, tone: .warn,
              endValue: root.map { Double($0.available) }, update: { e in root.map { e.value = Double($0.available) } }) {
            AlertEvent(rule: .disk, date: now, value: Double(root?.available ?? 0), limit: limitBytes, subject: root?.name)
        }

        let b = s.battery
        check(.battery, enabled: a.batteryOn && b.hasBattery, condition: b.level * 100 <= a.batteryPercent && !b.onAC, after: 0, tone: .crit,
              update: { $0.value = b.level * 100 }) {
            AlertEvent(rule: .battery, date: now, value: b.level * 100, limit: a.batteryPercent, timeLeft: b.minutesToEmpty.map { Double($0) * 60 })
        }

        let temp = s.sensors.cpuAverage ?? 0
        check(.temperature, enabled: a.tempOn, condition: temp >= a.tempThreshold, after: 10, tone: .crit, update: { $0.value = temp }) {
            AlertEvent(rule: .temperature, date: now, value: temp, limit: a.tempThreshold,
                       culprit: top?.name, culpritValue: top.map { Format.percentValue($0.cpu) })
        }

        // Network: only counts after the Mac has been online during this session.
        let connected = s.network.connected
        if connected { everConnected = true }
        // The link it came back on names the recovery ("Wi-Fi 已自动重新连接").
        check(.network, enabled: a.networkOn, condition: !connected && everConnected, after: 5, tone: .dim,
              endValue: connected ? Double(Self.kindCode(s.network.kind)) : nil) {
            AlertEvent(rule: .network, date: now, value: 0, limit: 0)
        }

        checkBluetooth(s, a, prefs)

        if next != active { active = next }
        // Rule state lands on disk now and then; firing and clearing save at once.
        if dirty, now.timeIntervalSince(lastSave) > 60 { save() }
    }

    /// Per device, so these keep their own memory instead of the module-wide rule state.
    private func checkBluetooth(_ s: Snapshot, _ a: AlertPrefs, _ prefs: Preferences) {
        guard s.monitored.contains(.bluetooth) else { lastConnected = nil; return }
        let low = prefs.bluetooth.lowLevel
        let now = s.date
        for d in s.bluetooth.withBattery {
            let level = d.level ?? 1
            if level > low + 0.05 || d.charging, let id = lowReported.removeValue(forKey: d.id) { end(id, at: now, value: level) }
            guard a.bluetoothLowOn, level <= low, !d.charging, lowReported[d.id] == nil else { continue }
            var event = AlertEvent(rule: .bluetoothLow, date: now, value: level, limit: low, subject: d.name)
            event.timeLeft = BluetoothStore.shared.timeLeft(d.id, level: level)
            lowReported[d.id] = event.id
            record(event, open: nil)
            notify(event, sound: a.sound)
        }
        let connected = Dictionary(s.bluetooth.connected.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for (id, eventID) in disconnected where connected[id] != nil {
            end(eventID, at: now, value: 1)
            disconnected[id] = nil
        }
        if a.bluetoothDisconnectOn, let before = lastConnected {
            for (id, name) in before where connected[id] == nil {
                let event = AlertEvent(rule: .bluetoothDisconnect, date: now, value: 0, limit: 0, subject: name)
                disconnected[id] = event.id
                record(event, open: nil)
                notify(event, sound: a.sound)
            }
        }
        lastConnected = connected
    }

    private func record(_ event: AlertEvent, open rule: Rule?) {
        if let rule { open[rule] = event.id }
        events.insert(event, at: 0)
        let cutoff = Date().addingTimeInterval(-Self.keptDays)
        events = Array(events.filter { $0.date > cutoff }.prefix(Self.keptEvents))
        save()
    }

    private func close(_ rule: Rule, at date: Date, value: Double?) {
        guard let id = open.removeValue(forKey: rule) else { return }
        end(id, at: date, value: value)
    }

    private func end(_ id: UUID, at date: Date, value: Double?) {
        guard let i = events.firstIndex(where: { $0.id == id }), events[i].ended == nil else { return }
        events[i].ended = date
        if let value { events[i].endValue = value }
        save()
    }

    #if DEBUG
    /// Snapshots: fills the record with sample triggers.
    func debugSeed(_ seed: [AlertEvent], open rule: Rule?) {
        events = seed
        if let rule, let first = seed.first { open[rule] = first.id }
    }
    #endif

    // MARK: Notify

    private func notify(_ event: AlertEvent, sound: Bool) {
        if let until = snoozed[event.rule], until > Date() { return }
        let content = UNMutableNotificationContent()
        content.title = AlertText.notificationTitle(event)
        content.body = AlertText.notificationBody(event)
        if sound { content.sound = .default }
        content.userInfo = ["rule": event.rule.rawValue, "event": event.id.uuidString]
        content.categoryIdentifier = Self.category
        let request = UNNotificationRequest(identifier: "hum.\(event.rule.rawValue).\(event.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func kindCode(_ kind: InterfaceKind) -> Int {
        switch kind {
        case .wifi: return 1
        case .ethernet: return 2
        case .vpn: return 3
        case .other: return 0
        }
    }

    // MARK: Store

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([AlertEvent].self, from: data) else { return }
        // Episodes from an earlier run can't still be going.
        events = decoded.map { e in
            var e = e
            if e.ended == nil { e.ended = e.date.addingTimeInterval(max(e.held, 0)) }
            return e
        }
    }

    private func save() {
        dirty = false
        lastSave = Date()
        guard SettingsStore.persistenceEnabled, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    func flush() {
        if dirty { save() }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            if let raw = info["rule"] as? String, let rule = Rule(rawValue: raw) {
                let id = (info["event"] as? String).flatMap(UUID.init(uuidString:))
                if response.actionIdentifier == Self.snoozeAction {
                    self.snooze(rule)
                } else if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                    if let id { self.markSeen(id) }
                    MainWindowController.shared.show(Page.monitor(rule.module))
                }
            }
            completionHandler()
        }
    }
}
