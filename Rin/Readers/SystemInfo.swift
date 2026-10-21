import Foundation
import IOKit

/// Static facts about this Mac, read once.
enum SystemInfo {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size { return Int(Int32(truncatingIfNeeded: value)) }
        return Int(value)
    }

    /// "M5", "M4 Pro", or the Intel brand string without the trademark noise.
    static let chipName: String = {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Mac"
        return brand.replacingOccurrences(of: "Apple ", with: "")
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
    }()

    static let coreCount: Int = sysctlInt("hw.ncpu") ?? ProcessInfo.processInfo.processorCount
    static let performanceCores: Int = sysctlInt("hw.perflevel0.logicalcpu") ?? coreCount
    static let efficiencyCores: Int = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    static let physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()

    /// Core type for each logical CPU in host_processor_info order, read from the device tree.
    static let coreKinds: [CoreKind] = {
        var kinds = [CoreKind](repeating: .performance, count: coreCount)
        guard isAppleSilicon else { return kinds }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator) == kIOReturnSuccess else { return kinds }
        defer { IOObjectRelease(iterator) }
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let cluster = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  let id = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { continue }
            let index = id.intValue
            guard index >= 0, index < kinds.count else { continue }
            kinds[index] = cluster.first == UInt8(ascii: "E") ? .efficiency : .performance
            found = true
        }
        if !found {
            // Fallback: Apple Silicon lists efficiency cores first.
            for i in 0..<min(efficiencyCores, kinds.count) { kinds[i] = .efficiency }
        }
        return kinds
    }()

    static let bootTime: Date = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }()

    static let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
}
