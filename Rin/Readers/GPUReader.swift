import Foundation
import IOKit
import Metal

final class GPUReader {
    private let memoryLimit: UInt64 = {
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }
        return device.recommendedMaxWorkingSetSize
    }()
    private var cores = 0
    private var model = ""

    func read(power: PowerReport.Reading, temperature: Double?) -> GPUSample {
        var sample = GPUSample()
        sample.memoryLimit = memoryLimit
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess {
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                      let d = props?.takeRetainedValue() as? [String: Any],
                      let stats = d["PerformanceStatistics"] as? [String: Any] else { continue }
                let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
                sample.utilization = max(sample.utilization, min(100, util) / 100)
                sample.memoryUsed = max(sample.memoryUsed, (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0)
                if let c = d["gpu-core-count"] as? Int { cores = c }
                if let m = d["model"] as? String { model = m.replacingOccurrences(of: "Apple ", with: "") }
            }
        }
        sample.cores = cores
        sample.model = model.isEmpty ? SystemInfo.chipName : model
        sample.power = power.gpuWatts
        sample.decodeWatts = power.decodeWatts
        sample.temperature = temperature
        sample.frequencyMHz = power.gpuMHz
        return sample
    }
}
