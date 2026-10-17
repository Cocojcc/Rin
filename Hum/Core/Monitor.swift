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
        config.interval = prefs.general.refreshInterval
        config.slowOnBattery = prefs.general.slowOnBattery
        config.interface = prefs.network.interface
        let anyUI = !consumers.isEmpty
        config.processes.includeOtherUsers = anyUI
        config.processes.network = consumers.contains(.popover(.network)) || consumers.contains(.window(.monitor(.network))) || consumers.contains(.combinedPanel)
        config.processes.gpu = consumers.contains(.popover(.gpu)) || consumers.contains(.window(.monitor(.gpu))) || consumers.contains(.window(.overview))
        config.processes.limit = max(8, prefs.cpu.processCount, prefs.memory.processCount, prefs.gpu.processCount)
        let batteryVisible = consumers.contains(.popover(.battery)) || consumers.contains(.window(.monitor(.battery)))
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
        var interval: Double = 2
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
    private var tickCount = 0
    private var lastProcesses: (ProcessSnapshot, [PeakProcess])?

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

    func sampleNow() {
        queue.async { self.sample() }
    }

    func volumesChanged() {
        queue.async {
            self.disk.invalidateVolumes()
            self.sample()
        }
    }

    func interfaces() -> [(name: String, kind: InterfaceKind)] {
        queue.sync { network.availableInterfaces() }
    }

    private func reschedule() {
        let interval = config.interval * (config.slowOnBattery && onBattery ? 2 : 1)
        guard interval != currentInterval || timer == nil else { return }
        currentInterval = interval
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    private func sample() {
        var s = Snapshot()
        s.date = Date()
        s.cpu = cpu.read()
        s.memory = memory.read()
        s.network = network.read(preferred: config.interface)
        s.disk = disk.read()
        s.battery = battery.read()
        let reading = power.read()
        s.sensors = sensors.read(power: reading)
        s.gpu = gpu.read(power: reading, temperature: s.sensors.value(.gpu))
        tickCount &+= 1
        if config.processes.includeOtherUsers || tickCount % 3 == 0 || lastProcesses == nil {
            lastProcesses = processes.read(config.processes)
        }
        let (procs, top) = lastProcesses ?? (ProcessSnapshot(), [])
        s.processes = procs
        s.topCPUNow = top
        s.selfCPU = processes.selfUsage.cpu
        s.selfMemory = processes.selfUsage.memory

        let devices = config.bluetooth ? bluetooth.read(includeHeadphones: config.headphones) : nil

        let wasOnBattery = onBattery
        onBattery = s.battery.hasBattery && !s.battery.onAC
        if wasOnBattery != onBattery { reschedule() }

        onSnapshot?(s, devices)
    }
}
