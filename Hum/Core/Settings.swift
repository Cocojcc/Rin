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
    var accent: AccentPalette = .graphite
    var temperatureUnit: TemperatureUnit = .celsius
    var language: LanguageChoice = .system
    var slowOnBattery = true
    var autoCheckUpdates = true
    /// Set once the first-launch window has been finished or closed.
    var onboarded = false
}

struct CPUPrefs: Codable, Equatable {
    var visible = true
    var refresh: Double = 1
    var processRefresh: Double = 3
    var showCores = true
    var splitCoreKinds = true
    var showLoad = true
    var showProcesses = true
    var processCount = 5
}

struct GPUPrefs: Codable, Equatable {
    var visible = false
    var refresh: Double = 1
    var valueType: GPUValueType = .utilization
    var showMemory = true
    var showFrequency = true
    var showTempPower = true
    var showVideo = true
    var showProcesses = true
    var processCount = 4
}

struct MemoryPrefs: Codable, Equatable {
    var visible = true
    var refresh: Double = 1
    var processRefresh: Double = 3
    var valueType: MemoryValueType = .percent
    var showComposition = true
    var showPressure = true
    var showSwap = true
    var showProcesses = true
    var processCount = 5
}

struct NetworkPrefs: Codable, Equatable {
    var visible = true
    var refresh: Double = 1
    var speedUnit: SpeedUnit = .auto
    var showLatency = true
    var showProcesses = true
    var showPublicIP = false
    var graphSeconds = 60
    var interface: String = ""   // empty = automatic (primary interface)
}

struct DiskPrefs: Codable, Equatable {
    var visible = false
    var refresh: Double = 1
    var content: DiskContent = .free
    var volume: String = ""      // empty = startup disk
    var showAllDisks = true
    var showGraph = true
    var showHealth = true
    var showProcesses = false
}

struct BatteryPrefs: Codable, Equatable {
    var visible = false
    var refresh: Double = 10
    var timeFormat: TimeFormat = .clock
    var showHealth = true
    var showCycles = true
    var showTemperature = true
    var showPower = true
    var showBluetooth = false
}

struct SensorsPrefs: Codable, Equatable {
    var visible = false
    var refresh: Double = 2
    var sensor: SensorChoice = .cpuAverage
    var showThermal = true
    var showAllTemps = true
    var showFans = true
    var showPower = true
}

struct MenubarPrefs: Codable, Equatable {
    var displayMode: DisplayMode = .separate
    var iconColor: ColorMode = .mono
    var colorOnHighLoad = true
    var order: [Module] = Module.allCases
    /// "不再提醒" on the notch card.
    var notchAlertDismissed = false
}

struct AlertPrefs: Codable, Equatable {
    var enabled = true
    var cpuOn = true
    var cpuThreshold: Double = 90
    var cpuMinutes: Double = 1
    var gpuOn = false
    var gpuThreshold: Double = 90
    var gpuMinutes: Double = 1
    var memoryOn = true
    var memoryLevel: MemoryPressure = .critical
    var diskOn = true
    var diskFreeGB: Double = 20
    var batteryOn = false
    var batteryPercent: Double = 20
    var tempOn = false
    var tempThreshold: Double = 95
    var networkOn = true
    var style: NotificationStyle = .banner
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
    /// Menu bar widgets per module (keyed by module raw value); missing entries use the defaults.
    var widgetState: [String: ModuleWidgets] = [:]

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

    /// Seconds between samples for a module (doubled on battery when that is switched on).
    func refresh(_ module: Module) -> Double {
        switch module {
        case .cpu: return cpu.refresh
        case .gpu: return gpu.refresh
        case .memory: return memory.refresh
        case .network: return network.refresh
        case .disk: return disk.refresh
        case .battery: return battery.refresh
        case .sensors: return sensors.refresh
        }
    }

    mutating func setVisible(_ module: Module, _ value: Bool) {
        // Switching a module on with no widget selected brings back its main widget.
        if value && widgets(module).isEmpty { setWidget(module.primaryWidget, true, for: module) }
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

    private static let key = "preferences.v2"
    private static let legacyKey = "preferences.v1"
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
           let decoded = Self.decode(data) {
            prefs = decoded
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyKey),
                  var decoded = Self.decode(data) {
            // v1 defaulted to orange; the glass design's default accent is graphite.
            if decoded.general.accent == .orange { decoded.general.accent = .graphite }
            prefs = decoded
        } else {
            prefs = Preferences()
        }
        // Keep every module in the order list, even ones added after the prefs were saved.
        let missing = Module.allCases.filter { !prefs.menubar.order.contains($0) }
        prefs.menubar.order.append(contentsOf: missing)
    }

    /// Decodes saved prefs on top of the defaults, so fields added in later versions get their
    /// default value instead of failing the whole decode.
    static func decode(_ data: Data) -> Preferences? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Preferences()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: merge(defaults, stored)) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: merged)
    }

    private static func merge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (key, value) in over {
            if let b = base[key] as? [String: Any], let o = value as? [String: Any] {
                out[key] = merge(b, o)
            } else {
                out[key] = value
            }
        }
        return out
    }

    private func save() {
        guard Self.persistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func resetMenubar() {
        let defaults = Preferences()
        let dismissed = prefs.menubar.notchAlertDismissed
        prefs.menubar = defaults.menubar
        prefs.menubar.notchAlertDismissed = dismissed
        prefs.cpu = defaults.cpu
        prefs.gpu = defaults.gpu
        prefs.memory = defaults.memory
        prefs.network = defaults.network
        prefs.disk = defaults.disk
        prefs.battery = defaults.battery
        prefs.sensors = defaults.sensors
        prefs.widgetState = [:]
    }
}
