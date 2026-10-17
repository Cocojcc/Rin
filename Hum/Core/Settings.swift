import Foundation
import Observation

enum AppearanceMode: String, Codable, CaseIterable { case system, light, dark }
enum TemperatureUnit: String, Codable, CaseIterable { case celsius, fahrenheit }
enum LanguageChoice: String, Codable, CaseIterable { case system, zhHans, en }
enum DisplayMode: String, Codable, CaseIterable { case separate, combined }
enum CPUGraphContent: String, Codable, CaseIterable { case total, userSystem }
enum GPUValueType: String, Codable, CaseIterable { case utilization, memory }
enum MemoryValueType: String, Codable, CaseIterable { case percent, usedGB }
enum MemoryColor: String, Codable, CaseIterable { case mono, pressure }
enum NetworkOrder: String, Codable, CaseIterable { case uploadTop, downloadTop }
enum SpeedUnit: String, Codable, CaseIterable { case auto, bytes, bits }
enum DiskContent: String, Codable, CaseIterable { case free, usedPercent, readWrite }
enum SensorChoice: String, Codable, CaseIterable { case cpuAverage, cpuPerformance, cpuEfficiency, gpu, ssd, battery }
enum TempColor: String, Codable, CaseIterable { case mono, byTemp }
enum NotificationStyle: String, Codable, CaseIterable { case banner, alert }

struct GeneralPrefs: Codable, Equatable {
    var appearance: AppearanceMode = .system
    var accent: AccentPalette = .orange
    var temperatureUnit: TemperatureUnit = .celsius
    var language: LanguageChoice = .system
    var refreshInterval: Double = 2
    var slowOnBattery = true
}

struct CPUPrefs: Codable, Equatable {
    var visible = true
    var style: CPUStyle = .graph
    var showValue = true
    var graphContent: CPUGraphContent = .total
    var color: ColorMode = .mono
    var showCores = true
    var splitCoreKinds = true
    var showLoad = true
    var showProcesses = true
    var processCount = 5
}

struct GPUPrefs: Codable, Equatable {
    var visible = false
    var style: GPUStyle = .iconValue
    var showValue = true
    var valueType: GPUValueType = .utilization
    var color: ColorMode = .mono
    var showMemory = true
    var showFrequency = true
    var showTempPower = true
    var showProcesses = true
    var processCount = 4
}

struct MemoryPrefs: Codable, Equatable {
    var visible = true
    var style: MemoryStyle = .bar
    var showValue = true
    var valueType: MemoryValueType = .percent
    var color: MemoryColor = .mono
    var showComposition = true
    var showPressure = true
    var showSwap = true
    var showProcesses = true
    var processCount = 5
}

struct NetworkPrefs: Codable, Equatable {
    var visible = true
    var style: NetworkStyle = .arrows
    var showUnit = true
    var order: NetworkOrder = .uploadTop
    var color: ColorMode = .mono
    var speedUnit: SpeedUnit = .auto
    var showProcesses = true
    var showPublicIP = false
    var graphSeconds = 60
    var interface: String = ""   // empty = automatic (primary interface)
}

struct DiskPrefs: Codable, Equatable {
    var visible = false
    var style: DiskStyle = .iconValue
    var content: DiskContent = .free
    var volume: String = ""      // empty = startup disk
    var showAllDisks = true
    var showGraph = true
    var showProcesses = false
}

struct BatteryPrefs: Codable, Equatable {
    var visible = true
    var style: BatteryStyle = .iconPercent
    var showTimeRemaining = false
    var showBolt = true
    var colorWhenLow = true
    var showHealth = true
    var showCycles = true
    var showPower = true
    var showBluetooth = false
}

struct SensorsPrefs: Codable, Equatable {
    var visible = true
    var style: SensorsStyle = .iconTemp
    var sensor: SensorChoice = .cpuAverage
    var color: TempColor = .mono
    var showAllTemps = true
    var showFans = true
    var showPower = true
}

struct MenubarPrefs: Codable, Equatable {
    var displayMode: DisplayMode = .separate
    var iconColor: ColorMode = .mono
    var colorOnHighLoad = true
    var order: [Module] = Module.allCases
}

struct AlertPrefs: Codable, Equatable {
    var enabled = true
    var cpuOn = true
    var cpuThreshold: Double = 90
    var cpuMinutes: Double = 1
    var memoryOn = true
    var memoryLevel: MemoryPressure = .critical
    var diskOn = true
    var diskFreeGB: Double = 20
    var batteryOn = false
    var batteryPercent: Double = 20
    var tempOn = false
    var tempThreshold: Double = 95
    var networkOn = true
    var sound = false
    var colorMenubar = true
}

struct Preferences: Codable, Equatable {
    var general = GeneralPrefs()
    var menubar = MenubarPrefs()
    var cpu = CPUPrefs()
    var gpu = GPUPrefs()
    var memory = MemoryPrefs()
    var network = NetworkPrefs()
    var disk = DiskPrefs()
    var battery = BatteryPrefs()
    var sensors = SensorsPrefs()
    var alerts = AlertPrefs()

    func isVisible(_ module: Module) -> Bool {
        switch module {
        case .cpu: return cpu.visible
        case .gpu: return gpu.visible
        case .memory: return memory.visible
        case .network: return network.visible
        case .disk: return disk.visible
        case .battery: return battery.visible
        case .sensors: return sensors.visible
        }
    }

    mutating func setVisible(_ module: Module, _ value: Bool) {
        switch module {
        case .cpu: cpu.visible = value
        case .gpu: gpu.visible = value
        case .memory: memory.visible = value
        case .network: network.visible = value
        case .disk: disk.visible = value
        case .battery: battery.visible = value
        case .sensors: sensors.visible = value
        }
    }
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private static let key = "preferences.v1"
    /// Off while rendering debug snapshots so previews never overwrite the user's settings.
    static var persistenceEnabled = true

    var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            save()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = decoded
        } else {
            prefs = Preferences()
        }
        // Keep every module in the order list, even ones added after the prefs were saved.
        let missing = Module.allCases.filter { !prefs.menubar.order.contains($0) }
        prefs.menubar.order.append(contentsOf: missing)
    }

    private func save() {
        guard Self.persistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func resetMenubar() {
        let defaults = Preferences()
        prefs.menubar = defaults.menubar
        prefs.cpu = defaults.cpu
        prefs.gpu = defaults.gpu
        prefs.memory = defaults.memory
        prefs.network = defaults.network
        prefs.disk = defaults.disk
        prefs.battery = defaults.battery
        prefs.sensors = defaults.sensors
    }
}
