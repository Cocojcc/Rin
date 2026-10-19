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

    private let latency = LatencyProbe()

    /// `preferred` empty means "the interface macOS currently routes through".
    func read(preferred: String, probeLatency: Bool = false) -> NetworkSample {
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
        if probeLatency {
            latency.tick(connected: sample.connected)
            (sample.latencyMS, sample.checks) = latency.results()
        }
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
                    let end = offset + Int(header.ifm_msglen)
                    if let name = linkName(raw, at: offset + MemoryLayout<if_msghdr2>.size, end: end, addrs: msg.ifm_addrs)
                        ?? interfaceName(msg.ifm_index) {
                        result[name] = (msg.ifm_data.ifi_ibytes, msg.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    /// The interface name from the link-level address that follows an RTM_IFINFO2 header.
    /// `if_indextoname` would list every interface again for each one, and there are dozens
    /// (utun, awdl, bridges).
    private static func linkName(_ raw: UnsafeRawBufferPointer, at start: Int, end: Int, addrs: Int32) -> String? {
        guard addrs & RTA_IFP != 0, start + MemoryLayout<sockaddr_dl>.size <= min(end, raw.count) else { return nil }
        let dl = raw.loadUnaligned(fromByteOffset: start, as: sockaddr_dl.self)
        guard Int32(dl.sdl_family) == AF_LINK, dl.sdl_nlen > 0, let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) else { return nil }
        let nameStart = start + dataOffset
        let nameEnd = nameStart + Int(dl.sdl_nlen)
        guard nameEnd <= min(end, raw.count) else { return nil }
        return String(decoding: raw[nameStart..<nameEnd], as: UTF8.self)
    }

    private static func interfaceName(_ index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return String(cString: buffer)
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


/// Round-trip time to a public resolver over ICMP (an unprivileged datagram socket), every
/// 30 seconds on its own queue. Keeps the last 48 checks for the connection log.
final class LatencyProbe {
    private let queue = DispatchQueue(label: "hum.latency", qos: .utility)
    private let lock = NSLock()
    private var lastStart = Date.distantPast
    private var latest: Double?
    private var checks: [ConnectionCheck] = []
    private static let target = "1.1.1.1"
    private static let slowMS = 100.0

    func tick(connected: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastStart) >= 30 else { return }
        lastStart = now
        guard connected else { record(nil); return }
        queue.async { [weak self] in self?.record(Self.ping(Self.target)) }
    }

    func results() -> (Double?, [ConnectionCheck]) {
        lock.lock(); defer { lock.unlock() }
        return (latest, checks)
    }

    private func record(_ ms: Double?) {
        lock.lock(); defer { lock.unlock() }
        latest = ms
        checks.append(ms.map { $0 < Self.slowMS ? .ok : .slow } ?? .failed)
        if checks.count > 48 { checks.removeFirst(checks.count - 48) }
    }

    /// One echo request; nil on timeout (1 s) or error.
    private static func ping(_ host: String) -> Double? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 1...UInt16.max)
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 8   // echo request
        packet[4] = UInt8(identifier >> 8); packet[5] = UInt8(identifier & 0xFF)
        packet[7] = 1   // sequence
        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count, by: 2) { sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1]) }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8); packet[3] = UInt8(checksum & 0xFF)

        let start = DispatchTime.now()
        let sent = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { return nil }
            // Replies may arrive with the IP header in front.
            let offset = buffer[0] >> 4 == 4 ? Int(buffer[0] & 0x0F) * 4 : 0
            guard n >= offset + 8 else { continue }
            if buffer[offset] == 0 { // echo reply
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                return elapsed
            }
            if Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) > 1_000_000_000 { return nil }
        }
    }
}
