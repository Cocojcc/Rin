import AppKit
import Foundation
import IOKit

final class DiskReader {
    private var previous: (date: Date, read: UInt64, write: UInt64)?
    private var volumes: [Volume] = []
    private var lastVolumeScan = Date.distantPast
    private var health: DiskHealth?
    private var lastHealthRead = Date.distantPast

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
        .volumeIsBrowsableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
    ]

    func read(force: Bool = false) -> DiskSample {
        var sample = DiskSample()
        let now = Date()
        // Capacity changes slowly and "important usage" costs tens of ms to compute.
        if force || now.timeIntervalSince(lastVolumeScan) > 60 {
            volumes = Self.scanVolumes()
            lastVolumeScan = now
        }
        sample.volumes = volumes
        // S.M.A.R.T. counters move slowly; read them every few minutes.
        if force || now.timeIntervalSince(lastHealthRead) > 300 {
            health = Self.readHealth()
            lastHealthRead = now
        }
        sample.health = health

        let (read, write) = Self.ioCounters()
        sample.totalRead = read
        sample.totalWritten = write
        if let p = previous {
            let dt = now.timeIntervalSince(p.date)
            if dt > 0 {
                sample.read = Double(read >= p.read ? read - p.read : 0) / dt
                sample.write = Double(write >= p.write ? write - p.write : 0) / dt
            }
        }
        previous = (now, read, write)
        return sample
    }

    func invalidateVolumes() { lastVolumeScan = .distantPast }

    private static func scanVolumes() -> [Volume] {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }
        var result: [Volume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable ?? true, v.volumeIsLocal ?? true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let isRoot = v.volumeIsRootFileSystem ?? (url.path == "/")
            let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            let strict = Int64(v.volumeAvailableCapacity ?? 0)
            result.append(Volume(
                url: url,
                name: v.volumeLocalizedName ?? v.volumeName ?? url.lastPathComponent,
                total: Int64(total),
                available: available,
                isInternal: v.volumeIsInternal ?? isRoot,
                isEjectable: (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false) || !(v.volumeIsInternal ?? true),
                isRoot: isRoot,
                purgeable: max(0, available - strict)
            ))
        }
        return result.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func readHealth() -> DiskHealth? {
        var smart = HumNVMeSMART()
        guard HumReadNVMeSMART(&smart) == 1 else { return nil }
        return DiskHealth(ok: smart.criticalWarning == 0,
                          lifeRemaining: max(0, 1 - Double(smart.percentageUsed) / 100),
                          totalWritten: smart.bytesWritten,
                          temperature: smart.temperatureC > 0 ? smart.temperatureC : nil)
    }

    /// Cumulative bytes read / written across all block storage drivers since boot.
    private static func ioCounters() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == kIOReturnSuccess else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }
}
