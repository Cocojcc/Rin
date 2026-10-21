import AppKit
import IOKit
import SystemConfiguration

/// What the About page shows: model, chip, display, system versions and volumes.
struct MacInfo {
    struct Volume: Identifiable {
        var id: String { path }
        var name: String
        var path: String
        var available: Int64
        var total: Int64
    }

    /// "MacBook Pro"
    var modelName: String
    /// From the marketing name "MacBook Pro (14-inch, M5)": 14 and, where it says, the year.
    var inches: String?
    var year: String?
    var modelID: String
    var chip: String
    var performanceCores: Int
    var efficiencyCores: Int
    var gpuCores: Int?
    var memory: UInt64
    var displayInches: Double?
    var displayPixels: (Int, Int)?
    var osVersion: String
    var build: String
    var kernel: String
    var computerName: String
    var bootTime: Date
    var appleSilicon: Bool
    var volumes: [Volume]

    static func read() -> MacInfo {
        let product = productName()
        let model = product.map { $0.components(separatedBy: " (").first ?? $0 } ?? SystemInfo.sysctlString("hw.model") ?? "Mac"
        var inches: String?
        var year: String?
        if let product, let open = product.firstIndex(of: "("), let close = product.lastIndex(of: ")"), open < close {
            for part in product[product.index(after: open)..<close].components(separatedBy: ",") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.hasSuffix("-inch") { inches = String(p.dropLast(5)) }
                else if p.count == 4, Int(p) != nil { year = p }
                else if p.count > 4, let y = p.split(separator: " ").last, y.count == 4, Int(y) != nil { year = String(y) }
            }
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        let display = builtInDisplay()
        return MacInfo(
            modelName: model,
            inches: inches,
            year: year,
            modelID: SystemInfo.sysctlString("hw.model") ?? "",
            chip: SystemInfo.sysctlString("machdep.cpu.brand_string") ?? SystemInfo.chipName,
            performanceCores: SystemInfo.sysctlInt("hw.perflevel0.physicalcpu") ?? SystemInfo.coreCount,
            efficiencyCores: SystemInfo.sysctlInt("hw.perflevel1.physicalcpu") ?? 0,
            gpuCores: gpuCoreCount(),
            memory: SystemInfo.physicalMemory,
            displayInches: display.inches,
            displayPixels: display.pixels,
            osVersion: os,
            build: SystemInfo.sysctlString("kern.osversion") ?? "",
            kernel: [SystemInfo.sysctlString("kern.ostype"), SystemInfo.sysctlString("kern.osrelease")].compactMap { $0 }.joined(separator: " "),
            computerName: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "",
            bootTime: SystemInfo.bootTime,
            appleSilicon: SystemInfo.isAppleSilicon,
            volumes: volumes())
    }

    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private static func gpuCoreCount() -> Int? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return (IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.intValue
    }

    /// The built-in panel (or the main display): diagonal in inches and native pixels.
    private static func builtInDisplay() -> (inches: Double?, pixels: (Int, Int)?) {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        guard let id = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? ids.first else { return (nil, nil) }
        let mm = CGDisplayScreenSize(id)
        let inches: Double? = mm.width > 0 ? Double((mm.width * mm.width + mm.height * mm.height).squareRoot() / 25.4) : nil
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        // The panel's own resolution; scaled "more space" modes can report larger backing sizes.
        let native = modes.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
        let best = (native.isEmpty ? modes : native).max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        return (inches, best.map { ($0.pixelWidth, $0.pixelHeight) })
    }

    private static func volumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable ?? true,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            return Volume(name: v.volumeName ?? url.lastPathComponent, path: url.path, available: available, total: Int64(total))
        }
    }

    /// The desktop picture, shrunk for the laptop drawing; nil when it can't be read.
    static func wallpaperThumbnail() -> NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 400,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
