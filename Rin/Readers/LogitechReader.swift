import Foundation
import IOKit.hid

/// Accessories paired with a Logitech receiver (Unifying, LIGHTSPEED, Bolt), read over HID++
/// through the receiver's vendor interface (usage page 0xFF00, which needs no Input Monitoring).
///
/// It runs on every refresh of the Accessories module, so it does as little as it can:
/// - The interface is opened for the read and closed after it; between reads Rin hears nothing
///   on it, G HUB's traffic included.
/// - Which slots hold a device comes from the receiver's pairing registers. The receiver answers
///   those itself without waking a device, and they are read again only every ten minutes.
/// - A device's name, kind and battery feature are looked up the first time it answers. After
///   that a read sends one battery request per paired device.
/// - A paired device that doesn't answer (asleep, off, out of range) comes back as not connected.
final class LogitechReader {
    private struct Slot {
        var index: UInt8
        /// The device's serial (its HID++ unit ID); nil when the receiver keeps no pairing registers.
        var serial: String?
        var name: String?
        var kind: BluetoothDevice.Kind?
    }

    private enum Battery {
        case unified(UInt8), status(UInt8), voltage(UInt8)
    }

    private struct Known {
        var id: String
        var name: String
        var kind: BluetoothDevice.Kind
        var battery: Battery?
    }

    private struct SlotKey: Hashable {
        var receiver: UInt64
        var slot: UInt8
    }

    private var slots: [UInt64: (read: Date, slots: [Slot])] = [:]
    private var known: [SlotKey: Known] = [:]
    private static let pairingTTL: TimeInterval = 600

    func read(now: Date = Date()) -> (connected: [BluetoothDevice], asleep: [BluetoothDevice]) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D, kIOHIDPrimaryUsagePageKey: 0xFF00] as CFDictionary)
        let interfaces = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var connected: [BluetoothDevice] = [], asleep: [BluetoothDevice] = []
        var present = Set<UInt64>()

        for hid in interfaces {
            var receiver: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(hid), &receiver)
            present.insert(receiver)
            guard let link = HIDPPLink(hid) else { continue }
            defer { link.close() }

            if slots[receiver].map({ now.timeIntervalSince($0.read) >= Self.pairingTTL }) ?? true {
                slots[receiver] = (now, Self.pairedSlots(link))
            }
            for slot in slots[receiver]?.slots ?? [] {
                let key = SlotKey(receiver: receiver, slot: slot.index)
                // Paired again with another device since it was looked up.
                if let serial = slot.serial, known[key].map({ $0.id != Self.id(serial) }) == true { known[key] = nil }
                if let device = reading(slot, key: key, link) {
                    connected.append(device)
                } else if let serial = slot.serial {
                    let k = known[key]
                    asleep.append(BluetoothDevice(id: Self.id(serial), name: k?.name ?? slot.name ?? "", kind: k?.kind ?? slot.kind ?? .other,
                                                  level: nil, connected: false, connection: .receiver))
                }
            }
        }
        slots = slots.filter { present.contains($0.key) }
        known = known.filter { present.contains($0.key.receiver) }
        return (connected, asleep)
    }

    /// The device in a slot, or nil when it doesn't answer.
    private func reading(_ slot: Slot, key: SlotKey, _ link: HIDPPLink) -> BluetoothDevice? {
        if known[key] == nil {
            guard let found = Self.discover(slot, link) else { return nil }
            known[key] = found
        }
        guard let k = known[key] else { return nil }
        var device = BluetoothDevice(id: k.id, name: k.name, kind: k.kind, level: nil, connection: .receiver)
        switch k.battery {
        case .unified(let f):
            // State of charge, level flags, charging status, external power.
            guard let r = link.call(slot.index, f, 1) else { return nil }
            device.level = r[0] > 0 ? Double(r[0]) / 100 : Self.approximate(r[1])
            device.charging = r[2] == 1 || r[2] == 2
        case .status(let f):
            // Level, next level, status.
            guard let r = link.call(slot.index, f, 0) else { return nil }
            device.level = r[0] > 0 ? Double(min(r[0], 100)) / 100 : nil
            device.charging = [1, 2, 4].contains(r[2])
        case .voltage(let f):
            // Millivolts, flags (bit 7: charging).
            guard let r = link.call(slot.index, f, 0) else { return nil }
            device.level = Self.level(millivolts: Int(r[0]) << 8 | Int(r[1]))
            device.charging = r[2] & 0x80 != 0
        case nil:
            // No battery feature: it still has to answer to count as connected.
            guard link.call(slot.index, 0, 1) != nil else { return nil }
        }
        return device
    }

    // MARK: Discovery

    /// The receiver's paired slots from its pairing registers, or slots 1–6 to try when it has none.
    private static func pairedSlots(_ link: HIDPPLink) -> [Slot] {
        var found: [Slot] = []
        for n in UInt8(0)..<6 {
            // 0x30+n: serial; 0x20+n: kind in the low nibble of byte 7; 0x40+n: length, then the name.
            guard let info = link.register(0xB5, 0x30 + n), info.count >= 5 else { continue }
            var slot = Slot(index: n + 1, serial: info[1...4].map { String(format: "%02x", $0) }.joined())
            if let pairing = link.register(0xB5, 0x20 + n), pairing.count > 7 {
                slot.kind = pairingKinds[pairing[7] & 0x0F] ?? .other
            }
            if let name = link.register(0xB5, 0x40 + n), name.count > 2 {
                slot.name = String(decoding: name.dropFirst(2).prefix(Int(name[1])), as: UTF8.self)
            }
            found.append(slot)
        }
        return found.isEmpty ? (1...6).map { Slot(index: UInt8($0)) } : found
    }

    private static func discover(_ slot: Slot, _ link: HIDPPLink) -> Known? {
        let i = slot.index
        // The root feature (index 0), function 0: a feature's index, 0 when the device lacks it,
        // nil when the device doesn't answer.
        func feature(_ id: UInt16) -> UInt8? { link.call(i, 0, 0, [UInt8(id >> 8), UInt8(id & 0xFF)])?[0] }
        // The first request doubles as the ping: no answer, no device.
        guard let unified = feature(0x1004) else { return nil }
        var battery: Battery? = unified != 0 ? .unified(unified) : nil
        if battery == nil, let f = feature(0x1000), f != 0 { battery = .status(f) }
        if battery == nil, let f = feature(0x1001), f != 0 { battery = .voltage(f) }

        var name = slot.name, kind = slot.kind
        if let f = feature(0x0005), f != 0, let count = link.call(i, f, 0) {
            var bytes: [UInt8] = []
            while bytes.count < Int(count[0]), let part = link.call(i, f, 1, [UInt8(bytes.count)]) {
                bytes += part.prefix(Int(count[0]) - bytes.count)
            }
            if !bytes.isEmpty { name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
            if let type = link.call(i, f, 2)?.first {
                kind = deviceTypes[type] ?? .other
            }
        }
        var serial = slot.serial
        if serial == nil, let f = feature(0x0003), f != 0, let info = link.call(i, f, 0) {
            serial = info[1...4].map { String(format: "%02x", $0) }.joined()
        }
        let title = name ?? ""
        return Known(id: id(serial ?? "slot\(i)"), name: title, kind: kind ?? BluetoothReader.kind(name: title, minorType: nil), battery: battery)
    }

    private static func id(_ serial: String) -> String { "logi-" + serial }

    /// The receiver's pairing kinds: keyboard, mouse, numpad, trackball, touchpad.
    private static let pairingKinds: [UInt8: BluetoothDevice.Kind] = [1: .keyboard, 2: .mouse, 3: .keyboard, 8: .mouse, 9: .trackpad]
    /// Device Name & Type's types: keyboard, numpad, mouse, trackpad, trackball, headset, joystick, gamepad.
    private static let deviceTypes: [UInt8: BluetoothDevice.Kind] = [0: .keyboard, 2: .keyboard, 3: .mouse, 4: .trackpad, 5: .mouse,
                                                                     8: .headphones, 11: .gamepad, 12: .gamepad]

    /// Unified Battery's level flags when the device doesn't report a percentage.
    private static func approximate(_ flags: UInt8) -> Double? {
        if flags & 8 != 0 { return 0.9 }
        if flags & 4 != 0 { return 0.5 }
        if flags & 2 != 0 { return 0.2 }
        if flags & 1 != 0 { return 0.05 }
        return nil
    }

    /// A lithium cell's charge from its voltage.
    private static func level(millivolts mv: Int) -> Double {
        let curve: [(Int, Double)] = [(4186, 1), (4067, 0.9), (3989, 0.8), (3922, 0.7), (3859, 0.6), (3811, 0.5),
                                      (3778, 0.4), (3751, 0.3), (3717, 0.2), (3671, 0.1), (3646, 0.05), (3579, 0.02), (3500, 0)]
        guard mv < curve[0].0 else { return 1 }
        for (high, low) in zip(curve, curve.dropFirst()) where mv >= low.0 {
            return low.1 + (high.1 - low.1) * Double(mv - low.0) / Double(high.0 - low.0)
        }
        return 0
    }
}

/// The receiver's HID++ interface, open for one read. Replies come back as input reports, so a
/// request runs this thread's run loop in a private mode until its reply (or 0.4 s) arrives.
private final class HIDPPLink {
    private let device: IOHIDDevice
    private let runLoop: CFRunLoop = CFRunLoopGetCurrent()
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var match: (([UInt8]) -> Bool)?
    private var reply: [UInt8]?
    private static let mode = CFRunLoopMode("com.zoro.rin.hidpp" as CFString)
    /// Tags Rin's requests, so replies to G HUB's on the same interface are told apart.
    private static let softwareID: UInt8 = 0x0D

    init?(_ device: IOHIDDevice) {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            buffer.deallocate()
            return nil
        }
        self.device = device
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
            let link = Unmanaged<HIDPPLink>.fromOpaque(context!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if link.match?(bytes) == true { link.reply = bytes; link.match = nil }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, Self.mode.rawValue)
    }

    func close() {
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, Self.mode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }

    /// HID++ 2.0: a function of the feature at `feature` on the device in `slot`; the reply's
    /// parameters, or nil on an error or no reply.
    func call(_ slot: UInt8, _ feature: UInt8, _ function: UInt8, _ params: [UInt8] = []) -> [UInt8]? {
        let tag = function << 4 | Self.softwareID
        var out = [UInt8](repeating: 0, count: 20)
        out[0] = 0x11; out[1] = slot; out[2] = feature; out[3] = tag
        out.replaceSubrange(4..<4 + params.count, with: params)
        var failed = false
        let r = send(out) { r in
            guard r.count >= 7, r[1] == slot else { return false }
            if r[2] == feature && r[3] == tag { return true }
            // An error: 0xFF from the device (HID++ 2.0), 0x8F from the receiver (HID++ 1.0).
            if (r[2] == 0xFF || r[2] == 0x8F) && r[3] == feature && r[4] == tag { failed = true; return true }
            return false
        }
        guard let r, !failed, r.count >= 20 else { return nil }
        return Array(r[4...])
    }

    /// HID++ 1.0: one of the receiver's long registers; the reply from the sub-address on.
    func register(_ address: UInt8, _ sub: UInt8) -> [UInt8]? {
        var failed = false
        let r = send([0x10, 0xFF, 0x83, address, sub, 0, 0]) { r in
            guard r.count >= 6, r[1] == 0xFF else { return false }
            if r[2] == 0x83 && r[3] == address && r[4] == sub { return true }
            if r[2] == 0x8F && r[3] == 0x83 && r[4] == address { failed = true; return true }
            return false
        }
        guard let r, !failed else { return nil }
        return Array(r[4...])
    }

    private func send(_ report: [UInt8], until matches: @escaping ([UInt8]) -> Bool) -> [UInt8]? {
        reply = nil
        match = matches
        defer { match = nil }
        guard IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count) == kIOReturnSuccess else { return nil }
        let deadline = CFAbsoluteTimeGetCurrent() + 0.4
        while reply == nil {
            let left = deadline - CFAbsoluteTimeGetCurrent()
            guard left > 0, CFRunLoopRunInMode(Self.mode, left, true) != .finished else { break }
        }
        return reply
    }
}
