import Foundation
import IOKit
import IOKit.ps

final class BatteryReader {
    /// Whether the Mac is running on its battery right now (cheap; for "slow down on battery"
    /// when the battery module itself is switched off).
    static func onBatteryPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    func read() -> BatterySample {
        var sample = BatterySample()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return sample }

        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let type = d[kIOPSTypeKey] as? String
            let current = (d[kIOPSCurrentCapacityKey] as? Int) ?? 0
            let max = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            let level = max > 0 ? Double(current) / Double(max) : 0
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            if type == kIOPSInternalBatteryType {
                sample.hasBattery = true
                sample.level = level
                sample.onAC = onAC
                sample.isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                sample.isCharged = (d[kIOPSIsChargedKey] as? Bool) ?? false
                if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0 { sample.minutesToEmpty = t }
                if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0 { sample.minutesToFull = t }
            } else if type == kIOPSUPSType {
                sample.ups.append(PowerSource(
                    id: (d[kIOPSNameKey] as? String) ?? UUID().uuidString,
                    name: (d[kIOPSNameKey] as? String) ?? "UPS",
                    level: level,
                    isUPS: true,
                    onAC: onAC,
                    minutesLeft: (d[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
                ))
            }
        }

        if sample.hasBattery { readSmartBattery(into: &sample) }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            sample.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return sample
    }

    private func readSmartBattery(into sample: inout BatterySample) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }

        // Newer models keep the capacity figures inside BatteryData.
        let data = d["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { (d[key] as? Int) ?? (data[key] as? Int) }

        sample.cycles = int("CycleCount")
        if let design = int("DesignCapacity"), design > 0,
           let full = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") {
            // Same figure System Settings shows as "Maximum Capacity".
            sample.health = min(1, Double(full) / Double(design))
            sample.maxCapacity = int("AppleRawMaxCapacity") ?? full
            sample.designCapacity = design
        }
        // Apple's rated endurance (DesignCycleCount9C) when the gauge reports it.
        sample.designCycles = int("DesignCycleCount9C") ?? int("DesignCycleCount") ?? 1000
        if let t = d["Temperature"] as? Int { sample.temperature = Double(t) / 100 }
        if let mv = d["Voltage"] as? Int {
            let ma = (d["InstantAmperage"] as? Int) ?? (d["Amperage"] as? Int) ?? 0
            sample.power = Double(mv) * Double(Int32(truncatingIfNeeded: ma)) / 1_000_000
        }
        if let telemetry = d["PowerTelemetryData"] as? [String: Any], let mw = telemetry["SystemPowerIn"] as? Int, mw > 0 {
            sample.systemPowerIn = Double(mw) / 1000
        }
    }
}

/// Battery levels of Bluetooth accessories: Magic devices via the IORegistry,
/// AirPods via system_profiler (slow, so it is only called while the page is visible).
final class BluetoothReader {
    private var cachedHeadphones: [BluetoothDevice] = []
    private var lastProfiler = Date.distantPast

    func read(includeHeadphones: Bool) -> [BluetoothDevice] {
        var devices = Self.hidDevices()
        if includeHeadphones {
            if Date().timeIntervalSince(lastProfiler) > 60 {
                cachedHeadphones = Self.headphones()
                lastProfiler = Date()
            }
            devices += cachedHeadphones
        }
        return devices
    }

    private static func hidDevices() -> [BluetoothDevice] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [BluetoothDevice] = []
        var seen = Set<String>()
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
            let address = IORegistryEntryCreateCFProperty(entry, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? name
            guard seen.insert(address).inserted else { continue }
            let lower = name.lowercased()
            let kind: BluetoothDevice.Kind = lower.contains("keyboard") ? .keyboard
                : lower.contains("trackpad") ? .trackpad
                : lower.contains("mouse") ? .mouse : .other
            result.append(BluetoothDevice(id: address, name: name, kind: kind, level: Double(percent) / 100))
        }
        return result.sorted { $0.name < $1.name }
    }

    private static func headphones() -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        func percent(_ value: Any?) -> Double? {
            guard let s = value as? String else { return nil }
            return Double(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map { $0 / 100 }
        }

        var result: [BluetoothDevice] = []
        for controller in controllers {
            for entry in (controller["device_connected"] as? [[String: Any]]) ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let left = percent(info["device_batteryLevelLeft"])
                    let right = percent(info["device_batteryLevelRight"])
                    let main = percent(info["device_batteryLevelMain"])
                    let box = percent(info["device_batteryLevelCase"])
                    guard let level = main ?? [left, right].compactMap({ $0 }).min() else { continue }
                    var parts: [String] = []
                    if let left { parts.append(L10n.Battery.budLeft(Int(left * 100))) }
                    if let right { parts.append(L10n.Battery.budRight(Int(right * 100))) }
                    if let box { parts.append(L10n.Battery.budCase(Int(box * 100))) }
                    result.append(BluetoothDevice(
                        id: (info["device_address"] as? String) ?? name,
                        name: name,
                        kind: .headphones,
                        level: level,
                        detail: parts.isEmpty ? nil : parts.joined(separator: " · ")
                    ))
                }
            }
        }
        return result
    }
}
