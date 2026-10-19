import AppKit
import Foundation
import Observation

/// Something on screen that needs extra (more expensive) data while it is visible.
enum Consumer: Hashable {
    case popover(Module)
    case combinedPanel
    case window(Page)
}

/// The app's live state. Readers run on a background queue; results land here on the main thread.
@Observable
final class Monitor {
    static let shared = Monitor()

    private(set) var snapshot = Snapshot()
    private(set) var tick = 0
    private(set) var publicIP: String?
    private(set) var interfaces: [(name: String, kind: InterfaceKind)] = []
    /// Sampling stopped from the sidebar's pause button; everything keeps its last values.
    private(set) var isPaused = false
    /// The screen is off or locked, or another user's session is in front: nobody sees the menu
    /// bar or a window, so only what alert rules need is read, slowly.
    private(set) var isResting = false

    @ObservationIgnored let history = History()
    /// Recent CPU and memory per process group, for the Processes page's inspector sparklines.
    @ObservationIgnored private(set) var processHistory: [String: [ProcessPoint]] = [:]
    @ObservationIgnored private var processHistoryDate = Date.distantPast
    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var consumers: Set<Consumer> = []
    @ObservationIgnored private var lastPublicIP = Date.distantPast
    @ObservationIgnored var onSample: ((Snapshot) -> Void)?

    enum RestReason { case displaysAsleep, locked, sessionInactive }
    @ObservationIgnored private var restReasons: Set<RestReason> = []

    private init() {}

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.sampler.volumesChanged() }
        }
        let restEvents: [(NotificationCenter, String, RestReason, Bool)] = [
            (center, NSWorkspace.screensDidSleepNotification.rawValue, .displaysAsleep, true),
            (center, NSWorkspace.screensDidWakeNotification.rawValue, .displaysAsleep, false),
            (center, NSWorkspace.sessionDidResignActiveNotification.rawValue, .sessionInactive, true),
            (center, NSWorkspace.sessionDidBecomeActiveNotification.rawValue, .sessionInactive, false),
            (DistributedNotificationCenter.default(), "com.apple.screenIsLocked", .locked, true),
            (DistributedNotificationCenter.default(), "com.apple.screenIsUnlocked", .locked, false),
        ]
        for (nc, name, reason, on) in restEvents {
            nc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.setRest(reason, on) }
        }
        sampler.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
        applyConfiguration()
        sampler.start()
    }

    func stop() {
        sampler.stop()
        history.save()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { sampler.pause() } else { sampler.resume() }
    }

    func setRest(_ reason: RestReason, _ on: Bool) {
        if on { restReasons.insert(reason) } else { restReasons.remove(reason) }
        let resting = !restReasons.isEmpty
        guard resting != isResting else { return }
        isResting = resting
        applyConfiguration()
        // Back in front: read everything at once rather than waiting for the next tick.
        if !resting { sampler.sampleNow() }
    }

    func setVisible(_ consumer: Consumer, _ visible: Bool) {
        let changed = visible ? consumers.insert(consumer).inserted : consumers.remove(consumer) != nil
        if changed {
            applyConfiguration()
            if visible { sampler.sampleNow() }
        }
    }

    /// Re-read settings and visibility into the sampler (interval, extra sources).
    func applyConfiguration() {
        let prefs = SettingsStore.shared.prefs
        var config = Sampler.Config()
        config.slowOnBattery = prefs.general.slowOnBattery
        config.interface = prefs.network.interface
        if isResting {
            // Only the modules alert rules watch, every 15 s or slower; processes every 30 s for
            // the culprit names; no per-app traffic, frequencies or latency pings.
            config.monitored = prefs.alertedModules
            for m in Module.allCases { config.intervals[m] = max(prefs.refresh(m), Self.restInterval) }
            config.processInterval = Self.restProcessInterval
            config.processes.limit = 8
            sampler.configure(config)
            return
        }
        // A module is read only while something uses it: its menu bar item, an alert rule, or a
        // view showing it. The overview and the combined panel show the whole machine.
        var shown = Set(Module.allCases.filter(prefs.showsInMenubar))
        for consumer in consumers {
            switch consumer {
            case .popover(let m), .window(.monitor(let m)), .window(.moduleSettings(let m)): shown.insert(m)
            case .combinedPanel, .window(.overview): shown = Set(Module.allCases)
            default: break
            }
        }
        shown = shown.filter(prefs.isEnabled)
        var read = shown.union(prefs.alertedModules)
        let allProcesses = consumers.contains(.window(.processes))
        let batteryPage = consumers.contains(.window(.monitor(.battery)))
        // The battery page's "整机" figure comes from the SMC on Macs without a battery.
        if batteryPage && prefs.isEnabled(.sensors) { read.insert(.sensors) }
        config.monitored = read
        config.processesWanted = allProcesses || batteryPage
        config.processes.full = allProcesses
        // A module read only for an alert rule needs no more than a reading every few seconds;
        // the rules wait 30 s or more before firing anyway.
        for m in Module.allCases {
            config.intervals[m] = shown.contains(m) ? prefs.refresh(m) : max(prefs.refresh(m), Self.alertOnlyInterval)
        }
        let anyUI = !consumers.isEmpty
        // With nothing open, processes are only needed for the CPU peaks' names and alert
        // culprits, which a slower scan serves as well.
        config.processInterval = anyUI ? min(prefs.cpu.processRefresh, prefs.memory.processRefresh) : Self.backgroundProcessInterval
        config.cpuFrequency = consumers.contains(.window(.monitor(.cpu)))
        config.latency = prefs.network.showLatency
        config.processes.includeOtherUsers = anyUI
        // Per-app traffic is a difference between two nettop reads (a subprocess, about 15 ms of
        // CPU each). While the network is read a slow baseline is kept, so a list that opens has
        // rates from its first read; nettop runs every process read only while one is on screen.
        config.processes.network = config.monitored.contains(.network) || allProcesses
        config.processes.networkLive = allProcesses || consumers.contains(.popover(.network)) || consumers.contains(.window(.monitor(.network)))
            || consumers.contains(.window(.overview)) || consumers.contains(.combinedPanel)
        config.processes.gpu = allProcesses || config.monitored.contains(.gpu)
            && (consumers.contains(.popover(.gpu)) || consumers.contains(.window(.monitor(.gpu))))
        config.processes.limit = max(8, prefs.cpu.processCount, prefs.memory.processCount, prefs.gpu.processCount)
        sampler.configure(config)

        if consumers.contains(.window(.monitor(.network))) || consumers.contains(.popover(.network)) {
            interfaces = sampler.interfaces()
        }
    }

    /// Seconds between reads of a module that only an alert rule needs.
    private static let alertOnlyInterval: Double = 5
    /// Seconds between process scans while no window or dropdown is open.
    private static let backgroundProcessInterval: Double = 10
    /// Seconds between reads, and between process scans, while the screen is off or locked.
    private static let restInterval: Double = 15
    private static let restProcessInterval: Double = 30

    private func apply(_ s: Snapshot) {
        snapshot = s
        history.record(s)
        recordProcesses(s.processes)
        tick &+= 1
        onSample?(s)
        refreshPublicIPIfNeeded()
    }

    private func recordProcesses(_ p: ProcessSnapshot) {
        guard !p.all.isEmpty else {
            if !processHistory.isEmpty { processHistory = [:] }
            return
        }
        guard p.date != processHistoryDate else { return }
        processHistoryDate = p.date
        var next: [String: [ProcessPoint]] = [:]
        next.reserveCapacity(p.all.count)
        for row in p.all {
            var points = processHistory[row.id] ?? []
            points.append(ProcessPoint(cpu: row.cpu, memory: Double(row.memory)))
            if points.count > ProcessPoint.kept { points.removeFirst(points.count - ProcessPoint.kept) }
            next[row.id] = points
        }
        processHistory = next
    }

    private func refreshPublicIPIfNeeded() {
        guard SettingsStore.shared.prefs.network.showPublicIP, snapshot.network.connected,
              Date().timeIntervalSince(lastPublicIP) > 600,
              let url = URL(string: "https://api.ipify.org") else { return }
        lastPublicIP = Date()
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty, ip.count < 64 else { return }
            DispatchQueue.main.async { self?.publicIP = ip }
        }.resume()
    }
}

/// Owns the readers and drives them from a timer on its own serial queue.
final class Sampler {
    struct Config {
        /// Modules read: in the menu bar, watched by an alert, or on screen.
        var monitored: Set<Module> = Set(Module.allCases)
        /// Seconds between reads per module; the timer ticks at the shortest of them.
        var intervals: [Module: Double] = [:]
        var processInterval: Double = 3
        var latency = false
        var slowOnBattery = true
        var interface = ""
        var processes = ProcessReader.Request()
        /// Read processes even when no process-listing module is read (Processes and battery pages).
        var processesWanted = false
        /// CPU cluster frequencies (IOReport), only shown on the CPU page.
        var cpuFrequency = false
    }

    var onSnapshot: ((Snapshot) -> Void)?

    private let queue = DispatchQueue(label: "hum.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config = Config()
    private var currentInterval: Double = 0
    private var onBattery = false
    private var lastProcesses: (ProcessSnapshot, [PeakProcess])?
    private var lastProcessRead = Date.distantPast
    /// Read processes on the next sample whatever the interval.
    private var processesDue = false
    private var lastRead: [Module: Date] = [:]
    private var lastPower = PowerReport.Reading()
    private var current = Snapshot()

    // Readers are created on the queue and only touched there.
    private lazy var cpu = CPUReader()
    private lazy var memory = MemoryReader()
    private lazy var network = NetworkReader()
    private lazy var disk = DiskReader()
    private lazy var battery = BatteryReader()
    private lazy var bluetooth = BluetoothReader()
    private lazy var sensors = SensorsReader()
    private lazy var power = PowerReport()
    private lazy var gpu = GPUReader()
    private lazy var processes = ProcessReader()

    func configure(_ config: Config) {
        queue.async {
            let old = self.config.processes
            let oldWanted = self.config.processesWanted
            self.config = config
            self.reschedule()
            // Per-app traffic and GPU time are rates between two reads, and the first read after
            // they switch on only sets the baseline. Read again a second later rather than after
            // the full process interval, so a list that just opened fills in at once.
            if (config.processes.network && !old.network) || (config.processes.gpu && !old.gpu)
                || (config.processes.networkLive && !old.networkLive)
                || (config.processes.full && !old.full) || (config.processesWanted && !oldWanted) {
                self.queue.asyncAfter(deadline: .now() + 1) {
                    guard !self.paused else { return }
                    self.processesDue = true
                    self.sample()
                }
            }
        }
    }

    func start() {
        queue.async {
            self.sample()
            self.reschedule()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    /// An immediate full read, e.g. when a dropdown opens.
    func sampleNow() {
        queue.async { if !self.paused { self.sample(force: true) } }
    }

    private var paused = false

    func pause() {
        queue.async {
            self.paused = true
            self.timer?.cancel()
            self.timer = nil
        }
    }

    func resume() {
        queue.async {
            self.paused = false
            self.currentInterval = 0
            self.sample(force: true)
            self.reschedule()
        }
    }

    func volumesChanged() {
        queue.async {
            self.disk.invalidateVolumes()
            self.sample(force: true)
        }
    }

    func interfaces() -> [(name: String, kind: InterfaceKind)] {
        queue.sync { network.availableInterfaces() }
    }

    private var slowFactor: Double { config.slowOnBattery && onBattery ? 2 : 1 }

    private func interval(_ m: Module) -> Double { (config.intervals[m] ?? 2) * slowFactor }

    private func reschedule() {
        guard !paused else { return }
        let active = Module.allCases.filter(config.monitored.contains)
        let interval = (active.isEmpty ? 10 : active.map(interval).min() ?? 2)
        guard interval != currentInterval || timer == nil else { return }
        currentInterval = interval
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    /// Whether a module's interval has elapsed (with a little slack for timer jitter). Modules
    /// switched off are never due.
    private func due(_ m: Module, _ now: Date, force: Bool) -> Bool {
        guard config.monitored.contains(m) else { lastRead[m] = nil; return false }
        guard !force, let last = lastRead[m] else { lastRead[m] = now; return true }
        guard now.timeIntervalSince(last) >= interval(m) - 0.25 else { return false }
        lastRead[m] = now
        return true
    }

    private func sample(force: Bool = false) {
        let now = Date()
        var s = current
        s.date = now
        s.monitored = config.monitored
        // A module switched off keeps no stale numbers around.
        if !config.monitored.contains(.cpu) { s.cpu = CPUSample() }
        if !config.monitored.contains(.memory) { s.memory = MemorySample() }
        if !config.monitored.contains(.network) { s.network = NetworkSample() }
        if !config.monitored.contains(.disk) { s.disk = DiskSample() }
        if !config.monitored.contains(.battery) { s.battery = BatterySample() }
        if !config.monitored.contains(.sensors) { s.sensors = SensorsSample() }
        if !config.monitored.contains(.bluetooth) { s.bluetooth = BluetoothSample() }
        if !config.monitored.contains(.gpu) { s.gpu = GPUSample() }
        if due(.cpu, now, force: force) { s.cpu = cpu.read() }
        if due(.memory, now, force: force) { s.memory = memory.read() }
        if due(.network, now, force: force) { s.network = network.read(preferred: config.interface, probeLatency: config.latency) }
        if due(.disk, now, force: force) { s.disk = disk.read() }
        if due(.battery, now, force: force) { s.battery = battery.read() }
        if due(.bluetooth, now, force: force) { s.bluetooth = bluetooth.read(now: now) }
        let cpuDue = lastRead[.cpu] == now && config.cpuFrequency
        let sensorsDue = due(.sensors, now, force: force)
        let gpuDue = due(.gpu, now, force: force)
        if sensorsDue || gpuDue || cpuDue {
            lastPower = power.read()
            if sensorsDue { s.sensors = sensors.read(power: lastPower) }
            if gpuDue { s.gpu = gpu.read(power: lastPower, temperature: s.sensors.value(.gpu)) }
        }
        if cpuDue {
            s.cpu.frequencyMHz = lastPower.cpuMHz
            s.cpu.performanceMHz = lastPower.performanceMHz
            s.cpu.efficiencyMHz = lastPower.efficiencyMHz
        }
        // Process lists feed the CPU, memory, GPU, network and disk views.
        let wantsProcesses = config.processesWanted || !config.monitored.isDisjoint(with: [.cpu, .memory, .gpu, .network, .disk])
        if !wantsProcesses {
            lastProcesses = nil
        } else if force || processesDue || config.processes.includeOtherUsers && lastProcesses == nil
            || now.timeIntervalSince(lastProcessRead) >= config.processInterval * slowFactor - 0.25 {
            lastProcesses = processes.read(config.processes)
            lastProcessRead = now
            processesDue = false
        }
        let (procs, top) = lastProcesses ?? (ProcessSnapshot(), [])
        s.processes = procs
        s.topCPUNow = top
        s.selfCPU = processes.selfUsage.cpu
        s.selfMemory = processes.selfUsage.memory
        current = s


        let wasOnBattery = onBattery
        if config.monitored.contains(.battery) {
            onBattery = s.battery.hasBattery && !s.battery.onAC
        } else if config.slowOnBattery {
            onBattery = BatteryReader.onBatteryPower()
        } else {
            onBattery = false
        }
        if wasOnBattery != onBattery { reschedule() }

        onSnapshot?(s)
    }
}
