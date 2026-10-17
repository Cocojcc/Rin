import Darwin
import Foundation

final class MemoryReader {
    private let pageSize = UInt64(vm_kernel_page_size)

    func read() -> MemorySample {
        var sample = MemorySample()
        sample.total = SystemInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Same breakdown as Activity Monitor.
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let external = UInt64(stats.external_page_count)
            sample.app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
            sample.wired = UInt64(stats.wire_count) * pageSize
            sample.compressed = UInt64(stats.compressor_page_count) * pageSize
            sample.cached = (external + purgeable) * pageSize
            sample.used = sample.app + sample.wired + sample.compressed
            let accounted = sample.used + sample.cached
            sample.free = sample.total > accounted ? sample.total - accounted : 0
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            sample.swapUsed = swap.xsu_used
        }

        var level: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            sample.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
        var available: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &available, &size, nil, 0) == 0 {
            sample.pressureLevel = max(0, min(1, Double(100 - available) / 100))
        }
        return sample
    }
}
