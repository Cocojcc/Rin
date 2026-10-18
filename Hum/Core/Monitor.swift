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
    private(set) var bluetooth: [BluetoothDevice] = []
    private(set) var publicIP: String?
    private(set) var interfaces: [(name: String, kind: InterfaceKind)] = []
    /// Sampling stopped from the sidebar's pause button; everything keeps its last values.
    private(set) var isPaused = false

    @ObservationIgnored let history = History()
    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var consumers: Set<Consumer> = []
    @ObservationIgnored private var lastPublicIP = Date.distantPast
    @ObservationIgnored var onSample: ((Snapshot) -> Void)?

    private init() {}

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.sampler.volumesChanged() }
        }
        sampler.onSnapshot = { [weak self] snapshot, devices in
            DispatchQueue.main.async { self?.apply(snapshot, devices) }
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
        // The overview and the combined panel show the whole machine, so while either is open
        // modules that are switched off are read too; otherwise they are not read at all.
        let wholeMachine = consumers.contains(.window(.overview)) || consumers.contains(.combinedPanel)
        config.monitored = wholeMachine ? Set(Module.allCases) : Set(Module.allCases.filter(prefs.isMonitored))
        for m in Module.allCases { config.intervals[m] = prefs.refresh(m) }
        config.processInterval = min(prefs.cpu.processRefresh, prefs.memory.processRefresh)
        config.latency = prefs.network.showLatency
        config.slowOnBattery = prefs.general.slowOnBattery
        config.interface = prefs.network.interface
        let anyUI = !consumers.isEmpty
        config.processes.includeOtherUsers = anyUI
        config.processes.network = config.monitored.contains(.network)
            && (consumers.contains(.popover(.network)) || consumers.contains(.window(.monitor(.network))) || consumers.contains(.combinedPanel))
        config.processes.gpu = config.monitored.contains(.gpu)
            && (consumers.contains(.popover(.gpu)) || consumers.contains(.window(.monitor(.gpu))) || consumers.contains(.window(.overview)))
        config.processes.limit = max(8, prefs.cpu.processCount, prefs.memory.processCount, prefs.gpu.processCount)
        let batteryVisible = config.monitored.contains(.battery)
            && (consumers.contains(.popover(.battery)) || consumers.contains(.window(.monitor(.battery))))
        config.bluetooth = batteryVisible && (prefs.battery.showBluetooth || consumers.contains(.window(.monitor(.battery))) || !snapshot.battery.hasBattery)
        config.headphones = consumers.contains(.window(.monitor(.battery))) || (batteryVisible && prefs.battery.showBluetooth)
        sampler.configure(config)

        if consumers.contains(.window(.monitor(.network))) || consumers.contains(.popover(.network)) {
            interfaces = sampler.interfaces()
        }
    }

    private func apply(_ s: Snapshot, _ devices: [BluetoothDevice]?) {
        snapshot = s
        if let devices { bluetooth = devices }
        history.record(s)
        tick &+= 1
        onSample?(s)
        refreshPublicIPIfNeeded()
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
        /// Modules read: those switched on, plus all of them while an overview is open.
        var monitored: Set<Module> = Set(Module.allCases)
        /// Seconds between reads per module; the timer ticks at the shortest of them.
        var intervals: [Module: Double] = [:]
        var processInterval: Double = 3
        var latency = false
        var slowOnBattery = true
        var interface = ""
        var processes = ProcessReader.Request()
        var bluetooth = false
        var headphones = false
    }

    var onSnapshot: ((Snapshot, [BluetoothDevice]?) -> Void)?

    private let queue = DispatchQueue(label: "hum.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config = Config()
    private var currentInterval: Double = 0
    private var onBattery = false
    private var lastProcesses: (ProcessSnapshot, [PeakProcess])?
    private var lastProcessRead = Date.distantPast
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
            self.config = config
            self.reschedule()
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
        if !config.monitored.contains(.gpu) { s.gpu = GPUSample() }
        if due(.cpu, now, force: force) { s.cpu = cpu.read() }
        if due(.memory, now, force: force) { s.memory = memory.read() }
        if due(.network, now, force: force) { s.network = network.read(preferred: config.interface, probeLatency: config.latency) }
        if due(.disk, now, force: force) { s.disk = disk.read() }
        if due(.battery, now, force: force) { s.battery = battery.read() }
        let cpuDue = lastRead[.cpu] == now
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
        let wantsProcesses = !config.monitored.isDisjoint(with: [.cpu, .memory, .gpu, .network, .disk])
        if !wantsProcesses {
            lastProcesses = nil
        } else if force || config.processes.includeOtherUsers && lastProcesses == nil
            || now.timeIntervalSince(lastProcessRead) >= config.processInterval * slowFactor - 0.25 {
            lastProcesses = processes.read(config.processes)
            lastProcessRead = now
        }
        let (procs, top) = lastProcesses ?? (ProcessSnapshot(), [])
        s.processes = procs
        s.topCPUNow = top
        s.selfCPU = processes.selfUsage.cpu
        s.selfMemory = processes.selfUsage.memory
        current = s

        let devices = config.bluetooth ? bluetooth.read(includeHeadphones: config.headphones) : nil

        let wasOnBattery = onBattery
        if config.monitored.contains(.battery) {
            onBattery = s.battery.hasBattery && !s.battery.onAC
        } else if config.slowOnBattery {
            onBattery = BatteryReader.onBatteryPower()
        } else {
            onBattery = false
        }
        if wasOnBattery != onBattery { reschedule() }

        onSnapshot?(s, devices)
    }
}
