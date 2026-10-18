import Foundation
import IOKit

/// Paired Bluetooth accessories and their batteries. Magic keyboards, mice and trackpads report
/// through the IORegistry; system_profiler adds AirPods and other headphones (with each bud and
/// the case), device types, and the paired devices that are not connected right now.
final class BluetoothReader {
    private let store = BluetoothStore.shared

    func read(now: Date = Date()) -> BluetoothSample {
        let hid = Self.hidDevices()
        let listed = Self.profiler()
        var connected: [BluetoothDevice] = []
        var seen = Set<String>()

        for var device in listed.connected {
            if let level = hid[device.id]?.level { device.level = level }
            connected.append(device)
            seen.insert(device.id)
        }
        // Accessories the IORegistry knows but system_profiler didn't list.
        for (id, entry) in hid where !seen.contains(id) {
            connected.append(BluetoothDevice(id: id, name: entry.name, kind: Self.kind(name: entry.name, minorType: nil), level: entry.level))
        }
        connected = connected.filter { $0.level != nil || $0.kind != .other }
        store.record(connected, now: now)

        let connectedIDs = Set(connected.map(\.id))
        var disconnected: [BluetoothDevice] = []
        for var device in listed.notConnected where !connectedIDs.contains(device.id) {
            let known = store.device(device.id)
            // Only accessories: skip paired phones and computers Hum never saw with a battery.
            guard known != nil || device.level != nil || ![.other, .phone, .tablet].contains(device.kind) else { continue }
            device.level = device.level ?? known?.level
            device.lastSeen = known?.lastSeen
            disconnected.append(device)
        }
        connected.sort { ($0.level ?? 2) < ($1.level ?? 2) }
        disconnected.sort { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
        for i in connected.indices { connected[i].lastSeen = now }
        return BluetoothSample(connected: connected, disconnected: disconnected)
    }

    // MARK: Sources

    private static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    private static func hidDevices() -> [String: (name: String, level: Double)] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == kIOReturnSuccess else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: (name: String, level: Double)] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func property<T>(_ key: String) -> T? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
            }
            guard let percent: Int = property("BatteryPercent"), let name: String = property("Product") else { continue }
            let address: String = property("DeviceAddress") ?? name
            result[normalize(address)] = (name, Double(percent) / 100)
        }
        return result
    }

    private static func profiler() -> (connected: [BluetoothDevice], notConnected: [BluetoothDevice]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return ([], []) }

        func percent(_ value: Any?) -> Double? {
            guard let s = value as? String else { return nil }
            return Double(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map { $0 / 100 }
        }
        func devices(_ key: String, connected: Bool) -> [BluetoothDevice] {
            controllers.flatMap { ($0[key] as? [[String: Any]]) ?? [] }.flatMap { entry in
                entry.compactMap { name, value -> BluetoothDevice? in
                    guard let info = value as? [String: Any], let address = info["device_address"] as? String else { return nil }
                    let left = percent(info["device_batteryLevelLeft"])
                    let right = percent(info["device_batteryLevelRight"])
                    let box = percent(info["device_batteryLevelCase"])
                    let main = percent(info["device_batteryLevelMain"]) ?? [left, right].compactMap { $0 }.min()
                    var kind = kind(name: name, minorType: info["device_minorType"] as? String)
                    if kind == .headphones && (left != nil || right != nil) { kind = .earbuds }
                    return BluetoothDevice(id: normalize(address), name: name, kind: kind, level: main, connected: connected,
                                           left: left, right: right, caseLevel: box)
                }
            }
        }
        return (devices("device_connected", connected: true), devices("device_not_connected", connected: false))
    }

    static func kind(name: String, minorType: String?) -> BluetoothDevice.Kind {
        let type = (minorType ?? "").lowercased(), lower = name.lowercased()
        if type.contains("keyboard") || lower.contains("keyboard") { return .keyboard }
        if type.contains("trackpad") || lower.contains("trackpad") { return .trackpad }
        if type.contains("mouse") || lower.contains("mouse") { return .mouse }
        if type.contains("headphone") || type.contains("headset") || lower.contains("airpods") { return lower.contains("max") ? .headphones : .earbuds }
        if type.contains("gamepad") || type.contains("joystick") || lower.contains("controller") { return .gamepad }
        if type.contains("phone") || lower.contains("iphone") { return .phone }
        if type.contains("tablet") || lower.contains("ipad") { return .tablet }
        return .other
    }
}

/// What Hum remembers about each device across launches: its name and kind, the last battery
/// and time it was seen connected, and a battery history (a point when the level changes, or
/// every half hour) for the charts and time-left estimates. Thirty days are kept. Written by
/// the sampler, read by the views, so access goes through a lock.
final class BluetoothStore {
    static let shared = BluetoothStore()

    struct Point: Codable { var date: Date; var level: Double }
    struct Device: Codable {
        var name: String
        var kind: BluetoothDevice.Kind
        var level: Double?
        var lastSeen: Date
        var history: [Point] = []
    }

    private var devices: [String: Device] = [:]
    private let lock = NSLock()
    private let url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Hum", isDirectory: true).appendingPathComponent("bluetooth.json")
    private static let keep: TimeInterval = 30 * 86_400

    init() {
        if let url, let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Device].self, from: data) {
            devices = decoded
        }
    }

    func device(_ id: String) -> Device? {
        lock.lock(); defer { lock.unlock() }
        return devices[id]
    }

    func record(_ connected: [BluetoothDevice], now: Date) {
        lock.lock()
        defer { lock.unlock() }
        for device in connected {
            var entry = devices[device.id] ?? Device(name: device.name, kind: device.kind, level: nil, lastSeen: now)
            entry.name = device.name
            entry.kind = device.kind
            entry.lastSeen = now
            if let level = device.level {
                entry.level = level
                let last = entry.history.last
                if last == nil || abs(last!.level - level) >= 0.005 || now.timeIntervalSince(last!.date) >= 1800 {
                    entry.history.append(Point(date: now, level: level))
                }
            }
            entry.history.removeAll { now.timeIntervalSince($0.date) > Self.keep }
            devices[device.id] = entry
        }
        save()
    }

    func history(_ id: String) -> [Point] { device(id)?.history ?? [] }

    /// Time until empty from the current run of discharge (at least two hours and 3% long).
    func timeLeft(_ id: String, level: Double, now: Date = Date()) -> TimeInterval? {
        let points = history(id)
        guard var end = points.last else { return nil }
        var start = end
        for p in points.reversed().dropFirst() {
            if p.level + 0.02 < start.level { break }     // charged up here: the run starts after it
            start = p
        }
        end = points.last!
        let drop = start.level - end.level, span = end.date.timeIntervalSince(start.date)
        guard drop >= 0.03, span >= 7200 else { return nil }
        return level / (drop / span)
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(devices) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
