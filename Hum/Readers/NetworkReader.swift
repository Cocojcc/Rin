import Darwin
import Foundation
import SystemConfiguration

final class NetworkReader {
    private var previous: (date: Date, interface: String, rx: UInt64, tx: UInt64)?
    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0
    private var today: (day: String, down: UInt64, up: UInt64)
    private var lastSave = Date.distantPast
    private var lastConnected: Date?
    private var kindCache: [String: InterfaceKind] = [:]
    private let store = SCDynamicStoreCreate(nil, "Hum" as CFString, nil, nil)

    private static let todayKey = "network.today"
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let day = Self.dayFormatter.string(from: Date())
        if let saved = UserDefaults.standard.dictionary(forKey: Self.todayKey),
           saved["day"] as? String == day {
            today = (day, (saved["down"] as? NSNumber)?.uint64Value ?? 0, (saved["up"] as? NSNumber)?.uint64Value ?? 0)
        } else {
            today = (day, 0, 0)
        }
    }

    /// `preferred` empty means "the interface macOS currently routes through".
    func read(preferred: String) -> NetworkSample {
        var sample = NetworkSample()
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let primary = global?["PrimaryInterface"] as? String
        let name = preferred.isEmpty ? primary : preferred
        sample.router = (name == primary ? global?["Router"] as? String : nil) ?? ""

        let counters = Self.counters()
        let now = Date()
        if let name, let c = counters[name] {
            sample.interface = name
            sample.kind = kind(of: name)
            sample.localIP = Self.ipv4(of: name) ?? ""
            sample.connected = !sample.localIP.isEmpty && primary != nil
            if let p = previous, p.interface == name {
                let dt = now.timeIntervalSince(p.date)
                let dRx = c.rx >= p.rx ? c.rx - p.rx : 0
                let dTx = c.tx >= p.tx ? c.tx - p.tx : 0
                if dt > 0 {
                    sample.down = Double(dRx) / dt
                    sample.up = Double(dTx) / dt
                }
                sessionDown += dRx
                sessionUp += dTx
                accumulateToday(dRx, dTx, now: now)
            }
            previous = (now, name, c.rx, c.tx)
        } else {
            previous = nil
        }

        if sample.connected { lastConnected = now }
        sample.lastConnected = lastConnected
        sample.sessionDown = sessionDown
        sample.sessionUp = sessionUp
        sample.todayDown = today.down
        sample.todayUp = today.up
        return sample
    }

    /// Interfaces that can carry traffic, for the interface picker.
    func availableInterfaces() -> [(name: String, kind: InterfaceKind)] {
        Self.counters().keys
            .filter { $0.hasPrefix("en") || $0.hasPrefix("utun") || $0.hasPrefix("bridge") }
            .sorted()
            .map { ($0, kind(of: $0)) }
    }

    private func accumulateToday(_ down: UInt64, _ up: UInt64, now: Date) {
        let day = Self.dayFormatter.string(from: now)
        if day != today.day { today = (day, 0, 0) }
        today.down += down
        today.up += up
        if now.timeIntervalSince(lastSave) > 30 {
            lastSave = now
            UserDefaults.standard.set(["day": today.day, "down": NSNumber(value: today.down), "up": NSNumber(value: today.up)], forKey: Self.todayKey)
        }
    }

    private func kind(of bsdName: String) -> InterfaceKind {
        if let cached = kindCache[bsdName] { return cached }
        var result: InterfaceKind = .other
        if ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains(where: { bsdName.hasPrefix($0) }) {
            kindCache[bsdName] = .vpn
            return .vpn
        }
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in all where SCNetworkInterfaceGetBSDName(iface) as String? == bsdName {
                let type = SCNetworkInterfaceGetInterfaceType(iface)
                if type == kSCNetworkInterfaceTypeIEEE80211 { result = .wifi }
                else if type == kSCNetworkInterfaceTypeEthernet { result = .ethernet }
            }
        }
        kindCache[bsdName] = result
        return result
    }

    /// 64-bit byte counters per interface (getifaddrs only exposes 32-bit ones).
    private static func counters() -> [String: (rx: UInt64, tx: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(msg.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        result[name] = (msg.ifm_data.ifi_ibytes, msg.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func ipv4(of name: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == name else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
