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
    private var adapterCache: (date: Date, value: Adapter?)?
    /// The last way out found, with the network it was found on: a lookup that fails for a
    /// moment keeps it instead of reading as a change.
    private var lastEgress: (base: String, signature: String)?
    private let store = SCDynamicStoreCreate(nil, "Rin" as CFString, nil, nil)

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
        let ipv4Interfaces = Self.allIPv4Interfaces()
        let now = Date()
        if let name, let c = counters[name] {
            sample.interface = name
            sample.kind = kind(of: name)
            sample.localIP = ipv4Interfaces.first(where: { $0.name == name })?.address ?? ""
            sample.connected = !sample.localIP.isEmpty && primary != nil
            // A VPN's tunnel has a made-up address; the Mac's own is the adapter's under it.
            // The tunnel also only carries what it captures, while everything, tunnelled or
            // sent direct, leaves through the adapter: unless an interface was picked in
            // settings, the rates are read there.
            var counted = (name: name, rx: c.rx, tx: c.tx)
            if sample.kind == .vpn, let adapter = adapter() {
                sample.localIP = adapter.ip
                sample.router = adapter.router
                sample.adapterKind = kind(of: adapter.name)
                if preferred.isEmpty, let a = counters[adapter.name] { counted = (adapter.name, a.rx, a.tx) }
            }
            if let p = previous, p.interface == counted.name {
                let dt = now.timeIntervalSince(p.date)
                let dRx = counted.rx >= p.rx ? counted.rx - p.rx : 0
                let dTx = counted.tx >= p.tx ? counted.tx - p.tx : 0
                if dt > 0 {
                    sample.down = Double(dRx) / dt
                    sample.up = Double(dTx) / dt
                }
                sessionDown += dRx
                sessionUp += dTx
                accumulateToday(dRx, dTx, now: now)
            }
            previous = (now, counted.name, counted.rx, counted.tx)
        } else {
            previous = nil
        }

        if sample.connected {
            lastConnected = now
            let proxy = proxyState()
            let tunnels = Self.activeTunnels(from: ipv4Interfaces)
            let tunnelSig = Self.tunnelSignature(from: tunnels)
            let base = "\(sample.interface)|\(sample.localIP)|\(sample.router)"
            let found = Self.egressSignature(interfaces: ipv4Interfaces)
            let egress = Self.resolvedEgress(found: found, base: base, last: lastEgress)
            if !found.isEmpty { lastEgress = (base, found) }
            sample.hasProxyOrTunnel = proxy.enabled || !tunnels.isEmpty || sample.kind == .vpn
            sample.routeKey = "\(base)|\(proxy.signature)|\(tunnelSig)|\(egress)"
            // Empty means "not known": watchers keep the way out they had rather than see a change.
            sample.egressKey = egress.isEmpty ? "" : "\(base)|\(proxy.signature)|\(egress)"
        }
        sample.lastConnected = lastConnected
        sample.sessionDown = sessionDown
        sample.sessionUp = sessionUp
        sample.todayDown = today.down
        sample.todayUp = today.up
        if probeLatency {
            latency.tick(connected: sample.connected)
            (sample.latencyMS, sample.checks, sample.latencies) = latency.results()
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

    private func proxyState() -> (signature: String, enabled: Bool) {
        let proxies = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/Proxies" as CFString) as? [String: Any] }
        return Self.proxyState(from: proxies)
    }

    static func proxyState(from proxies: [String: Any]?) -> (signature: String, enabled: Bool) {
        guard let proxies else { return ("", false) }
        var enabled = false
        func entry(_ enableKey: String, _ hostKey: String, _ portKey: String) -> String {
            guard (proxies[enableKey] as? NSNumber)?.intValue == 1 else { return "0" }
            enabled = true
            let host = proxies[hostKey] as? String ?? ""
            let port = (proxies[portKey] as? NSNumber)?.intValue ?? 0
            return "1:\(host):\(port)"
        }
        let pacEnabled = (proxies["ProxyAutoConfigEnable"] as? NSNumber)?.intValue == 1
        if pacEnabled { enabled = true }
        let pac = pacEnabled ? (proxies["ProxyAutoConfigURLString"] as? String ?? "1") : "0"
        let sig = "\(entry("HTTPEnable", "HTTPProxy", "HTTPPort"))|\(entry("HTTPSEnable", "HTTPSProxy", "HTTPSPort"))|\(entry("SOCKSEnable", "SOCKSProxy", "SOCKSPort"))|\(pac)"
        return (sig, enabled)
    }

    private struct Adapter {
        var name: String
        var ip: String
        var router: String
    }

    /// The adapter a VPN runs over: the first network service, in the user's service order, that
    /// is up on an interface that isn't a tunnel. Looked up again every 15 s.
    private func adapter() -> Adapter? {
        let now = Date()
        if let cached = adapterCache, now.timeIntervalSince(cached.date) < 15 { return cached.value }
        var found: Adapter?
        if let store {
            let setup = SCDynamicStoreCopyValue(store, "Setup:/Network/Global/IPv4" as CFString) as? [String: Any]
            let order = setup?["ServiceOrder"] as? [String] ?? []
            let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString) as? [String] ?? []
            // "State:/Network/Service/<id>/IPv4"
            let ids = keys.compactMap { $0.split(separator: "/").dropLast().last.map(String.init) }
            for id in ids.sorted(by: { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }) {
                guard let v = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/IPv4" as CFString) as? [String: Any],
                      let name = v["InterfaceName"] as? String, kind(of: name) != .vpn,
                      let ip = (v["Addresses"] as? [String])?.first else { continue }
                found = Adapter(name: name, ip: ip, router: v["Router"] as? String ?? "")
                break
            }
        }
        adapterCache = (now, found)
        return found
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

    static func isTunnelInterface(_ bsdName: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains(where: { bsdName.hasPrefix($0) })
    }

    private func kind(of bsdName: String) -> InterfaceKind {
        if let cached = kindCache[bsdName] { return cached }
        var result: InterfaceKind = .other
        if Self.isTunnelInterface(bsdName) {
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

    struct InterfaceIPv4: Equatable {
        var name: String
        var address: String
        var flags: UInt32
    }

    static func activeTunnels(from interfaces: [InterfaceIPv4]) -> [(name: String, ip: String)] {
        let upRunning = UInt32(IFF_UP | IFF_RUNNING)
        var seen = Set<String>()
        var result: [(name: String, ip: String)] = []
        for entry in interfaces {
            guard isTunnelInterface(entry.name),
                  (entry.flags & upRunning) == upRunning,
                  !entry.address.isEmpty,
                  entry.address != "0.0.0.0",
                  !entry.address.hasPrefix("127."),
                  // Link-local: a tunnel with only this carries no traffic anywhere.
                  !entry.address.hasPrefix("169.254.") else { continue }
            let key = "\(entry.name):\(entry.address)"
            if seen.insert(key).inserted {
                result.append((entry.name, entry.address))
            }
        }
        return result.sorted { a, b in a.name == b.name ? a.ip < b.ip : a.name < b.name }
    }

    static func tunnelSignature(from tunnels: [(name: String, ip: String)]) -> String {
        tunnels.map { "\($0.name):\($0.ip)" }.joined(separator: ",")
    }

    /// The source address macOS picks to reach a public address. Connecting a UDP socket only
    /// looks up the route; nothing is sent. A proxy's TUN mode or a full VPN routes public
    /// addresses through its tunnel, so this is the tunnel's address; a tunnel that only carries
    /// its own subnet (Tailscale without an exit node) doesn't change it.
    static func egressAddress(to target: String = "1.1.1.1") -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(53).bigEndian
        guard inet_pton(AF_INET, target, &address.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        let text = String(cString: buffer)
        return text == "0.0.0.0" ? nil : text
    }

    /// The way out to report: what was just found, else (a lookup failing for a moment) the last
    /// one found on the same network, else "" for not known. Never an empty part that would
    /// read as a different way out.
    static func resolvedEgress(found: String, base: String, last: (base: String, signature: String)?) -> String {
        if !found.isEmpty { return found }
        if let last, last.base == base { return last.signature }
        return ""
    }

    /// Public addresses looked up for the way out, in order. One alone could mislead: a proxy's
    /// TUN can leave a single address (often 1.1.1.1) out of its routes.
    static let egressTargets = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]

    /// The way out most of `targets` route over, as "interface:address", or "" when none could
    /// be looked up. Stops as soon as two agree, so it usually costs two lookups. With no
    /// majority, a tunnel wins over the physical interface, then the earlier target.
    static func egressSignature(targets: [String] = egressTargets, interfaces: [InterfaceIPv4],
                                lookup: (String) -> String? = { egressAddress(to: $0) }) -> String {
        var found: [String] = []
        for target in targets {
            guard let address = lookup(target) else { continue }
            let signature = egressSignature(address: address, interfaces: interfaces)
            if found.contains(signature) { return signature }
            found.append(signature)
        }
        return found.first { isTunnelInterface(String($0.prefix { $0 != ":" })) } ?? found.first ?? ""
    }

    /// "interface:address" for one egress address, or "" when there is none. When several
    /// interfaces carry the address, one that is up and running wins, then a tunnel, then the
    /// first by name.
    static func egressSignature(address: String?, interfaces: [InterfaceIPv4]) -> String {
        guard let address else { return "" }
        let upRunning = UInt32(IFF_UP | IFF_RUNNING)
        let name = interfaces.filter { $0.address == address }
            .min { a, b in
                let ua = a.flags & upRunning == upRunning, ub = b.flags & upRunning == upRunning
                if ua != ub { return ua }
                let ta = isTunnelInterface(a.name), tb = isTunnelInterface(b.name)
                if ta != tb { return ta }
                return a.name < b.name
            }?.name ?? ""
        return "\(name):\(address)"
    }

    private static func allIPv4Interfaces() -> [InterfaceIPv4] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [InterfaceIPv4] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(InterfaceIPv4(name: String(cString: entry.pointee.ifa_name),
                                            address: String(cString: host),
                                            flags: entry.pointee.ifa_flags))
            }
        }
        return result
    }
}


/// Round-trip time to a public resolver over ICMP (an unprivileged datagram socket), every
/// 30 seconds on its own queue. Keeps the last 48 checks for the connection log.
final class LatencyProbe {
    private let queue = DispatchQueue(label: "rin.latency", qos: .utility)
    private let lock = NSLock()
    private var lastStart = Date.distantPast
    private var latest: Double?
    private var checks: [ConnectionCheck] = []
    /// The round trips behind the checks (nil where none was measured).
    private var latencies: [Double?] = []
    private static let target = "1.1.1.1"
    private static let slowMS = 100.0
    /// No reply from the internet comes back this fast; one that does was answered on the Mac.
    private static let localMS = 1.0

    func tick(connected: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastStart) >= 30 else { return }
        lastStart = now
        guard connected else { record(nil); return }
        queue.async { [weak self] in self?.record(Self.ping(Self.target)) }
    }

    func results() -> (Double?, [ConnectionCheck], [Double?]) {
        lock.lock(); defer { lock.unlock() }
        return (latest, checks, latencies)
    }

    private func record(_ ms: Double?) {
        lock.lock(); defer { lock.unlock() }
        if let ms, ms < Self.localMS {
            latest = nil
            checks.append(.unmeasured)
        } else {
            latest = ms
            checks.append(ms.map { $0 < Self.slowMS ? .ok : .slow } ?? .failed)
        }
        latencies.append(latest)
        if checks.count > 48 { checks.removeFirst(checks.count - 48) }
        if latencies.count > 48 { latencies.removeFirst(latencies.count - 48) }
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

/// Checks the Mac's public IP on its own timer when shown in the UI or watched by the IP-change
/// alert. Each probe uses a fresh ephemeral session (`Connection: close`, no cache) so switching
/// a proxy node or VPN tunnel is seen on the very next check instead of reusing an old socket.
final class PublicIPWatcher {
    struct Endpoint: Equatable {
        enum Format: Equatable { case plain, cloudflareTrace, afterColon }
        var url: URL
        var format: Format
        var timeout: TimeInterval
        var overseas: Bool

        var isIPLiteralHost: Bool {
            guard let host = url.host else { return false }
            return PublicIPWatcher.isValidIP(host)
        }

        func parse(_ text: String) -> String? {
            switch format {
            case .plain:
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .cloudflareTrace:
                for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
                    return String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            case .afterColon:
                guard let idx = text.lastIndex(of: ":") else { return nil }
                return text[text.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    enum ProbeErrorKind: Equatable {
        case timeout
        case dns
        case tls
        case connection
        case invalidResponse
    }

    struct ProbeAttemptFailure: Equatable {
        var endpoint: Endpoint
        var kind: ProbeErrorKind
    }

    enum ProbeAttemptResult: Equatable {
        case success(String)
        case failure(ProbeErrorKind)
    }

    typealias CancelToken = () -> Void
    typealias EndpointFetcher = (_ endpoint: Endpoint, _ completion: @escaping (ProbeAttemptResult) -> Void) -> CancelToken

    /// Consecutive full probe failures required before reporting a gentle failure status/alert.
    static let failureReportThreshold = 2

    // Pure IPv4 endpoints so dual-stack networks never flap between IPv4 and IPv6.
    // Overseas endpoints run first (seeing proxy/VPN exit IPs); direct China-reachable endpoints
    // serve as fallback only when the way out changed or the connection was not already overseas.
    // The IP-literal endpoint goes last of the overseas ones: a proxy can route 1.1.1.1/32 on
    // its own (often straight out), and then it would see the direct IP, not the proxy's.
    static let endpoints: [Endpoint] = [
        Endpoint(url: URL(string: "https://api.ipify.org")!, format: .plain, timeout: 4.5, overseas: true),
        Endpoint(url: URL(string: "https://v4.ident.me")!, format: .plain, timeout: 4.0, overseas: true),
        Endpoint(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, format: .cloudflareTrace, timeout: 4.0, overseas: true),
        Endpoint(url: URL(string: "https://myip.ipip.net/s")!, format: .plain, timeout: 3.5, overseas: false),
        Endpoint(url: URL(string: "https://ddns.oray.com/checkip")!, format: .afterColon, timeout: 3.5, overseas: false),
    ]

    var onUpdate: ((String) -> Void)?
    var onFailure: ((PublicIPFailureReason) -> Void)?
    var onFailureCleared: (() -> Void)?

    private let queue = DispatchQueue(label: "rin.publicIP", qos: .utility)
    private let callbackQueue: DispatchQueue
    private let fetcher: EndpointFetcher
    private let now: () -> Date
    private let enableTimer: Bool
    private let endpoints: [Endpoint]

    private var timer: DispatchSourceTimer?
    private var timerInterval: TimeInterval = 0
    private var active = false
    private var connected = false
    private var route = ""
    private var egress = ""
    private var hasProxyOrTunnel = false
    private var interval: TimeInterval = 600
    private var lastStarted = Date.distantPast
    private var lastSucceeded = Date.distantPast
    private var inFlight = false
    private var generation: UInt64 = 0
    private var currentCancel: CancelToken?
    /// Tracks whether global/overseas endpoints were reachable on the current route; when false
    /// (e.g. direct mainland China network without VPN), skips the blackholed secondary overseas
    /// probes so direct fallback stays fast while still probing primary in case a proxy comes back.
    private var overseasReachable = true
    /// The source (`overseas` vs direct), route and way out of the last successful probe.
    private var lastSuccessOverseas: Bool?
    private var lastSuccessRoute = ""
    private var lastSuccessEgress = ""
    private var consecutiveFailures = 0
    private var reportedFailure: PublicIPFailureReason?
    /// A failure went to `onFailure` and no `onFailureCleared` has followed. A success doesn't
    /// reset it: its delivery can still be dropped (the state moved on before it ran), and then
    /// only a clear closes what the failure opened.
    private var failureShown = false
    /// The stale epoch the probe in flight started in.
    private var probeEpoch: UInt64 = 0

    /// What a callback still waiting on `callbackQueue` checks before it runs, behind a lock:
    /// the generation it belongs to and whether checks are on and the Mac connected (written on
    /// `queue`), and the stale epoch (bumped on the caller's thread).
    private let deliveryLock = NSLock()
    private var deliverable: (generation: UInt64, live: Bool) = (0, false)
    /// Bumped on the caller's thread the moment results go stale (a disconnect, a new route or
    /// way out, checks turned off, `stop()`), before `queue` gets to it: a result already waiting
    /// on `callbackQueue` can't run in between.
    private var staleEpoch: UInt64 = 0
    /// The network as the caller last reported it, to tell on its thread whether results went stale.
    private var reportedNetwork: (connected: Bool, route: String, egress: String) = (false, "", "")

    init(
        endpoints: [Endpoint] = PublicIPWatcher.endpoints,
        fetcher: @escaping EndpointFetcher = PublicIPWatcher.liveFetch,
        callbackQueue: DispatchQueue = .main,
        now: @escaping () -> Date = Date.init,
        enableTimer: Bool = true
    ) {
        self.endpoints = endpoints
        self.fetcher = fetcher
        self.callbackQueue = callbackQueue
        self.now = now
        self.enableTimer = enableTimer
    }

    func configure(active: Bool, interval: TimeInterval, immediate: Bool = false) {
        if !active { invalidateResultsNow() }
        queue.async {
            let clamped = min(max(interval, AlertPrefs.publicIPIntervalRange.lowerBound), AlertPrefs.publicIPIntervalRange.upperBound)
            guard active else {
                if self.active {
                    self.active = false
                    self.overseasReachable = true
                    self.lastSuccessOverseas = nil
                    self.lastSuccessRoute = ""
                    self.lastSuccessEgress = ""
                    self.consecutiveFailures = 0
                    self.cancelInFlight()
                    self.clearReportedFailure()
                    self.stopTimer()
                    self.lastStarted = .distantPast
                    self.lastSucceeded = .distantPast
                }
                return
            }
            let wasActive = self.active
            let intervalChanged = self.interval != clamped
            self.active = true
            self.interval = clamped
            self.publishDeliverable()
            if self.enableTimer { self.rescheduleTimer() }
            if self.connected {
                if !wasActive || immediate {
                    self.probe(force: true)
                } else if intervalChanged, self.now().timeIntervalSince(self.lastStarted) >= clamped {
                    self.probe(force: false)
                }
            }
        }
    }

    /// `route` changing means "check again"; `egress` changing means the way out changed, which
    /// alone lets a check fall back to the direct endpoints after an overseas IP.
    func networkChanged(connected: Bool, route: String, egress: String, hasProxyOrTunnel: Bool) {
        deliveryLock.lock()
        let last = reportedNetwork
        let moved = (!last.route.isEmpty && !route.isEmpty && route != last.route)
            || (!last.egress.isEmpty && !egress.isEmpty && egress != last.egress)
        if (last.connected && !connected) || (connected && moved) { staleEpoch &+= 1 }
        reportedNetwork.connected = connected
        if !route.isEmpty { reportedNetwork.route = route }
        if !egress.isEmpty { reportedNetwork.egress = egress }
        deliveryLock.unlock()

        queue.async {
            let wasConnected = self.connected
            let routeChanged = (!self.route.isEmpty && !route.isEmpty && route != self.route)
                || (!self.egress.isEmpty && !egress.isEmpty && egress != self.egress)
            self.connected = connected
            self.hasProxyOrTunnel = hasProxyOrTunnel
            if !route.isEmpty { self.route = route }
            if !egress.isEmpty { self.egress = egress }
            guard self.active else {
                self.publishDeliverable()
                return
            }
            guard connected else {
                self.cancelInFlight()
                self.consecutiveFailures = 0
                self.clearReportedFailure()
                return
            }
            if routeChanged {
                self.overseasReachable = true
                self.consecutiveFailures = 0
                self.cancelInFlight()
                self.clearReportedFailure()
                self.probe(force: true)
            } else if !wasConnected {
                self.publishDeliverable()
                if self.lastSuccessRoute != self.route { self.overseasReachable = true }
                self.consecutiveFailures = 0
                self.clearReportedFailure()
                self.probe(force: true)
            }
        }
    }

    /// Triggers an immediate check on the watcher's queue (used by unit tests to drive retries deterministically).
    func probeNow(force: Bool = true) {
        queue.async { self.probe(force: force) }
    }

    #if DEBUG
    /// Runs everything queued on the watcher's queue; then, unless told not to (a test holding
    /// `callbackQueue` suspended), everything queued for delivery.
    func flushForTesting(includingCallbacks: Bool = true) {
        for _ in 0..<(endpoints.count + 2) { queue.sync {} }
        if includingCallbacks { callbackQueue.sync {} }
    }
    #endif

    func stop() {
        invalidateResultsNow()
        queue.sync {
            active = false
            overseasReachable = true
            lastSuccessOverseas = nil
            lastSuccessRoute = ""
            lastSuccessEgress = ""
            consecutiveFailures = 0
            cancelInFlight()
            clearReportedFailure()
            stopTimer()
        }
    }

    static func shouldAllowDirectFallback(
        lastSuccessOverseas: Bool?,
        lastSuccessEgress: String,
        currentEgress: String,
        hasProxyOrTunnel: Bool,
        consecutiveFailures: Int
    ) -> Bool {
        let sameEgress = !currentEgress.isEmpty && currentEgress == lastSuccessEgress
        // Never known then or now (the lookups keep failing): no sign the way out changed.
        let stillUnknown = currentEgress.isEmpty && lastSuccessEgress.isEmpty
        // Never fall back to China-direct endpoints when the previous IP came from an overseas
        // endpoint and the way out (physical network, system proxy, the interface public
        // addresses route over) is the same: a proxy hiccup, or a tunnel reconnecting beside the
        // one carrying the traffic, must not masquerade as a public IP change.
        if lastSuccessOverseas == true && (sameEgress || stillUnknown) {
            return false
        }
        // When a proxy or tunnel is active on a fresh/changed way out, try overseas endpoints once
        // before falling back so TUN/proxy startup races don't grab a direct IP prematurely.
        if hasProxyOrTunnel && !sameEgress && consecutiveFailures == 0 {
            return false
        }
        return true
    }

    static func probePlan(
        endpoints: [Endpoint] = PublicIPWatcher.endpoints,
        overseasReachable: Bool,
        lastSuccessOverseas: Bool?,
        lastSuccessEgress: String,
        currentEgress: String,
        hasProxyOrTunnel: Bool,
        consecutiveFailures: Int
    ) -> (endpoints: [Endpoint], overseasOnly: Bool) {
        let allowDirect = shouldAllowDirectFallback(
            lastSuccessOverseas: lastSuccessOverseas,
            lastSuccessEgress: lastSuccessEgress,
            currentEgress: currentEgress,
            hasProxyOrTunnel: hasProxyOrTunnel,
            consecutiveFailures: consecutiveFailures
        )
        let overseas = endpoints.filter(\.overseas)
        let direct = endpoints.filter { !$0.overseas }
        if !allowDirect {
            return (overseas, true)
        }
        if overseasReachable || overseas.isEmpty {
            return (overseas + direct, false)
        }
        return ([overseas[0]] + direct, false)
    }

    static func classifyURLError(_ error: Error?) -> ProbeErrorKind {
        guard let error else { return .invalidResponse }
        let code: URLError.Code
        if let urlError = error as? URLError {
            code = urlError.code
        } else {
            let ns = error as NSError
            guard ns.domain == NSURLErrorDomain else { return .invalidResponse }
            code = URLError.Code(rawValue: ns.code)
        }
        switch code {
        case .timedOut:
            return .timeout
        case .cannotFindHost, .dnsLookupFailed:
            return .dns
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return .tls
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
             .cannotLoadFromNetwork, .internationalRoamingOff, .dataNotAllowed:
            return .connection
        default:
            return .invalidResponse
        }
    }

    static func classifyFailure(failures: [ProbeAttemptFailure], overseasOnly: Bool) -> PublicIPFailureReason {
        guard !failures.isEmpty else { return overseasOnly ? .overseasUnreachable : .unreachable }
        let hostnameFailures = failures.filter { !$0.endpoint.isIPLiteralHost }
        if !hostnameFailures.isEmpty && hostnameFailures.allSatisfy({ $0.kind == .dns }) {
            return .dnsFailed
        }
        let kinds = failures.map(\.kind)
        if kinds.allSatisfy({ $0 == .timeout }) {
            return .timedOut
        }
        if overseasOnly {
            if kinds.contains(.timeout) && !kinds.contains(.connection) && !kinds.contains(.tls) {
                return .timedOut
            }
            return .overseasUnreachable
        }
        if kinds.contains(.dns) { return .dnsFailed }
        if kinds.contains(.timeout) { return .timedOut }
        return .unreachable
    }

    private func rescheduleTimer() {
        // Retry failures after a minute in slow display-only mode, or on the next tick in alert mode.
        let tick = min(interval, 60)
        guard timer == nil || timerInterval != tick else { return }
        stopTimer()
        timerInterval = tick
        let t = DispatchSource.makeTimerSource(queue: queue)
        let leeway = min(Int(tick * 100), 500)
        t.schedule(deadline: .now() + tick, repeating: tick, leeway: .milliseconds(max(leeway, 50)))
        t.setEventHandler { [weak self] in self?.probe(force: false) }
        t.resume()
        timer = t
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        timerInterval = 0
    }

    private func cancelInFlight() {
        generation &+= 1
        currentCancel?()
        currentCancel = nil
        inFlight = false
        publishDeliverable()
    }

    /// Call on `queue` after `generation`, `active` or `connected` changes.
    private func publishDeliverable() {
        deliveryLock.lock()
        deliverable = (generation, active && connected)
        deliveryLock.unlock()
    }

    /// On the caller's thread: results of probes started before now must not be delivered.
    private func invalidateResultsNow() {
        deliveryLock.lock()
        staleEpoch &+= 1
        deliveryLock.unlock()
    }

    private func currentStaleEpoch() -> UInt64 {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        return staleEpoch
    }

    /// Runs a probe's result on `callbackQueue` only if, by the time it gets there, nothing made
    /// it stale since the probe started (a disconnect, a new route or way out, checks turned off,
    /// `stop()`), whether `queue` has caught up with that yet or not.
    private func deliver(_ gen: UInt64, _ body: @escaping () -> Void) {
        let epoch = probeEpoch
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.deliveryLock.lock()
            let current = self.deliverable
            let stale = self.staleEpoch != epoch
            self.deliveryLock.unlock()
            guard current.generation == gen, current.live, !stale else { return }
            body()
        }
    }

    /// Clearing is not checked like results: it is queued in the same order as every result,
    /// so a later failure still lands after it, and it only says what was true when queued.
    /// It goes out whenever a failure was shown, even after a success whose delivery may have
    /// been dropped; a clear with nothing open does nothing.
    private func clearReportedFailure() {
        guard reportedFailure != nil || failureShown else { return }
        reportedFailure = nil
        failureShown = false
        let cb = onFailureCleared
        callbackQueue.async { cb?() }
    }

    private func probe(force: Bool) {
        guard active, connected, !inFlight else { return }
        let timestamp = now()
        if !force {
            let failed = lastStarted > lastSucceeded
            let wait = failed && interval > 60 ? 60 : interval
            guard timestamp.timeIntervalSince(lastStarted) >= wait - 0.15 else { return }
        }
        inFlight = true
        lastStarted = timestamp
        probeEpoch = currentStaleEpoch()
        let probeRoute = route
        let probeEgress = egress
        let plan = Self.probePlan(
            endpoints: endpoints,
            overseasReachable: overseasReachable,
            lastSuccessOverseas: lastSuccessOverseas,
            lastSuccessEgress: lastSuccessEgress,
            currentEgress: probeEgress,
            hasProxyOrTunnel: hasProxyOrTunnel,
            consecutiveFailures: consecutiveFailures
        )
        fetch(plan: plan.endpoints, overseasOnly: plan.overseasOnly, probeRoute: probeRoute, probeEgress: probeEgress,
              index: 0, failures: [], generation: generation)
    }

    private func fetch(
        plan: [Endpoint],
        overseasOnly: Bool,
        probeRoute: String,
        probeEgress: String,
        index: Int,
        failures: [ProbeAttemptFailure],
        generation gen: UInt64
    ) {
        guard active, connected, generation == gen, index < plan.count else {
            if generation == gen { inFlight = false }
            return
        }
        let endpoint = plan[index]
        currentCancel = fetcher(endpoint) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.generation == gen else { return }
                self.currentCancel = nil
                switch result {
                case .success(let ip) where Self.isValidIP(ip):
                    self.inFlight = false
                    self.lastSucceeded = self.now()
                    self.overseasReachable = endpoint.overseas
                    self.lastSuccessOverseas = endpoint.overseas
                    self.lastSuccessRoute = probeRoute
                    self.lastSuccessEgress = probeEgress
                    self.consecutiveFailures = 0
                    self.reportedFailure = nil
                    let cb = self.onUpdate
                    self.deliver(gen) { cb?(ip) }
                    return
                case .success:
                    self.advance(plan: plan, overseasOnly: overseasOnly, probeRoute: probeRoute, probeEgress: probeEgress, index: index,
                                 failures: failures + [ProbeAttemptFailure(endpoint: endpoint, kind: .invalidResponse)], generation: gen)
                case .failure(let kind):
                    self.advance(plan: plan, overseasOnly: overseasOnly, probeRoute: probeRoute, probeEgress: probeEgress, index: index,
                                 failures: failures + [ProbeAttemptFailure(endpoint: endpoint, kind: kind)], generation: gen)
                }
            }
        }
    }

    private func advance(
        plan: [Endpoint],
        overseasOnly: Bool,
        probeRoute: String,
        probeEgress: String,
        index: Int,
        failures: [ProbeAttemptFailure],
        generation gen: UInt64
    ) {
        let next = index + 1
        if next < plan.count, active, connected {
            fetch(plan: plan, overseasOnly: overseasOnly, probeRoute: probeRoute, probeEgress: probeEgress,
                  index: next, failures: failures, generation: gen)
            return
        }
        inFlight = false
        consecutiveFailures += 1
        let sameEgress = !probeEgress.isEmpty && probeEgress == lastSuccessEgress
        // After the one-shot overseas-only pass on a new/fresh way out fails (e.g. a proxy turned
        // off while Tailscale stays up, or a proxy still warming up at login), retry shortly so
        // slow display-only polling does not stall for 60 s.
        if enableTimer, hasProxyOrTunnel, !sameEgress, consecutiveFailures == 1, interval > 3 {
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.generation == gen, self.active, self.connected, !self.inFlight else { return }
                self.probe(force: true)
            }
        }
        guard consecutiveFailures >= Self.failureReportThreshold else { return }
        let reason = Self.classifyFailure(failures: failures, overseasOnly: overseasOnly)
        if reportedFailure != reason {
            reportedFailure = reason
            failureShown = true
            let cb = onFailure
            deliver(gen) { cb?(reason) }
        }
    }

    private static func liveFetch(_ endpoint: Endpoint, completion: @escaping (ProbeAttemptResult) -> Void) -> CancelToken {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = endpoint.timeout
        config.timeoutIntervalForResource = endpoint.timeout + 1
        config.httpAdditionalHeaders = ["Connection": "close", "Cache-Control": "no-cache"]
        let session = URLSession(configuration: config)

        var request = URLRequest(url: endpoint.url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = endpoint.timeout

        let task = session.dataTask(with: request) { data, response, error in
            session.finishTasksAndInvalidate()
            if error == nil,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, let text = String(data: data, encoding: .utf8),
               let ip = endpoint.parse(text), Self.isValidIP(ip) {
                completion(.success(ip))
            } else {
                completion(.failure(Self.classifyURLError(error)))
            }
        }
        task.resume()
        return { session.invalidateAndCancel() }
    }

    static func isValidIP(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 45 else { return false }
        var v4 = in_addr()
        if s.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }
        var v6 = in6_addr()
        if s.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 { return true }
        return false
    }
}
