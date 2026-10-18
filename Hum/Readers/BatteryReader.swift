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
