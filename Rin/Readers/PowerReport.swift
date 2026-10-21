import Foundation
import IOKit

/// Energy and GPU frequency residency from IOReport, the interface `powermetrics` uses.
/// Needs no root. Each `read()` returns averages over the time since the previous call.
final class PowerReport {
    struct Reading {
        var cpuWatts: Double?
        var gpuWatts: Double?
        var gpuMHz: Double?
        var decodeWatts: Double?
        var encodeWatts: Double?
        /// Average active frequency (MHz): all cores, performance cluster, efficiency cluster.
        var cpuMHz: Double?
        var performanceMHz: Double?
        var efficiencyMHz: Double?
    }

    private var subscription: IOReportSubscription?
    private var channels: CFMutableDictionary?
    private var previous: (date: Date, sample: CFDictionary)?
    private let gpuFrequencies: [Double] = PowerReport.readFrequencies("voltage-states9")
    private let efficiencyFrequencies: [Double] = PowerReport.readFrequencies("voltage-states1-sram")
    private let performanceFrequencies: [Double] = PowerReport.readFrequencies("voltage-states5-sram")

    init() {
        guard SystemInfo.isAppleSilicon else { return }
        guard let energy = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0) else { return }
        let merged = NSMutableDictionary(dictionary: energy as NSDictionary) as CFMutableDictionary
        if let gpu = IOReportCopyChannelsInGroup("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0) {
            IOReportMergeChannels(merged, gpu, nil)
        }
        if let cpu = IOReportCopyChannelsInGroup("CPU Stats" as CFString, "CPU Core Performance States" as CFString, 0, 0, 0) {
            IOReportMergeChannels(merged, cpu, nil)
        }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let sub = IOReportCreateSubscription(nil, merged, &subscribed, 0, nil), let subscribed else { return }
        subscription = sub
        channels = subscribed.takeRetainedValue()
    }

    var maxGPUMHz: Double? { gpuFrequencies.max() }

    func read() -> Reading {
        guard let subscription, let channels,
              let current = IOReportCreateSamples(subscription, channels, nil) else { return Reading() }
        let now = Date()
        defer { previous = (now, current) }
        guard let previous, let delta = IOReportCreateSamplesDelta(previous.sample, current, nil) else { return Reading() }
        let dt = now.timeIntervalSince(previous.date)
        guard dt > 0, let items = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { return Reading() }

        var cpuJoules = 0.0, gpuJoules = 0.0, aveJoules = 0.0, vdecJoules = 0.0
        var sawCPU = false, sawGPU = false, sawMedia = false
        var residency: [Double] = []
        // (weighted MHz, active time) per cluster.
        var eCluster = (0.0, 0.0), pCluster = (0.0, 0.0)

        for channel in items {
            let group = IOReportChannelGetGroup(channel) as String? ?? ""
            let name = IOReportChannelGetChannelName(channel) as String? ?? ""
            if group == "Energy Model" {
                let unit = IOReportChannelGetUnitLabel(channel) as String? ?? ""
                let joules = Double(IOReportSimpleGetIntegerValue(channel, 0)) * Self.scale(unit)
                if name == "CPU Energy" { cpuJoules += joules; sawCPU = true }
                else if name == "GPU Energy" || name == "GPU" { gpuJoules += joules; sawGPU = true }
                else if name == "AVE" { aveJoules += joules; sawMedia = true }
                else if name == "VDEC" { vdecJoules += joules; sawMedia = true }
            } else if group == "GPU Stats", name == "GPUPH" {
                let count = IOReportStateGetCount(channel)
                residency = (0..<count).map { Double(IOReportStateGetResidency(channel, $0)) }
            } else if group == "CPU Stats" {
                let efficiency = name.hasPrefix("E")
                let table = efficiency ? efficiencyFrequencies : performanceFrequencies
                let (mhz, time) = Self.activeFrequency(channel, table)
                if efficiency { eCluster.0 += mhz * time; eCluster.1 += time } else { pCluster.0 += mhz * time; pCluster.1 += time }
            }
        }

        var reading = Reading()
        if sawCPU, cpuJoules > 0 { reading.cpuWatts = cpuJoules / dt }
        if sawGPU { reading.gpuWatts = gpuJoules / dt }
        if sawMedia {
            reading.decodeWatts = vdecJoules / dt
            reading.encodeWatts = aveJoules / dt
        }
        if eCluster.1 > 0 { reading.efficiencyMHz = eCluster.0 / eCluster.1 }
        if pCluster.1 > 0 { reading.performanceMHz = pCluster.0 / pCluster.1 }
        let busy = eCluster.1 + pCluster.1
        if busy > 0 { reading.cpuMHz = (eCluster.0 + pCluster.0) / busy }
        // State 0 is OFF; the active states map in order onto the non-zero DVFS frequencies.
        let active = Array(residency.dropFirst())
        let n = min(active.count, gpuFrequencies.count)
        if n > 0 {
            var weighted = 0.0, total = 0.0
            for i in 0..<n {
                weighted += active[i] * gpuFrequencies[i]
                total += active[i]
            }
            reading.gpuMHz = total > 0 ? weighted / total : 0
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

    /// A core's residency-weighted frequency over its active (non-idle) states, and that active time.
    /// Active states map in order onto the cluster's DVFS table.
    private static func activeFrequency(_ channel: CFDictionary, _ table: [Double]) -> (Double, Double) {
        guard !table.isEmpty else { return (0, 0) }
        var active: [Double] = []
        for i in 0..<IOReportStateGetCount(channel) {
            let name = (IOReportStateGetNameForIndex(channel, i) as String? ?? "").uppercased()
            if name.hasPrefix("IDLE") || name.hasPrefix("DOWN") || name.hasPrefix("OFF") { continue }
            active.append(Double(IOReportStateGetResidency(channel, i)))
        }
        // Extra leading states (when the table is shorter) are the lowest ones; align from the top.
        let offset = max(0, active.count - table.count)
        var weighted = 0.0, total = 0.0
        for (i, r) in active.enumerated() where i >= offset {
            weighted += r * table[min(i - offset, table.count - 1)]
            total += r
        }
        return total > 0 ? (weighted / total, total) : (0, 0)
    }

    /// A DVFS table from the power manager node: little-endian (frequency, voltage) pairs.
    /// Newer chips store kHz in the CPU tables, the GPU table holds Hz; both come back as MHz.
    private static func readFrequencies(_ key: String) -> [Double] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            guard String(cString: name) == "pmgr",
                  let data = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { continue }
            var result: [Double] = []
            var offset = 0
            while offset + 8 <= data.count {
                let raw = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                let value = Double(UInt32(littleEndian: raw))
                if value > 0 { result.append(value >= 10_000_000 ? value / 1_000_000 : value / 1000) }
                offset += 8
            }
            return result
        }
        return []
    }
}
