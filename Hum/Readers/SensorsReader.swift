import Foundation
import IOKit

/// Temperatures, fans and power. SMC keys are discovered once per launch because they
/// differ between chip generations; HID sensors are the fallback when SMC has nothing.
final class SensorsReader {
    private let smc = SMC()
    private var groups: [TempGroup: [UInt32]] = [:]
    private var fanCount = 0
    private var hasSystemPower = false
    private lazy var hid = HIDTemperatures()

    init() {
        discover()
    }

    private func discover() {
        guard let smc else { return }
        var found: [TempGroup: [UInt32]] = [:]
        for key in smc.allKeys() {
            let name = SMC.string(key)
            guard name.first == "T", let group = Self.group(for: name) else { continue }
            // Skip keys that read nonsense on this model (unpopulated sensors read 0 or negative).
            guard let v = smc.value(key), v > 5, v < 130 else { continue }
            found[group, default: []].append(key)
        }
        // SMC calls cost ~0.1 ms each; a few evenly spread sensors give the same average.
        groups = found.mapValues { keys in
            guard keys.count > 4 else { return keys }
            let step = Double(keys.count) / 4
            return (0..<4).map { keys[Int(Double($0) * step)] }
        }
        fanCount = Int(smc.value("FNum") ?? 0)
        hasSystemPower = smc.value("PSTR") != nil
    }

    /// Key families. Apple Silicon: Tp* performance cores, Te* efficiency cores, Tg* GPU.
    /// Intel: TC*/TG*. Shared: TH* SSD, TB*T battery, TW* wireless.
    private static func group(for key: String) -> TempGroup? {
        let p2 = String(key.prefix(2))
        switch p2 {
        case "Tp": return .cpuPerformance
        case "Te": return .cpuEfficiency
        case "Tg": return .gpu
        case "TH": return .ssd
        case "TW": return .wireless
        default: break
        }
        if key.hasPrefix("TB") && key.hasSuffix("T") { return .battery }
        if !SystemInfo.isAppleSilicon {
            if ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C"].contains(key) { return .cpuPerformance }
            if ["TG0P", "TG0D", "TG0H"].contains(key) { return .gpu }
        }
        return nil
    }

    private var cached: SensorsSample?
    private var reads = 0

    /// Temperatures and fans move slowly, so the SMC is read every other call.
    func read(power: PowerReport.Reading) -> SensorsSample {
        reads &+= 1
        var sample = (reads % 2 == 0 ? cached : nil) ?? readSMC()
        cached = sample
        sample.cpuPower = power.cpuWatts
        sample.gpuPower = power.gpuWatts
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: sample.thermal = .nominal
        case .fair: sample.thermal = .fair
        case .serious: sample.thermal = .serious
        case .critical: sample.thermal = .critical
        @unknown default: sample.thermal = .nominal
        }
        return sample
    }

    private func readSMC() -> SensorsSample {
        var sample = SensorsSample()
        if let smc {
            for group in TempGroup.allCases {
                guard let keys = groups[group], !keys.isEmpty else { continue }
                let values = keys.compactMap { smc.value($0) }.filter { $0 > 5 && $0 < 130 }
                guard !values.isEmpty else { continue }
                let value = group == .ssd ? values.max()! : values.reduce(0, +) / Double(values.count)
                sample.temps.append(TempReading(group: group, value: value))
            }
            for i in 0..<fanCount {
                let rpm = smc.value("F\(i)Ac") ?? 0
                sample.fans.append(Fan(id: i, rpm: max(0, rpm), min: smc.value("F\(i)Mn") ?? 0, max: smc.value("F\(i)Mx") ?? 0))
            }
            if hasSystemPower, let w = smc.value("PSTR"), w > 0 { sample.systemPower = w }
        }
        sample.hasFans = fanCount > 0

        if sample.temps.isEmpty { sample.temps = hid.read() }
        return sample
    }
}

/// Apple Silicon temperature sensors through the HID event system.
final class HIDTemperatures {
    private let client: IOHIDEventSystemClient?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            let matching = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary
            _ = IOHIDEventSystemClientSetMatching(client, matching)
        }
    }

    func read() -> [TempReading] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        var buckets: [TempGroup: [Double]] = [:]
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, 15, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, 15 << 16)
            guard value > 5, value < 130 else { continue }
            let group: TempGroup?
            if name.hasPrefix("PMU tdie") || name.contains("pACC") { group = .cpuPerformance }
            else if name.contains("eACC") { group = .cpuEfficiency }
            else if name.contains("GPU") { group = .gpu }
            else if name.contains("NAND") { group = .ssd }
            else if name.contains("gas gauge") { group = .battery }
            else { group = nil }
            if let group { buckets[group, default: []].append(value) }
        }
        return TempGroup.allCases.compactMap { g in
            guard let values = buckets[g], !values.isEmpty else { return nil }
            return TempReading(group: g, value: values.reduce(0, +) / Double(values.count))
        }
    }
}
