import Foundation
import IOKit

/// Minimal reader for the System Management Controller (temperatures, fans, system power).
/// Works without root on both Intel and Apple Silicon.
final class SMC {
    private struct KeyData {
        struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, attributes: UInt8 = 0 }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector: UInt8 { case read = 5, readIndex = 8, keyInfo = 9 }

    struct Info { let size: UInt32; let type: UInt32 }

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: Info] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    static func string(_ v: UInt32) -> String {
        let bytes = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.stride, &output, &size)
        guard r == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    func info(_ key: UInt32) -> Info? {
        if let cached = infoCache[key] { return cached }
        var input = KeyData()
        input.key = key
        input.data8 = Selector.keyInfo.rawValue
        guard let out = call(&input) else { return nil }
        let info = Info(size: out.keyInfo.dataSize, type: out.keyInfo.dataType)
        infoCache[key] = info
        return info
    }

    func bytes(_ key: UInt32) -> (Info, [UInt8])? {
        guard let info = info(key) else { return nil }
        var input = KeyData()
        input.key = key
        input.keyInfo.dataSize = info.size
        input.data8 = Selector.read.rawValue
        guard let out = call(&input) else { return nil }
        let raw = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(min(info.size, 32)))) }
        return (info, raw)
    }

    func value(_ key: String) -> Double? { value(Self.code(key)) }

    func value(_ key: UInt32) -> Double? {
        guard let (info, b) = bytes(key), !b.isEmpty else { return nil }
        switch Self.string(info.type) {
        case "flt ":
            guard b.count >= 4 else { return nil }
            return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 ", "si8 ":
            return Double(b[0])
        case "ui16":
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            guard b.count >= 4 else { return nil }
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "sp78":
            guard b.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fpe2":
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 6 | UInt16(b[1]) >> 2)
        default:
            return nil
        }
    }

    /// Every key the SMC exposes. Used once at start-up to discover the sensors on this model.
    func allKeys() -> [UInt32] {
        guard let count = value("#KEY").map({ UInt32($0) }), count > 0 else { return [] }
        var keys: [UInt32] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<count {
            var input = KeyData()
            input.data8 = Selector.readIndex.rawValue
            input.data32 = index
            if let out = call(&input) { keys.append(out.key) }
        }
        return keys
    }
}
