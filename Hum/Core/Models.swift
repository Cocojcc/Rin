import Foundation

enum Module: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, battery, sensors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return L10n.Module.cpu
        case .gpu: return L10n.Module.gpu
        case .memory: return L10n.Module.memory
        case .network: return L10n.Module.network
        case .disk: return L10n.Module.disk
        case .battery: return L10n.Module.battery
        case .sensors: return L10n.Module.sensors
        }
    }

    /// Short Latin label used by the two-line compact style (Chinese is unreadable at 7 pt).
    /// Default text of the "label" and "mini" widgets.
    var widgetLabel: String {
        switch self {
        case .memory: return "RAM"
        default: return compactLabel
        }
    }

    var compactLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "MEM"
        case .network: return "NET"
        case .disk: return "SSD"
        case .battery: return "BAT"
        case .sensors: return "TMP"
        }
    }
}

// MARK: - Menu bar styles


enum ColorMode: String, Codable, CaseIterable { case mono, color }

// MARK: - Samples

enum CoreKind: String, Codable { case performance, efficiency }

struct CPUSample {
    var total: Double = 0      // 0...1
    var user: Double = 0
    var system: Double = 0
    var perCore: [Double] = []
    var coreKinds: [CoreKind] = []
    /// Per-core user / system split (0...1 of each core), same order as `perCore`.
    var perCoreUser: [Double] = []
    var perCoreSystem: [Double] = []
    var load: (Double, Double, Double) = (0, 0, 0)
    /// Average running frequency (MHz) over the last interval: all cores, P cluster, E cluster.
    var frequencyMHz: Double?
    var performanceMHz: Double?
    var efficiencyMHz: Double?
}

enum MemoryPressure: Int, Codable {
    case normal = 1, warning = 2, critical = 4
}

struct MemorySample {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal
    /// 0...1, derived from kern.memorystatus_level (share of memory still available to the system).
    var pressureLevel: Double = 0

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum InterfaceKind { case wifi, ethernet, vpn, other }

struct NetworkSample {
    var down: Double = 0        // bytes per second
    var up: Double = 0
    var connected = false
    var interface: String = ""
    var kind: InterfaceKind = .other
    var localIP: String = ""
    var router: String = ""
    var sessionDown: UInt64 = 0
    var sessionUp: UInt64 = 0
    var todayDown: UInt64 = 0
    var todayUp: UInt64 = 0
    var lastConnected: Date?
    /// Round trip to the router (or a public resolver) from the latest connection check.
    var latencyMS: Double?
    /// Recent connection checks, oldest first (at most 48).
    var checks: [ConnectionCheck] = []
}

enum ConnectionCheck: Int, Codable { case ok, slow, failed }

struct Volume: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    var total: Int64
    var available: Int64
    var isInternal: Bool
    var isEjectable: Bool
    var isRoot: Bool
    /// Space macOS can free on demand (caches, local snapshots), counted as used.
    var purgeable: Int64 = 0

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskSample {
    var volumes: [Volume] = []
    var read: Double = 0        // bytes per second
    var write: Double = 0
    var totalRead: UInt64 = 0   // since boot
    var totalWritten: UInt64 = 0
    /// S.M.A.R.T. of the internal SSD, when the NVMe controller reports it.
    var health: DiskHealth?

    var root: Volume? { volumes.first(where: \.isRoot) ?? volumes.first }
}

struct DiskHealth {
    var ok: Bool
    var lifeRemaining: Double       // 0...1
    var totalWritten: UInt64        // bytes over the drive's life
    var temperature: Double?
}

struct PowerSource: Identifiable {
    var id: String
    var name: String
    var level: Double
    var isUPS: Bool
    var onAC: Bool
    var minutesLeft: Int?
}

struct BatterySample {
    var hasBattery = false
    var level: Double = 0           // 0...1
    var isCharging = false
    var onAC = false
    var isCharged = false
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var health: Double?             // 0...1
    var cycles: Int?
    var temperature: Double?        // °C
    var power: Double?              // W, positive while charging
    var systemPowerIn: Double?      // W drawn from the adapter by the whole Mac
    var adapterWatts: Int?
    var maxCapacity: Int?           // mAh when full
    var designCapacity: Int?        // mAh
    var designCycles: Int?
    var ups: [PowerSource] = []
}

struct BluetoothDevice: Identifiable {
    enum Kind { case keyboard, mouse, trackpad, headphones, other }
    var id: String
    var name: String
    var kind: Kind
    var level: Double
    var detail: String?
}

enum TempGroup: String, CaseIterable {
    case cpuPerformance, cpuEfficiency, gpu, ssd, battery, wireless
}

struct TempReading: Identifiable {
    var id: TempGroup { group }
    var group: TempGroup
    var value: Double
}

struct Fan: Identifiable {
    var id: Int
    var rpm: Double
    var min: Double
    var max: Double
}

enum ThermalLevel: Int {
    case nominal, fair, serious, critical
}

struct SensorsSample {
    var temps: [TempReading] = []
    var fans: [Fan] = []
    var hasFans = true
    var systemPower: Double?
    var cpuPower: Double?
    var gpuPower: Double?
    var thermal: ThermalLevel = .nominal
    /// Fans run under automatic control (no manual override).
    var fansAuto = true

    var cpuMax: Double? {
        temps.filter { $0.group == .cpuPerformance || $0.group == .cpuEfficiency }.map(\.value).max()
    }

    var cpuAverage: Double? {
        let cpu = temps.filter { $0.group == .cpuPerformance || $0.group == .cpuEfficiency }
        guard !cpu.isEmpty else { return nil }
        return cpu.map(\.value).reduce(0, +) / Double(cpu.count)
    }

    func value(_ group: TempGroup) -> Double? { temps.first(where: { $0.group == group })?.value }
}

struct GPUSample {
    var utilization: Double = 0     // 0...1
    var memoryUsed: UInt64 = 0
    var memoryLimit: UInt64 = 0
    var frequencyMHz: Double?
    var averageMHz: Double?
    var maxMHz: Double?
    var temperature: Double?
    var power: Double?
    var cores: Int = 0
    var model: String = ""
    var renderer: Double?           // 0...1
    var tiler: Double?              // 0...1
    /// Media engine power (W): macOS reports their energy, not utilization or codec.
    var decodeWatts: Double?
    var encodeWatts: Double?
    /// Main display: current refresh (frames per second) and its maximum.
    var fps: Double?
    var maxFPS: Int = 60
}

/// One row in a "top processes" list. Helper processes are folded into their app.
struct ProcessUsage: Identifiable, Hashable {
    var id: String               // bundle path or "pid:<n>"
    var pid: pid_t               // representative (main) pid
    var pids: [pid_t]
    var name: String
    var bundlePath: String?
    var executablePath: String?
    var isSystem: Bool
    var cpu: Double = 0          // percent of one core (100 = one full core)
    var memory: UInt64 = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var netDown: Double = 0
    var netUp: Double = 0
    var gpu: Double = 0          // percent of the GPU

    var netTotal: Double { netDown + netUp }
    var diskTotal: Double { diskRead + diskWrite }
}

struct ProcessSnapshot {
    var byCPU: [ProcessUsage] = []
    var byMemory: [ProcessUsage] = []
    var byDisk: [ProcessUsage] = []
    var byNetwork: [ProcessUsage] = []
    var byGPU: [ProcessUsage] = []
    var processCount = 0
    var threadCount = 0
}

/// The tick's full reading, produced on the sampler queue and applied on the main thread.
struct Snapshot {
    var date = Date()
    var cpu = CPUSample()
    var memory = MemorySample()
    var network = NetworkSample()
    var disk = DiskSample()
    var battery = BatterySample()
    var sensors = SensorsSample()
    var gpu = GPUSample()
    var processes = ProcessSnapshot()
    var topCPUNow: [PeakProcess] = []
    var selfCPU: Double = 0
    var selfMemory: UInt64 = 0
    /// Modules that were read for this snapshot; the others are switched off and left empty.
    var monitored: Set<Module> = Set(Module.allCases)
}

struct PeakProcess: Codable, Hashable {
    var name: String
    var cpu: Double
}
