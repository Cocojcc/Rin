import Foundation
import IOKit

/// Energy and GPU frequency residency from IOReport, the interface `powermetrics` uses.
/// Needs no root. Each `read()` returns averages over the time since the previous call.
final class PowerReport {
    struct Reading {
        var cpuWatts: Double?
        var gpuWatts: Double?
        var gpuMHz: Double?
    }

    private var subscription: IOReportSubscription?
    private var channels: CFMutableDictionary?
    private var previous: (date: Date, sample: CFDictionary)?
    private let gpuFrequencies: [Double] = PowerReport.readGPUFrequencies()

    init() {
        guard SystemInfo.isAppleSilicon else { return }
        guard let energy = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0) else { return }
        let merged = NSMutableDictionary(dictionary: energy as NSDictionary) as CFMutableDictionary
        if let gpu = IOReportCopyChannelsInGroup("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0) {
            IOReportMergeChannels(merged, gpu, nil)
        }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let sub = IOReportCreateSubscription(nil, merged, &subscribed, 0, nil), let subscribed else { return }
        subscription = sub
        channels = subscribed.takeRetainedValue()
    }

    var maxGPUMHz: Double? { gpuFrequencies.max().map { $0 / 1_000_000 } }

    func read() -> Reading {
        guard let subscription, let channels,
              let current = IOReportCreateSamples(subscription, channels, nil) else { return Reading() }
        let now = Date()
        defer { previous = (now, current) }
        guard let previous, let delta = IOReportCreateSamplesDelta(previous.sample, current, nil) else { return Reading() }
        let dt = now.timeIntervalSince(previous.date)
        guard dt > 0, let items = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { return Reading() }

        var cpuJoules = 0.0, gpuJoules = 0.0
        var sawCPU = false, sawGPU = false
        var residency: [Double] = []

        for channel in items {
            let group = IOReportChannelGetGroup(channel) as String? ?? ""
            let name = IOReportChannelGetChannelName(channel) as String? ?? ""
            if group == "Energy Model" {
                let unit = IOReportChannelGetUnitLabel(channel) as String? ?? ""
                let joules = Double(IOReportSimpleGetIntegerValue(channel, 0)) * Self.scale(unit)
                if name == "CPU Energy" { cpuJoules += joules; sawCPU = true }
                else if name == "GPU Energy" || name == "GPU" { gpuJoules += joules; sawGPU = true }
            } else if group == "GPU Stats", name == "GPUPH" {
                let count = IOReportStateGetCount(channel)
                residency = (0..<count).map { Double(IOReportStateGetResidency(channel, $0)) }
            }
        }

        var reading = Reading()
        if sawCPU, cpuJoules > 0 { reading.cpuWatts = cpuJoules / dt }
        if sawGPU { reading.gpuWatts = gpuJoules / dt }
        // State 0 is OFF; the active states map in order onto the non-zero DVFS frequencies.
        let active = Array(residency.dropFirst())
        let n = min(active.count, gpuFrequencies.count)
        if n > 0 {
            var weighted = 0.0, total = 0.0
            for i in 0..<n {
                weighted += active[i] * gpuFrequencies[i]
                total += active[i]
            }
            reading.gpuMHz = total > 0 ? weighted / total / 1_000_000 : 0
        }
        return reading
    }

    private static func scale(_ unit: String) -> Double {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": return 1e-3
        case "uJ", "µJ": return 1e-6
        case "nJ": return 1e-9
        default: return 1e-3
        }
    }

    /// GPU DVFS table from the power manager node: little-endian (Hz, mV) pairs; zero entries are dropped.
    private static func readGPUFrequencies() -> [Double] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            guard String(cString: name) == "pmgr",
                  let data = IORegistryEntryCreateCFProperty(entry, "voltage-states9" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { continue }
            var result: [Double] = []
            var offset = 0
            while offset + 8 <= data.count {
                let hz = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                let value = Double(UInt32(littleEndian: hz))
                if value > 0 { result.append(value) }
                offset += 8
            }
            return result
        }
        return []
    }
}
