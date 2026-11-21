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
        let now = Date()
        if let name, let c = counters[name] {
            sample.interface = name
            sample.kind = kind(of: name)
            sample.localIP = Self.ipv4(of: name) ?? ""
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
            sample.routeKey = "\(sample.interface)|\(sample.localIP)|\(sample.router)|\(proxySignature())"
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

    private func proxySignature() -> String {
        guard let store,
              let proxies = SCDynamicStoreCopyValue(store, "State:/Network/Global/Proxies" as CFString) as? [String: Any] else { return "" }
        func entry(_ enableKey: String, _ hostKey: String, _ portKey: String) -> String {
            guard (proxies[enableKey] as? NSNumber)?.intValue == 1 else { return "0" }
            let host = proxies[hostKey] as? String ?? ""
            let port = (proxies[portKey] as? NSNumber)?.intValue ?? 0
            return "1:\(host):\(port)"
        }
        let pac = (proxies["ProxyAutoConfigEnable"] as? NSNumber)?.intValue == 1
            ? (proxies["ProxyAutoConfigURLString"] as? String ?? "1") : "0"
        return "\(entry("HTTPEnable", "HTTPProxy", "HTTPPort"))|\(entry("HTTPSEnable", "HTTPSProxy", "HTTPSPort"))|\(entry("SOCKSEnable", "SOCKSProxy", "SOCKSPort"))|\(pac)"
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
    var onUpdate: ((String) -> Void)?

    private let queue = DispatchQueue(label: "rin.publicIP", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var timerInterval: TimeInterval = 0
    private var active = false
    private var connected = false
    private var route = ""
    private var interval: TimeInterval = 600
    private var lastStarted = Date.distantPast
    private var lastSucceeded = Date.distantPast
    private var inFlight = false
    private var generation: UInt64 = 0
    private var currentSession: URLSession?
    /// Tracks whether global/overseas endpoints were reachable on the current route; when false
    /// (e.g. direct mainland China network without VPN), skips the blackholed secondary overseas
    /// probe so direct fallback stays fast while still probing primary in case VPN comes back.
    private var overseasReachable = true

    private struct Endpoint {
        enum Format { case plain, cloudflareTrace, afterColon }
        var url: URL
        var format: Format
        var timeout: TimeInterval
        var overseas: Bool

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

    // Pure IPv4 endpoints so dual-stack networks never flap between IPv4 and IPv6.
    // Overseas endpoints run first (seeing proxy/VPN exit IPs); direct China-reachable endpoints
    // serve as fallback when overseas endpoints are blocked or unreachable (e.g. VPN turned off).
    private static let endpoints: [Endpoint] = [
        Endpoint(url: URL(string: "https://api.ipify.org")!, format: .plain, timeout: 3.5, overseas: true),
        Endpoint(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, format: .cloudflareTrace, timeout: 3.0, overseas: true),
        Endpoint(url: URL(string: "https://myip.ipip.net/s")!, format: .plain, timeout: 3.0, overseas: false),
        Endpoint(url: URL(string: "https://ddns.oray.com/checkip")!, format: .afterColon, timeout: 3.0, overseas: false),
    ]

    func configure(active: Bool, interval: TimeInterval, immediate: Bool = false) {
        queue.async {
            let clamped = min(max(interval, AlertPrefs.publicIPIntervalRange.lowerBound), AlertPrefs.publicIPIntervalRange.upperBound)
            guard active else {
                if self.active {
                    self.active = false
                    self.overseasReachable = true
                    self.cancelInFlight()
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
            self.rescheduleTimer()
            if self.connected {
                if !wasActive || immediate {
                    self.probe(force: true)
                } else if intervalChanged, Date().timeIntervalSince(self.lastStarted) >= clamped {
                    self.probe(force: false)
                }
            }
        }
    }

    func networkChanged(connected: Bool, route: String) {
        queue.async {
            let wasConnected = self.connected
            let routeChanged = !self.route.isEmpty && !route.isEmpty && route != self.route
            self.connected = connected
            if !route.isEmpty { self.route = route }
            guard self.active else { return }
            guard connected else {
                self.cancelInFlight()
                return
            }
            if routeChanged {
                self.overseasReachable = true
                self.cancelInFlight()
                self.probe(force: true)
            } else if !wasConnected {
                self.overseasReachable = true
                self.probe(force: true)
            }
        }
    }

    func stop() {
        queue.sync {
            active = false
            cancelInFlight()
            stopTimer()
        }
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
        currentSession?.invalidateAndCancel()
        currentSession = nil
        inFlight = false
    }

    private func probe(force: Bool) {
        guard active, connected, !inFlight else { return }
        let now = Date()
        if !force {
            let failed = lastStarted > lastSucceeded
            let wait = failed && interval > 60 ? 60 : interval
            guard now.timeIntervalSince(lastStarted) >= wait - 0.15 else { return }
        }
        inFlight = true
        lastStarted = now
        let plan = overseasReachable
            ? Self.endpoints
            : [Self.endpoints[0]] + Self.endpoints.filter { !$0.overseas }
        fetch(plan: plan, index: 0, generation: generation)
    }

    private func fetch(plan: [Endpoint], index: Int, generation gen: UInt64) {
        guard active, connected, generation == gen, index < plan.count else {
            if generation == gen { inFlight = false }
            return
        }
        let endpoint = plan[index]
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = endpoint.timeout
        config.timeoutIntervalForResource = endpoint.timeout + 1
        config.httpAdditionalHeaders = ["Connection": "close", "Cache-Control": "no-cache"]
        let session = URLSession(configuration: config)
        currentSession = session

        var request = URLRequest(url: endpoint.url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = endpoint.timeout

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            session.finishTasksAndInvalidate()
            guard let self else { return }
            self.queue.async {
                guard self.generation == gen else { return }
                if self.currentSession === session { self.currentSession = nil }
                if error == nil,
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let data, let text = String(data: data, encoding: .utf8),
                   let ip = endpoint.parse(text), Self.isValidIP(ip) {
                    self.inFlight = false
                    self.lastSucceeded = Date()
                    self.overseasReachable = endpoint.overseas
                    let cb = self.onUpdate
                    DispatchQueue.main.async { cb?(ip) }
                    return
                }
                let next = index + 1
                if next < plan.count, self.active, self.connected {
                    self.fetch(plan: plan, index: next, generation: gen)
                } else {
                    self.inFlight = false
                }
            }
        }
        task.resume()
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
