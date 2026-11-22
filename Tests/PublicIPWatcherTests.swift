import Darwin
import Foundation
import XCTest
@testable import Rin

final class PublicIPWatcherTests: XCTestCase {
    private let upRunning = UInt32(IFF_UP | IFF_RUNNING)

    override func setUp() {
        super.setUp()
        SettingsStore.persistenceEnabled = false
        Alerts.shared.deliverNotification = nil
        Alerts.shared.debugReset()
    }

    override func tearDown() {
        Alerts.shared.deliverNotification = nil
        Alerts.shared.debugReset()
        super.tearDown()
    }

    // MARK: - NetworkReader tunnel & proxy signatures

    func testActiveTunnelsFiltersSystemUtunsAndDownInterfaces() {
        let interfaces: [NetworkReader.InterfaceIPv4] = [
            .init(name: "lo0", address: "127.0.0.1", flags: upRunning),
            .init(name: "en0", address: "192.168.3.5", flags: upRunning),
            // Down tunnel (missing IFF_UP, like utun4)
            .init(name: "utun4", address: "10.0.0.1", flags: UInt32(IFF_RUNNING)),
            // Loopback / unspecified IPv4 on a tunnel should be ignored
            .init(name: "utun1", address: "127.0.0.2", flags: upRunning),
            .init(name: "utun2", address: "0.0.0.0", flags: upRunning),
            // Active tunnels (unsorted input + duplicate entry)
            .init(name: "wg0", address: "10.8.0.2", flags: upRunning),
            .init(name: "utun5", address: "198.18.0.1", flags: upRunning),
            .init(name: "utun5", address: "198.18.0.1", flags: upRunning),
            .init(name: "ipsec0", address: "172.16.0.5", flags: upRunning),
        ]

        let tunnels = NetworkReader.activeTunnels(from: interfaces)
        XCTAssertEqual(tunnels.map(\.name), ["ipsec0", "utun5", "wg0"])
        XCTAssertEqual(NetworkReader.tunnelSignature(from: tunnels), "ipsec0:172.16.0.5,utun5:198.18.0.1,wg0:10.8.0.2")
    }

    func testProxyStateDetectsEnabledAndDisabledProxies() {
        let off = NetworkReader.proxyState(from: [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0,
        ])
        XCTAssertFalse(off.enabled)
        XCTAssertEqual(off.signature, "0|0|0|0")

        let socks = NetworkReader.proxyState(from: [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 1,
            "SOCKSProxy": "127.0.0.1",
            "SOCKSPort": 7890,
            "ProxyAutoConfigEnable": 0,
        ])
        XCTAssertTrue(socks.enabled)
        XCTAssertEqual(socks.signature, "0|0|1:127.0.0.1:7890|0")

        let pac = NetworkReader.proxyState(from: [
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "http://127.0.0.1:7890/pac",
        ])
        XCTAssertTrue(pac.enabled)
        XCTAssertEqual(pac.signature, "0|0|0|http://127.0.0.1:7890/pac")
    }

    func testActiveTunnelsIgnoresLinkLocalAddresses() {
        let interfaces: [NetworkReader.InterfaceIPv4] = [
            .init(name: "utun6", address: "169.254.12.34", flags: upRunning),
            .init(name: "utun5", address: "198.18.0.1", flags: upRunning),
        ]
        XCTAssertEqual(NetworkReader.activeTunnels(from: interfaces).map(\.name), ["utun5"])
        XCTAssertTrue(NetworkReader.activeTunnels(from: [.init(name: "utun7", address: "169.254.0.1", flags: upRunning)]).isEmpty)
    }

    func testEgressSignatureNamesTheInterfacePublicTrafficLeavesThrough() {
        let interfaces: [NetworkReader.InterfaceIPv4] = [
            .init(name: "en0", address: "192.168.3.5", flags: upRunning),
            .init(name: "utun3", address: "100.64.0.1", flags: upRunning),
            .init(name: "utun5", address: "198.18.0.1", flags: upRunning),
        ]
        XCTAssertEqual(NetworkReader.egressSignature(address: "198.18.0.1", interfaces: interfaces), "utun5:198.18.0.1")
        XCTAssertEqual(NetworkReader.egressSignature(address: "192.168.3.5", interfaces: interfaces), "en0:192.168.3.5")
        XCTAssertEqual(NetworkReader.egressSignature(address: nil, interfaces: interfaces), "")
        // The live lookup only consults the routing table; whatever it finds is an IPv4 address.
        if let live = NetworkReader.egressAddress() {
            XCTAssertTrue(PublicIPWatcher.isValidIP(live), live)
        }
    }

    func testIPLiteralEndpointIsTheLastOverseasOne() {
        // A proxy that routes 1.1.1.1/32 straight out would report the direct IP from it.
        let overseas = PublicIPWatcher.endpoints.filter(\.overseas)
        XCTAssertEqual(overseas.map { $0.url.host ?? "" }, ["api.ipify.org", "v4.ident.me", "1.1.1.1"])
        XCTAssertEqual(overseas.firstIndex(where: \.isIPLiteralHost), overseas.count - 1)
    }

    func testOverseasIPWithTheWayOutNeverKnownNeverFallsBackToDirect() {
        // The egress lookups have failed since launch: "" before and after is no change.
        XCTAssertFalse(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: "", currentEgress: "",
            hasProxyOrTunnel: true, consecutiveFailures: 3))
        XCTAssertFalse(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: "", currentEgress: "",
            hasProxyOrTunnel: false, consecutiveFailures: 3))
        // Before any success, unknown still means "fresh": one overseas pass, then direct.
        XCTAssertFalse(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: nil, lastSuccessEgress: "", currentEgress: "",
            hasProxyOrTunnel: true, consecutiveFailures: 0))
        XCTAssertTrue(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: nil, lastSuccessEgress: "", currentEgress: "",
            hasProxyOrTunnel: true, consecutiveFailures: 1))

        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.neverKnown")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var requestedURLs: [String] = []
        var updates: [String] = []
        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                requestedURLs.append(endpoint.url.absoluteString)
                completion(endpoint.overseas ? overseasResult : .success("183.241.150.62"))
                return {}
            },
            callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: route, egress: "", hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])

        overseasResult = .failure(.timeout)
        requestedURLs.removeAll()
        for _ in 0..<3 {
            watcher.probeNow(force: true)
            drain(watcher, callbackQueue)
        }
        XCTAssertTrue(requestedURLs.allSatisfy { !$0.contains("ipip.net") && !$0.contains("oray.com") },
                      "Direct fallback with the way out never known: \(requestedURLs)")
        XCTAssertEqual(updates, ["179.253.226.232"])
        watcher.stop()
    }

    func testEgressFollowsMostTargetsSoOneAddressLeftOutOfTheTunnelDoesNotDecide() {
        let interfaces: [NetworkReader.InterfaceIPv4] = [
            .init(name: "en0", address: "192.168.3.5", flags: upRunning),
            .init(name: "utun5", address: "198.18.0.1", flags: upRunning),
        ]
        var asked: [String] = []
        // 1.1.1.1/32 excluded from the TUN: it goes direct, the others through utun5.
        let excluded = NetworkReader.egressSignature(interfaces: interfaces) { target in
            asked.append(target)
            return target == "1.1.1.1" ? "192.168.3.5" : "198.18.0.1"
        }
        XCTAssertEqual(excluded, "utun5:198.18.0.1")
        XCTAssertEqual(asked, ["1.1.1.1", "8.8.8.8", "9.9.9.9"])

        // The usual case stops after two agreeing lookups.
        asked.removeAll()
        let agreed = NetworkReader.egressSignature(interfaces: interfaces) { target in
            asked.append(target)
            return "198.18.0.1"
        }
        XCTAssertEqual(agreed, "utun5:198.18.0.1")
        XCTAssertEqual(asked, ["1.1.1.1", "8.8.8.8"])

        // Failed lookups are skipped; with no majority a tunnel wins; with none at all, unknown.
        XCTAssertEqual(NetworkReader.egressSignature(interfaces: interfaces) { $0 == "1.1.1.1" ? "192.168.3.5" : ($0 == "8.8.8.8" ? nil : "198.18.0.1") },
                       "utun5:198.18.0.1")
        XCTAssertEqual(NetworkReader.egressSignature(interfaces: interfaces) { _ in nil }, "")
    }

    func testEgressAddressSharedByInterfacesPrefersOneThatIsUpAndRunning() {
        let interfaces: [NetworkReader.InterfaceIPv4] = [
            .init(name: "bridge0", address: "10.0.0.2", flags: UInt32(IFF_UP)),
            .init(name: "utun9", address: "10.0.0.2", flags: upRunning),
            .init(name: "en5", address: "10.0.0.2", flags: upRunning),
        ]
        XCTAssertEqual(NetworkReader.egressSignature(address: "10.0.0.2", interfaces: interfaces), "utun9:10.0.0.2")
        let physical: [NetworkReader.InterfaceIPv4] = [
            .init(name: "en7", address: "10.0.0.3", flags: UInt32(IFF_UP)),
            .init(name: "en6", address: "10.0.0.3", flags: upRunning),
        ]
        XCTAssertEqual(NetworkReader.egressSignature(address: "10.0.0.3", interfaces: physical), "en6:10.0.0.3")
    }

    func testFailedEgressLookupKeepsTheLastWayOutInsteadOfReadingAsAChange() {
        let base = "en0|192.168.3.5|192.168.3.1"
        let last = (base: base, signature: "utun5:198.18.0.1")
        XCTAssertEqual(NetworkReader.resolvedEgress(found: "en0:192.168.3.5", base: base, last: last), "en0:192.168.3.5")
        XCTAssertEqual(NetworkReader.resolvedEgress(found: "", base: base, last: last), "utun5:198.18.0.1")
        // On another network the old way out says nothing: unknown, not a change.
        XCTAssertEqual(NetworkReader.resolvedEgress(found: "", base: "en0|10.0.0.8|10.0.0.1", last: last), "")
        XCTAssertEqual(NetworkReader.resolvedEgress(found: "", base: base, last: nil), "")
    }

    func testUnknownEgressNeitherCountsAsAChangeNorDropsWaitingResults() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.unknownEgress")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var requestedURLs: [String] = []
        var updates: [String] = []
        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                requestedURLs.append(endpoint.url.absoluteString)
                completion(endpoint.overseas ? overseasResult : .success("183.241.150.62"))
                return {}
            },
            callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)

        // A lookup fails for a moment: egress "" (unknown). The way out stays as it was, so a
        // failing proxy still never falls back to direct.
        overseasResult = .failure(.timeout)
        requestedURLs.removeAll()
        watcher.networkChanged(connected: true, route: route, egress: "", hasProxyOrTunnel: true)
        for _ in 0..<3 {
            watcher.probeNow(force: true)
            drain(watcher, callbackQueue)
        }
        XCTAssertTrue(requestedURLs.allSatisfy { !$0.contains("ipip.net") && !$0.contains("oray.com") })
        XCTAssertEqual(updates, ["179.253.226.232"])
        watcher.stop()
    }

    func testDirectFallbackFollowsTheWayOutNotTheTunnelList() {
        let viaFlClash = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let direct = "en0|192.168.3.5|192.168.3.1|0|0|0|0|en0:192.168.3.5"
        let otherWiFi = "en0|10.0.0.8|10.0.0.1|0|0|0|0|utun5:198.18.0.1"
        // Same way out after an overseas IP: never, however many checks failed.
        XCTAssertFalse(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: viaFlClash, currentEgress: viaFlClash,
            hasProxyOrTunnel: true, consecutiveFailures: 5))
        // The tunnel carrying it went away: after one overseas-only pass.
        XCTAssertFalse(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: viaFlClash, currentEgress: direct,
            hasProxyOrTunnel: true, consecutiveFailures: 0))
        XCTAssertTrue(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: viaFlClash, currentEgress: direct,
            hasProxyOrTunnel: true, consecutiveFailures: 1))
        // A different physical network counts as a different way out too.
        XCTAssertTrue(PublicIPWatcher.shouldAllowDirectFallback(
            lastSuccessOverseas: true, lastSuccessEgress: viaFlClash, currentEgress: otherWiFi,
            hasProxyOrTunnel: true, consecutiveFailures: 1))
    }

    // MARK: - Failure classification

    func testClassifyURLErrorMappings() {
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.timedOut)), .timeout)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.cannotFindHost)), .dns)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.dnsLookupFailed)), .dns)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.cannotConnectToHost)), .connection)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.networkConnectionLost)), .connection)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(URLError(.secureConnectionFailed)), .tls)
        XCTAssertEqual(PublicIPWatcher.classifyURLError(nil), .invalidResponse)
    }

    func testClassifyFailureDistinguishesTimeoutDNSAndOverseasUnreachable() {
        let overseas = PublicIPWatcher.endpoints.filter(\.overseas)
        let ipify = overseas.first { $0.url.host == "api.ipify.org" }!
        let cloudflare = overseas.first(where: \.isIPLiteralHost)! // 1.1.1.1
        let ident = overseas.first { $0.url.host == "v4.ident.me" }!

        // All timed out -> .timedOut
        XCTAssertEqual(
            PublicIPWatcher.classifyFailure(
                failures: [
                    .init(endpoint: ipify, kind: .timeout),
                    .init(endpoint: cloudflare, kind: .timeout),
                    .init(endpoint: ident, kind: .timeout),
                ],
                overseasOnly: true
            ),
            .timedOut
        )

        // All hostname endpoints failed DNS while IP literal timed out -> .dnsFailed
        XCTAssertEqual(
            PublicIPWatcher.classifyFailure(
                failures: [
                    .init(endpoint: ipify, kind: .dns),
                    .init(endpoint: cloudflare, kind: .timeout),
                    .init(endpoint: ident, kind: .dns),
                ],
                overseasOnly: true
            ),
            .dnsFailed
        )

        // Connection refused / TLS errors on overseas-only -> .overseasUnreachable
        XCTAssertEqual(
            PublicIPWatcher.classifyFailure(
                failures: [
                    .init(endpoint: ipify, kind: .connection),
                    .init(endpoint: cloudflare, kind: .timeout),
                    .init(endpoint: ident, kind: .tls),
                ],
                overseasOnly: true
            ),
            .overseasUnreachable
        )

        // Direct fallback also failed with connection errors -> .unreachable
        let direct = PublicIPWatcher.endpoints.filter { !$0.overseas }
        XCTAssertEqual(
            PublicIPWatcher.classifyFailure(
                failures: [
                    .init(endpoint: ipify, kind: .connection),
                    .init(endpoint: direct[0], kind: .connection),
                ],
                overseasOnly: false
            ),
            .unreachable
        )
    }

    // MARK: - PublicIPWatcher state machine

    func testProxyNodeHiccupNeverFallsBackToDirectAndReportsFailureAfterThreshold() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.cb")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var requestedURLs: [String] = []

        var updates: [String] = []
        var failures: [PublicIPFailureReason] = []
        var clearedCount = 0

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                requestedURLs.append(endpoint.url.absoluteString)
                if endpoint.overseas {
                    completion(overseasResult)
                } else {
                    // Simulates FlClash rule-mode Direct route returning local China ISP IP.
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }
        watcher.onFailure = { failures.append($0) }
        watcher.onFailureCleared = { clearedCount += 1 }

        // 1. Initial check succeeds over FlClash TUN.
        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])
        XCTAssertTrue(failures.isEmpty)

        // 2. Proxy node stalls (TCP SYN packet loss -> all overseas endpoints time out).
        requestedURLs.removeAll()
        overseasResult = .failure(.timeout)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)

        // Must NOT touch any domestic direct endpoint, must NOT emit fake IP, and 1st failure stays silent.
        XCTAssertTrue(requestedURLs.allSatisfy { !$0.contains("ipip.net") && !$0.contains("oray.com") },
                      "Unexpected domestic fallback on unchanged TUN route: \(requestedURLs)")
        XCTAssertEqual(requestedURLs.count, 3)
        XCTAssertEqual(updates, ["179.253.226.232"])
        XCTAssertTrue(failures.isEmpty)

        // 3. Second consecutive failure surfaces gentle .timedOut status (still no domestic fallback!).
        requestedURLs.removeAll()
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertTrue(requestedURLs.allSatisfy { !$0.contains("ipip.net") && !$0.contains("oray.com") })
        XCTAssertEqual(updates, ["179.253.226.232"])
        XCTAssertEqual(failures, [.timedOut])

        // 4. Third consecutive failure with same reason does not emit duplicate failure callbacks.
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(failures, [.timedOut])

        // 5. Proxy recovers with same exit IP -> updates cleanly with no domestic IP ever reported.
        overseasResult = .success("179.253.226.232")
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232", "179.253.226.232"])
        XCTAssertEqual(clearedCount, 0) // onUpdate itself clears failure state
        watcher.stop()
    }

    func testTurningOffVpnTunnelAllowsDirectFallbackAndDetectsRealIPChange() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let directRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|"
        let callbackQueue = DispatchQueue(label: "test.publicIP.vpnoff")
        var vpnOn = true
        var requestedURLs: [String] = []
        var updates: [String] = []
        var failures: [PublicIPFailureReason] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                requestedURLs.append(endpoint.url.absoluteString)
                if endpoint.overseas {
                    completion(vpnOn ? .success("179.253.226.232") : .failure(.connection))
                } else {
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }
        watcher.onFailure = { failures.append($0) }

        // 1. Start with FlClash TUN ON.
        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])

        // 2. Turn OFF FlClash TUN -> utun5 disappears, route changes, hasProxyOrTunnel becomes false.
        vpnOn = false
        requestedURLs.removeAll()
        watcher.networkChanged(connected: true, route: directRoute, egress: directRoute, hasProxyOrTunnel: false)
        drain(watcher, callbackQueue)

        XCTAssertEqual(updates, ["179.253.226.232", "183.241.150.62"])
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(requestedURLs.contains { $0.contains("ipip.net") })

        // 3. Steady-state direct check uses fast plan: primary overseas + domestic (skips 1.1.1.1 & v4.ident.me).
        requestedURLs.removeAll()
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(requestedURLs, ["https://api.ipify.org", "https://myip.ipip.net/s"])
        XCTAssertEqual(updates, ["179.253.226.232", "183.241.150.62", "183.241.150.62"])
        watcher.stop()
    }

    func testSwitchingProxyNodeDetectsNewOverseasIP() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.node")
        var currentExitIP = "179.253.226.232"
        var updates: [String] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if endpoint.overseas {
                    completion(.success(currentExitIP))
                } else {
                    XCTFail("Direct endpoint should never be queried when overseas succeeds")
                    completion(.failure(.connection))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])

        // Switch node inside FlClash (route stays identical, exit IP changes).
        currentExitIP = "45.76.10.20"
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232", "45.76.10.20"])
        watcher.stop()
    }

    func testTailscaleCoexistenceStillDetectsDirectIPAfterFlClashTurnsOff() {
        let bothTunnels = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun3:100.64.0.1,utun5:198.18.0.1|utun5:198.18.0.1"
        let tailscaleOnly = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun3:100.64.0.1|en0:192.168.3.5"
        let viaFlClash = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let direct = "en0|192.168.3.5|192.168.3.1|0|0|0|0|en0:192.168.3.5"
        let callbackQueue = DispatchQueue(label: "test.publicIP.tailscale")
        var flClashOn = true
        var updates: [String] = []
        var failures: [PublicIPFailureReason] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if endpoint.overseas {
                    completion(flClashOn ? .success("179.253.226.232") : .failure(.connection))
                } else {
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }
        watcher.onFailure = { failures.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: bothTunnels, egress: viaFlClash, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])

        // FlClash turns off while Tailscale utun3 stays active -> public addresses now route over
        // en0, so the way out changed; hasProxyOrTunnel is still true because of utun3.
        flClashOn = false
        watcher.networkChanged(connected: true, route: tailscaleOnly, egress: direct, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        // First pass tries overseas only and stays silent.
        XCTAssertEqual(updates, ["179.253.226.232"])
        XCTAssertTrue(failures.isEmpty)

        // Second pass allows direct fallback -> detects real direct IP cleanly without false failure alert.
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232", "183.241.150.62"])
        XCTAssertTrue(failures.isEmpty)
        watcher.stop()
    }

    func testLoginStartupRaceWithTunnelWaitsOnePassBeforeDirectFallback() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.login")
        var proxyReady = false
        var directCalled = false
        var updates: [String] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if endpoint.overseas {
                    completion(proxyReady ? .success("179.253.226.232") : .failure(.timeout))
                } else {
                    directCalled = true
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }

        // App starts while FlClash TUN exists but node handshake hasn't finished yet.
        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertFalse(directCalled)
        XCTAssertTrue(updates.isEmpty)

        // Proxy finishes connecting -> next probe gets overseas IP as initial baseline (no fake change!).
        proxyReady = true
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertFalse(directCalled)
        XCTAssertEqual(updates, ["179.253.226.232"])
        watcher.stop()
    }

    func testReconnectOnSameTunnelRouteKeepsDirectFallbackBlocked() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.reconnect")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var directCalled = false
        var clearedCount = 0

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if endpoint.overseas {
                    completion(overseasResult)
                } else {
                    directCalled = true
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onFailureCleared = { clearedCount += 1 }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)

        // Trigger a reported failure first, then disconnect -> failure clears.
        overseasResult = .failure(.timeout)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)

        watcher.networkChanged(connected: false, route: "", egress: "", hasProxyOrTunnel: false)
        drain(watcher, callbackQueue)
        XCTAssertEqual(clearedCount, 1)

        // Reconnect on the exact same TUN route while proxy is still re-establishing -> must NOT hit direct.
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertFalse(directCalled)
        watcher.stop()
    }

    func testDirectStartupFallsBackImmediatelyWithoutTunnel() {
        let directRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|"
        let callbackQueue = DispatchQueue(label: "test.publicIP.direct")
        var updates: [String] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if endpoint.overseas {
                    completion(.failure(.connection))
                } else {
                    completion(.success("183.241.150.62"))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: directRoute, egress: directRoute, hasProxyOrTunnel: false)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["183.241.150.62"])
        watcher.stop()
    }

    func testDNSFailureReportsDNSReasonAfterConsecutiveFailures() {
        let tunRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.dns")
        var failDNS = false
        var failures: [PublicIPFailureReason] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                if !failDNS {
                    completion(.success("179.253.226.232"))
                } else if endpoint.isIPLiteralHost {
                    completion(.failure(.timeout))
                } else {
                    completion(.failure(.dns))
                }
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onFailure = { failures.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: tunRoute, egress: tunRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)

        failDNS = true
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertTrue(failures.isEmpty)

        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(failures, [.dnsFailed])
        watcher.stop()
    }

    func testCompanionTunnelReconnectDuringOverseasTimeoutNeverFallsBackToDirect() {
        // FlClash's TUN (utun5) carries public traffic throughout; Tailscale (utun3) drops and
        // comes back, which changes the route key but not the way out.
        let viaFlClash = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let both = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun3:100.64.0.1,utun5:198.18.0.1|utun5:198.18.0.1"
        let tailscaleDown = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1|utun5:198.18.0.1"
        let tailscaleBack = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun3:100.64.0.1,utun5:198.18.0.1|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.companion")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var requestedURLs: [String] = []
        var updates: [String] = []

        let watcher = PublicIPWatcher(
            fetcher: { endpoint, completion in
                requestedURLs.append(endpoint.url.absoluteString)
                completion(endpoint.overseas ? overseasResult : .success("183.241.150.62"))
                return {}
            },
            callbackQueue: callbackQueue,
            enableTimer: false
        )
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: both, egress: viaFlClash, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232"])

        // Tailscale reconnects while the proxy's checks time out: a fresh check runs on each
        // route change, and the retries after it, but none of them may go direct.
        overseasResult = .failure(.timeout)
        requestedURLs.removeAll()
        watcher.networkChanged(connected: true, route: tailscaleDown, egress: viaFlClash, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        watcher.networkChanged(connected: true, route: tailscaleBack, egress: viaFlClash, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertFalse(requestedURLs.isEmpty)
        XCTAssertTrue(requestedURLs.allSatisfy { !$0.contains("ipip.net") && !$0.contains("oray.com") },
                      "Direct fallback while the way out stayed the same: \(requestedURLs)")
        XCTAssertEqual(updates, ["179.253.226.232"])

        // The proxy answers again with the same exit IP: no change was ever reported.
        overseasResult = .success("179.253.226.232")
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(updates, ["179.253.226.232", "179.253.226.232"])
        watcher.stop()
    }

    // MARK: - Delivery after the state moved on

    func testResultWaitingOnCallbackQueueIsDeliveredWhileStillCurrent() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.deliver.current")
        var updates: [String] = []
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(.success("179.253.226.232")); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        callbackQueue.suspend()
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        watcher.flushForTesting(includingCallbacks: false)
        callbackQueue.resume()
        watcher.flushForTesting()
        XCTAssertEqual(updates, ["179.253.226.232"])
        watcher.stop()
    }

    func testResultWaitingOnCallbackQueueIsDroppedAfterDisconnect() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.deliver.disconnect")
        var updates: [String] = []
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(.success("179.253.226.232")); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        callbackQueue.suspend()
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        watcher.flushForTesting(includingCallbacks: false) // the result now waits on the held queue
        watcher.networkChanged(connected: false, route: "", egress: "", hasProxyOrTunnel: false)
        watcher.flushForTesting(includingCallbacks: false)
        callbackQueue.resume()
        watcher.flushForTesting()
        XCTAssertTrue(updates.isEmpty, "A result from before the disconnect was delivered: \(updates)")
        watcher.stop()
    }

    func testResultWaitingOnCallbackQueueIsDroppedAfterStop() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.deliver.stop")
        var updates: [String] = []
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(.success("179.253.226.232")); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        callbackQueue.suspend()
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        watcher.flushForTesting(includingCallbacks: false)
        watcher.stop()
        callbackQueue.resume()
        watcher.flushForTesting()
        XCTAssertTrue(updates.isEmpty, "A result from before stop() was delivered: \(updates)")
    }

    func testFailureWaitingOnCallbackQueueIsDroppedAfterRouteChange() {
        let oldRoute = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let newRoute = "en0|10.0.0.8|10.0.0.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.deliver.route")
        var failures: [PublicIPFailureReason] = []
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(.failure(.timeout)); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onFailure = { failures.append($0) }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: oldRoute, egress: oldRoute, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue) // first failure stays quiet

        callbackQueue.suspend()
        watcher.probeNow(force: true)
        watcher.flushForTesting(includingCallbacks: false) // second failure now waits on the held queue
        watcher.networkChanged(connected: true, route: newRoute, egress: newRoute, hasProxyOrTunnel: true)
        watcher.flushForTesting(includingCallbacks: false)
        callbackQueue.resume()
        watcher.flushForTesting()
        XCTAssertTrue(failures.isEmpty, "A failure from the old route was delivered: \(failures)")
        watcher.stop()
    }

    func testShownFailureIsClearedEvenWhenTheSuccessAfterItWasDropped() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.clearAfterDrop")
        var overseasResult: PublicIPWatcher.ProbeAttemptResult = .success("179.253.226.232")
        var updates: [String] = []
        var failures: [PublicIPFailureReason] = []
        var cleared = 0
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(overseasResult); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }
        watcher.onFailure = { failures.append($0) }
        watcher.onFailureCleared = { cleared += 1 }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        overseasResult = .failure(.timeout)
        for _ in 0..<2 {
            watcher.probeNow(force: true)
            drain(watcher, callbackQueue)
        }
        XCTAssertEqual(failures, [.timedOut]) // shown: Alerts has a failure episode open

        // A check succeeds, but before its result runs the Mac disconnects: the result is
        // dropped, so the failure must still be closed by a clear.
        overseasResult = .success("179.253.226.232")
        callbackQueue.suspend()
        watcher.probeNow(force: true)
        watcher.flushForTesting(includingCallbacks: false)
        watcher.networkChanged(connected: false, route: "", egress: "", hasProxyOrTunnel: false)
        watcher.flushForTesting(includingCallbacks: false)
        callbackQueue.resume()
        watcher.flushForTesting()
        XCTAssertEqual(updates, ["179.253.226.232"])
        XCTAssertEqual(cleared, 1)
        watcher.stop()
    }

    func testStopClearsAShownFailure() {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.stopClears")
        var failures: [PublicIPFailureReason] = []
        var cleared = 0
        let watcher = PublicIPWatcher(fetcher: { _, completion in completion(.failure(.timeout)); return {} },
                                      callbackQueue: callbackQueue, enableTimer: false)
        watcher.onFailure = { failures.append($0) }
        watcher.onFailureCleared = { cleared += 1 }

        watcher.configure(active: true, interval: 5)
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        drain(watcher, callbackQueue)
        watcher.probeNow(force: true)
        drain(watcher, callbackQueue)
        XCTAssertEqual(failures, [.timedOut])

        watcher.stop()
        callbackQueue.sync {}
        XCTAssertEqual(cleared, 1)
    }

    /// The watcher's queue is held busy (a check stuck in its fetcher) while the caller reports
    /// the change, so only an invalidation made on the caller's thread can stop a result that is
    /// already waiting on `callbackQueue`.
    private func assertWaitingResultDroppedBeforeQueueCatchesUp(_ change: (PublicIPWatcher) -> Void,
                                                               file: StaticString = #filePath, line: UInt = #line) {
        let route = "en0|192.168.3.5|192.168.3.1|0|0|0|0|utun5:198.18.0.1"
        let callbackQueue = DispatchQueue(label: "test.publicIP.syncInvalidate")
        let release = DispatchSemaphore(value: 0)
        var holdNext = false
        var updates: [String] = []
        let watcher = PublicIPWatcher(
            fetcher: { _, completion in
                if holdNext { release.wait() }
                completion(.success("179.253.226.232"))
                return {}
            },
            callbackQueue: callbackQueue, enableTimer: false)
        watcher.onUpdate = { updates.append($0) }

        watcher.configure(active: true, interval: 5)
        callbackQueue.suspend()
        watcher.networkChanged(connected: true, route: route, egress: route, hasProxyOrTunnel: true)
        watcher.flushForTesting(includingCallbacks: false) // the result waits on the held queue
        holdNext = true
        watcher.probeNow(force: true)                       // the watcher's queue is now stuck
        change(watcher)                                     // queued behind it
        callbackQueue.resume()
        callbackQueue.sync {}
        XCTAssertTrue(updates.isEmpty, "A stale result ran before the watcher caught up: \(updates)", file: file, line: line)
        holdNext = false
        release.signal()
        watcher.flushForTesting()
        watcher.stop()
    }

    func testWaitingResultIsDroppedOnDisconnectBeforeTheWatcherQueueCatchesUp() {
        assertWaitingResultDroppedBeforeQueueCatchesUp { $0.networkChanged(connected: false, route: "", egress: "", hasProxyOrTunnel: false) }
    }

    func testWaitingResultIsDroppedOnANewWayOutBeforeTheWatcherQueueCatchesUp() {
        let direct = "en0|192.168.3.5|192.168.3.1|0|0|0|0|en0:192.168.3.5"
        assertWaitingResultDroppedBeforeQueueCatchesUp { $0.networkChanged(connected: true, route: direct, egress: direct, hasProxyOrTunnel: false) }
    }

    func testWaitingResultIsDroppedWhenChecksTurnOffBeforeTheWatcherQueueCatchesUp() {
        assertWaitingResultDroppedBeforeQueueCatchesUp { $0.configure(active: false, interval: 5) }
    }

    // MARK: - Alerts integration & backwards compatibility

    func testAlertsProbeFailureCooldownRecoveryAndRealIPChange() {
        let savedPrefs = SettingsStore.shared.prefs
        defer { SettingsStore.shared.prefs = savedPrefs }

        SettingsStore.shared.prefs.alerts.enabled = true
        SettingsStore.shared.prefs.alerts.publicIPOn = true
        SettingsStore.shared.prefs.setEnabled(.network, true)

        var notified: [AlertEvent] = []
        Alerts.shared.deliverNotification = { event, _ in notified.append(event) }

        // 1. Baseline IP -> no alert.
        Alerts.shared.publicIPUpdated("179.253.226.232")
        XCTAssertTrue(notified.isEmpty)
        XCTAssertTrue(Alerts.shared.events.isEmpty)

        // 2. Sustained failure -> posts ONE calm probe-failure alert, NOT angry overview banner.
        let t0 = Date()
        Alerts.shared.publicIPCheckFailed(.timedOut, at: t0)
        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(notified[0].probeFailure, .timedOut)
        XCTAssertEqual(notified[0].previousSubject, "179.253.226.232")
        XCTAssertNil(notified[0].subject)
        XCTAssertNil(notified[0].ended)
        XCTAssertNil(Alerts.shared.current, "Probe failure should not trigger Rin's angry overview banner")
        XCTAssertNotEqual(AlertText.banner(notified[0]), L10n.Alerts.publicIPBanner)

        // 3. Repeated failure in same episode -> no duplicate notification.
        Alerts.shared.publicIPCheckFailed(.overseasUnreachable, at: t0.addingTimeInterval(10))
        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(Alerts.shared.events.first?.probeFailure, .overseasUnreachable)

        // 4. Recovery with same IP -> closes failure episode, NO fake IP-change notification!
        Alerts.shared.publicIPUpdated("179.253.226.232")
        XCTAssertEqual(notified.count, 1)
        XCTAssertNotNil(Alerts.shared.events.first?.ended)
        XCTAssertEqual(Alerts.shared.events.first?.endValue, AlertEvent.publicIPConfirmedRecovery)
        XCTAssertEqual(AlertText.detail(Alerts.shared.events[0]), L10n.Alerts.recovered)

        // 5. Another failure within 10-minute cooldown stays quiet.
        Alerts.shared.publicIPCheckFailed(.timedOut, at: t0.addingTimeInterval(120))
        XCTAssertEqual(notified.count, 1)

        // 6. Real IP change still fires immediately even during failure cooldown!
        Alerts.shared.publicIPUpdated("183.241.150.62")
        XCTAssertEqual(notified.count, 2)
        XCTAssertNil(notified[1].probeFailure)
        XCTAssertEqual(notified[1].previousSubject, "179.253.226.232")
        XCTAssertEqual(notified[1].subject, "183.241.150.62")
    }

    func testProbeFailureEndedWithoutASuccessfulCheckIsNotShownAsRecovered() {
        let savedPrefs = SettingsStore.shared.prefs
        defer { SettingsStore.shared.prefs = savedPrefs }
        SettingsStore.shared.prefs.alerts.enabled = true
        SettingsStore.shared.prefs.alerts.publicIPOn = true
        SettingsStore.shared.prefs.setEnabled(.network, true)
        Alerts.shared.deliverNotification = { _, _ in }

        Alerts.shared.publicIPUpdated("179.253.226.232")
        let t0 = Date()

        // Disconnect or route change: the watcher clears the failure, no check got through.
        Alerts.shared.publicIPCheckFailed(.timedOut, at: t0)
        Alerts.shared.publicIPFailureCleared(at: t0.addingTimeInterval(30))
        var event = Alerts.shared.events[0]
        XCTAssertNotNil(event.ended)
        XCTAssertNil(event.endValue)
        XCTAssertFalse(event.publicIPRecoveryConfirmed)
        XCTAssertEqual(AlertText.detail(event), L10n.Alerts.publicIPLastConfirmed("179.253.226.232"))

        // Checks turned off while failing (past the cooldown, so this is a new episode).
        Alerts.shared.publicIPCheckFailed(.dnsFailed, at: t0.addingTimeInterval(700))
        XCTAssertEqual(Alerts.shared.events.count, 2)
        Alerts.shared.resetPublicIP()
        event = Alerts.shared.events[0]
        XCTAssertEqual(event.probeFailure, .dnsFailed)
        XCTAssertNotNil(event.ended)
        XCTAssertFalse(event.publicIPRecoveryConfirmed)
        XCTAssertNotEqual(AlertText.detail(event), L10n.Alerts.recovered)
    }

    func testLegacyProbeFailureWithoutEndValueIsNotShownAsRecovered() throws {
        // Closed by a restart (load() fills `ended`) or saved before `endValue` meant recovery.
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "rule": "publicIP",
          "date": 785000000,
          "value": 1,
          "limit": 0,
          "held": 0,
          "previousSubject": "179.253.226.232",
          "probeFailure": 1,
          "ended": 785000300,
          "seen": false
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(AlertEvent.self, from: json)
        XCTAssertEqual(event.probeFailure, .timedOut)
        XCTAssertFalse(event.publicIPRecoveryConfirmed)
        XCTAssertEqual(AlertText.detail(event), L10n.Alerts.publicIPLastConfirmed("179.253.226.232"))

        var confirmed = event
        confirmed.endValue = AlertEvent.publicIPConfirmedRecovery
        let roundTrip = try JSONDecoder().decode(AlertEvent.self, from: JSONEncoder().encode(confirmed))
        XCTAssertTrue(roundTrip.publicIPRecoveryConfirmed)
        XCTAssertEqual(AlertText.detail(roundTrip), L10n.Alerts.recovered)
    }

    func testAlertEventCodableBackwardsCompatibility() throws {
        // Legacy 0.6.6 alerts.json event without `probeFailure`.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "rule": "publicIP",
          "date": 785000000,
          "value": 0,
          "limit": 0,
          "held": 0,
          "subject": "183.241.150.62",
          "previousSubject": "179.253.226.232",
          "ended": 785000000,
          "seen": true
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(AlertEvent.self, from: legacyJSON)
        XCTAssertEqual(decodedLegacy.rule, .publicIP)
        XCTAssertEqual(decodedLegacy.subject, "183.241.150.62")
        XCTAssertEqual(decodedLegacy.previousSubject, "179.253.226.232")
        XCTAssertNil(decodedLegacy.probeFailure)
        XCTAssertFalse(decodedLegacy.publicIPRecoveryConfirmed)
        XCTAssertEqual(AlertText.detail(decodedLegacy), L10n.Alerts.publicIPDetail("179.253.226.232"))

        // New probeFailure event round-trips cleanly.
        let failureEvent = AlertEvent(rule: .publicIP, date: Date(), value: 1, limit: 0,
                                      previousSubject: "179.253.226.232", probeFailure: .dnsFailed)
        let data = try JSONEncoder().encode(failureEvent)
        let decodedFailure = try JSONDecoder().decode(AlertEvent.self, from: data)
        XCTAssertEqual(decodedFailure.probeFailure, .dnsFailed)
        XCTAssertEqual(decodedFailure.previousSubject, "179.253.226.232")
    }

    func testAlertTextCopyForAllFailureReasons() {
        for reason in [PublicIPFailureReason.timedOut, .dnsFailed, .overseasUnreachable, .unreachable] {
            let event = AlertEvent(rule: .publicIP, date: Date(), value: Double(reason.rawValue), limit: 0,
                                   previousSubject: "179.253.226.232", probeFailure: reason)
            XCTAssertFalse(AlertText.headline(event).isEmpty)
            XCTAssertFalse(AlertText.banner(event).isEmpty)
            XCTAssertFalse(AlertText.notificationBody(event).isEmpty)
            XCTAssertFalse(AlertText.publicIPFailureStatus(reason).isEmpty)
            XCTAssertNotEqual(AlertText.banner(event), L10n.Alerts.publicIPBanner)
            XCTAssertNotNil(AlertText.detail(event))
        }
    }

    // MARK: - Helpers

    /// Flushes both the watcher's internal serial queue and the test callback queue deterministically.
    private func drain(_ watcher: PublicIPWatcher, _ callbackQueue: DispatchQueue) {
        watcher.flushForTesting()
    }
}
