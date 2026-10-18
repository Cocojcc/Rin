import AppKit
import Foundation
import Observation
import UserNotifications

/// Evaluates the alert rules after every sample, colors the menu bar and posts notifications
/// that name the process behind the problem. A rule fires once per episode, at most every 10 minutes.
@Observable
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    enum Rule: String, CaseIterable {
        case cpu, gpu, memory, disk, battery, temperature, network

        var module: Module {
            switch self {
            case .cpu: return .cpu
            case .gpu: return .gpu
            case .memory: return .memory
            case .disk: return .disk
            case .battery: return .battery
            case .temperature: return .sensors
            case .network: return .network
            }
        }
    }

    private(set) var active: [Module: BarTone] = [:]

    @ObservationIgnored private var since: [Rule: Date] = [:]
    @ObservationIgnored private var firedEpisode: Set<Rule> = []
    @ObservationIgnored private var lastFired: [Rule: Date] = [:]
    @ObservationIgnored private var authorized = false
    @ObservationIgnored private var askedAuthorization = false
    @ObservationIgnored private var everConnected = false

    private static let cooldown: TimeInterval = 600
    private static let quitAction = "quit"
    private static let category = "hum.process"

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let quit = UNNotificationAction(identifier: Self.quitAction, title: L10n.Alerts.quitAction, options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [quit], intentIdentifiers: [])])
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard !askedAuthorization else { return }
        askedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.authorized = granted }
        }
    }

    func evaluate() {
        let prefs = SettingsStore.shared.prefs
        let a = prefs.alerts
        let s = Monitor.shared.snapshot
        guard a.enabled else {
            if !active.isEmpty { active = [:] }
            since = [:]
            firedEpisode = []
            return
        }
        requestAuthorizationIfNeeded()
        let now = s.date
        var next: [Module: BarTone] = [:]

        func check(_ rule: Rule, enabled: Bool, condition: Bool, after: TimeInterval, tone: BarTone, notify: () -> (String, String, ProcessUsage?)) {
            guard enabled, condition else {
                since[rule] = nil
                firedEpisode.remove(rule)
                return
            }
            let start = since[rule] ?? now
            since[rule] = start
            guard now.timeIntervalSince(start) >= after else { return }
            next[rule.module] = tone
            guard !firedEpisode.contains(rule) else { return }
            firedEpisode.insert(rule)
            if let last = lastFired[rule], now.timeIntervalSince(last) < Self.cooldown { return }
            lastFired[rule] = now
            let (title, body, process) = notify()
            post(rule, title: title, body: body, process: process, sound: a.sound)
        }

        let top = s.processes.byCPU.first
        check(.cpu, enabled: a.cpuOn, condition: s.cpu.total * 100 >= a.cpuThreshold, after: a.cpuMinutes * 60, tone: .warn) {
            let culprit = top.map { L10n.Alerts.cpuCulprit($0.name, Format.percentValue($0.cpu)) } ?? ""
            return (L10n.Alerts.cpuTitle, L10n.Alerts.cpuBody(Format.percent(s.cpu.total), Self.minutes(a.cpuMinutes)) + culprit, top?.isSystem == false ? top : nil)
        }

        // Per-process GPU usage is only read while a GPU view is open, so the culprit may be missing.
        let gpuTop = s.processes.byGPU.first
        check(.gpu, enabled: a.gpuOn, condition: s.gpu.utilization * 100 >= a.gpuThreshold, after: a.gpuMinutes * 60, tone: .warn) {
            let culprit = gpuTop.map { L10n.Alerts.gpuCulprit($0.name, Format.percentValue($0.gpu)) } ?? ""
            return (L10n.Alerts.gpuTitle, L10n.Alerts.gpuBody(Format.percent(s.gpu.utilization), Self.minutes(a.gpuMinutes)) + culprit, gpuTop?.isSystem == false ? gpuTop : nil)
        }

        let memTop = s.processes.byMemory.first
        check(.memory, enabled: a.memoryOn, condition: s.memory.pressure.rawValue >= a.memoryLevel.rawValue, after: 10, tone: a.memoryLevel == .critical ? .crit : .warn) {
            let culprit = memTop.map { L10n.Alerts.memoryCulprit($0.name, Format.memory($0.memory)) } ?? ""
            return (L10n.Alerts.memoryTitle, L10n.Alerts.memoryBody + culprit, memTop?.isSystem == false ? memTop : nil)
        }

        let root = s.disk.root
        check(.disk, enabled: a.diskOn, condition: root.map { Double($0.available) < a.diskFreeGB * 1_000_000_000 } ?? false, after: 0, tone: .warn) {
            (L10n.Alerts.diskTitle, L10n.Alerts.diskBody(root?.name ?? "", Format.storage(root?.available ?? 0)), nil)
        }

        check(.battery, enabled: a.batteryOn && s.battery.hasBattery, condition: s.battery.level * 100 <= a.batteryPercent && !s.battery.onAC, after: 0, tone: .crit) {
            (L10n.Alerts.batteryTitle, L10n.Alerts.batteryBody(Format.percent(s.battery.level)), nil)
        }

        let temp = s.sensors.cpuAverage ?? 0
        check(.temperature, enabled: a.tempOn, condition: temp >= a.tempThreshold, after: 10, tone: .crit) {
            (L10n.Alerts.tempTitle, L10n.Alerts.tempBody(Format.temperature(temp, unit: prefs.general.temperatureUnit, showUnit: true)) +
                (top.map { L10n.Alerts.cpuCulprit($0.name, Format.percentValue($0.cpu)) } ?? ""), top?.isSystem == false ? top : nil)
        }

        // Network: only counts after the Mac has been online during this session.
        let connected = s.network.connected
        if connected { everConnected = true }
        check(.network, enabled: a.networkOn, condition: !connected && everConnected, after: 5, tone: .dim) {
            (L10n.Alerts.networkTitle, L10n.Alerts.networkBody, nil)
        }

        if next != active { active = next }
    }

    private static func minutes(_ m: Double) -> String {
        m < 1 ? L10n.Alerts.seconds(Int(m * 60)) : L10n.Alerts.minutes(Int(m))
    }

    private func post(_ rule: Rule, title: String, body: String, process: ProcessUsage?, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        content.userInfo = ["rule": rule.rawValue]
        if let process {
            content.categoryIdentifier = Self.category
            content.userInfo["pid"] = Int(process.pid)
            content.userInfo["name"] = process.name
        }
        let request = UNNotificationRequest(identifier: "hum.\(rule.rawValue).\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            if response.actionIdentifier == Self.quitAction, let pid = info["pid"] as? Int {
                _ = ProcessActions.quit(pid: pid_t(pid))
            } else if let raw = info["rule"] as? String, let rule = Rule(rawValue: raw) {
                MainWindowController.shared.show(Page.monitor(rule.module))
            }
            completionHandler()
        }
    }
}
