import Foundation

/// Every user-visible string, including accessibility labels. Translations live in
/// Resources/<lang>.lproj/Localizable.strings; views never contain literal copy.
enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        spaced(String(format: tr(key), arguments: args))
    }

    /// Chinese typography: a space between CJK and Latin letters or digits ("打开 CPU 监视器",
    /// "打开内存监视器"). Lets one template serve both kinds of arguments.
    static func spaced(_ s: String) -> String {
        func isCJK(_ c: Character) -> Bool {
            guard let v = c.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        }
        func isLatin(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        var out = ""
        var prev: Character?
        for c in s {
            if let p = prev, (isCJK(p) && isLatin(c)) || (isLatin(p) && isCJK(c)) { out.append(" ") }
            out.append(c)
            prev = c
        }
        return out
    }

    enum App {
        static var name: String { tr("app.name") }
        static func version(_ v: String) -> String { tr("app.version", v) }
    }

    enum Module {
        static var cpu: String { tr("module.cpu") }
        static var gpu: String { tr("module.gpu") }
        static var memory: String { tr("module.memory") }
        static var network: String { tr("module.network") }
        static var disk: String { tr("module.disk") }
        static var battery: String { tr("module.battery") }
        static var sensors: String { tr("module.sensors") }
    }

    enum Range {
        static var m5: String { tr("range.5m") }
        static var m30: String { tr("range.30m") }
        static var h1: String { tr("range.1h") }
        static var h24: String { tr("range.24h") }
        static var d7: String { tr("range.7d") }
        static var label: String { tr("range.label") }
        static var last60s: String { tr("range.last60s") }
        static func lastSeconds(_ n: Int) -> String { tr("range.lastSeconds", n) }
        static var last24h: String { tr("range.last24h") }
        static var ago24h: String { tr("range.ago24h") }
        static var ago12h: String { tr("range.ago12h") }
        static var now: String { tr("range.now") }
    }

    enum Time {
        static func today(_ t: String) -> String { tr("time.today", t) }
        static func yesterday(_ t: String) -> String { tr("time.yesterday", t) }
    }

    enum Sidebar {
        static var label: String { tr("sidebar.label") }
        static var monitors: String { tr("sidebar.monitors") }
        static var settings: String { tr("sidebar.settings") }
        static var overview: String { tr("sidebar.overview") }
        static var general: String { tr("sidebar.general") }
        static var menubar: String { tr("sidebar.menubar") }
        static var alerts: String { tr("sidebar.alerts") }
        static var about: String { tr("sidebar.about") }
    }

    enum Common {
        static var on: String { tr("common.on") }
        static var off: String { tr("common.off") }
        static var cancel: String { tr("common.cancel") }
        static var auto: String { tr("common.auto") }
        static var none: String { tr("common.none") }
        static var dash: String { tr("common.dash") }
        static func count(_ n: Int) -> String { tr("common.count", n) }
        static var mono: String { tr("common.mono") }
        static var colored: String { tr("common.colored") }
        static var restart: String { tr("common.restart") }
    }

    enum Overview {
        static var title: String { tr("overview.title") }
        static func uptimeDays(_ d: Int, _ h: Int) -> String { tr("overview.uptime.days", d, h) }
        static func uptimeHours(_ h: Int, _ m: Int) -> String { tr("overview.uptime.hours", h, m) }
        static func uptimeMinutes(_ m: Int) -> String { tr("overview.uptime.minutes", m) }
        static var allGood: String { tr("overview.allGood") }
        static func issues(_ n: Int) -> String { tr("overview.issues", n) }
        static func cpuDetail(_ user: String, _ system: String) -> String { tr("overview.cpu.detail", user, system) }
        static func gpuDetail(_ mem: String, _ temp: String) -> String { tr("overview.gpu.detail", mem, temp) }
        static func gpuDetailNoTemp(_ mem: String) -> String { tr("overview.gpu.detailNoTemp", mem) }
        static func memoryOf(_ total: String) -> String { tr("overview.memory.of", total) }
        static var pressureNormal: String { tr("overview.memory.pressureNormal") }
        static var pressureWarning: String { tr("overview.memory.pressureWarning") }
        static var pressureCritical: String { tr("overview.memory.pressureCritical") }
        static var wifiConnected: String { tr("overview.network.wifi") }
        static var ethernetConnected: String { tr("overview.network.ethernet") }
        static var connected: String { tr("overview.network.connected") }
        static var disconnected: String { tr("overview.network.disconnected") }
        static func diskOf(_ total: String) -> String { tr("overview.disk.of", total) }
        static var cpuTemp: String { tr("overview.sensors.cpuTemp") }
        static var fan: String { tr("overview.sensors.fan") }
        static var power: String { tr("overview.sensors.power") }
        static var noFan: String { tr("overview.sensors.noFan") }
        static var topUsage: String { tr("overview.top") }
        static var sortBy: String { tr("overview.sortBy") }
        static var noBattery: String { tr("overview.battery.none") }
    }

    enum Battery {
        static func budLeft(_ p: Int) -> String { tr("battery.bud.left", p) }
        static func budRight(_ p: Int) -> String { tr("battery.bud.right", p) }
        static func budCase(_ p: Int) -> String { tr("battery.bud.case", p) }
        static var charging: String { tr("battery.charging") }
        static var charged: String { tr("battery.charged") }
        static var onBattery: String { tr("battery.onBattery") }
        static var onAC: String { tr("battery.onAC") }
        static func untilFull(_ t: String) -> String { tr("battery.untilFull", t) }
        static func remaining(_ t: String) -> String { tr("battery.remaining", t) }
        static func adapter(_ w: Int) -> String { tr("battery.adapter", w) }
        static var health: String { tr("battery.health") }
        static var cycles: String { tr("battery.cycles") }
        static var temperature: String { tr("battery.temperature") }
        static var power: String { tr("battery.power") }
        static var chargingPower: String { tr("battery.chargingPower") }
        static var adapterLabel: String { tr("battery.adapterLabel") }
        static var level: String { tr("battery.level") }
        static var levelHistory: String { tr("battery.levelHistory") }
        static var bluetooth: String { tr("battery.bluetooth") }
        static func deviceCount(_ n: Int) -> String { tr("battery.deviceCount", n) }
        static var noBattery: String { tr("battery.noBattery") }
        static var ups: String { tr("battery.ups") }
        static func upsDetail(_ minutes: Int) -> String { tr("battery.upsDetail", minutes) }
        static var upsOnAC: String { tr("battery.upsOnAC") }
        static var low: String { tr("battery.low") }
        static var noDevices: String { tr("battery.noDevices") }
        static var lowA11y: String { tr("battery.lowA11y") }
        static var chargingA11y: String { tr("battery.chargingA11y") }
    }

    enum Menu {
        static var open: String { tr("menu.open") }
        static var settings: String { tr("menu.settings") }
        static var quit: String { tr("menu.quit") }
    }

    enum A11y {
        static var separator: String { tr("a11y.separator") }
        static func cpu(_ v: String) -> String { tr("a11y.cpu", v) }
        static func gpu(_ v: String) -> String { tr("a11y.gpu", v) }
        static func memory(_ v: String) -> String { tr("a11y.memory", v) }
        static func network(_ up: String, _ down: String) -> String { tr("a11y.network", up, down) }
        static var networkOffline: String { tr("a11y.networkOffline") }
        static func disk(_ v: String) -> String { tr("a11y.disk", v) }
        static func battery(_ v: String) -> String { tr("a11y.battery", v) }
        static func temperature(_ v: String) -> String { tr("a11y.temperature", v) }
    }

    enum Alerts {
        static var quitAction: String { tr("alerts.quitAction") }
        static var cpuTitle: String { tr("alerts.cpu.title") }
        static func cpuBody(_ v: String, _ duration: String) -> String { tr("alerts.cpu.body", v, duration) }
        static func cpuCulprit(_ name: String, _ v: String) -> String { tr("alerts.cpu.culprit", name, v) }
        static var memoryTitle: String { tr("alerts.memory.title") }
        static var memoryBody: String { tr("alerts.memory.body") }
        static func memoryCulprit(_ name: String, _ v: String) -> String { tr("alerts.memory.culprit", name, v) }
        static var diskTitle: String { tr("alerts.disk.title") }
        static func diskBody(_ name: String, _ v: String) -> String { tr("alerts.disk.body", name, v) }
        static var batteryTitle: String { tr("alerts.battery.title") }
        static func batteryBody(_ v: String) -> String { tr("alerts.battery.body", v) }
        static var tempTitle: String { tr("alerts.temp.title") }
        static func tempBody(_ v: String) -> String { tr("alerts.temp.body", v) }
        static var networkTitle: String { tr("alerts.network.title") }
        static var networkBody: String { tr("alerts.network.body") }
        static func seconds(_ n: Int) -> String { tr("alerts.seconds", n) }
        static func minutes(_ n: Int) -> String { tr("alerts.minutes", n) }
    }

    enum Panel {
        static func openMonitor(_ m: String) -> String { tr("panel.openMonitor", m) }
        static func moduleSettings(_ m: String) -> String { tr("panel.moduleSettings", m) }
        static var noProcesses: String { tr("panel.noProcesses") }
        static var quit: String { tr("panel.quit") }
        static var quitting: String { tr("panel.quitting") }
        static func quitNamed(_ n: String) -> String { tr("panel.quitNamed", n) }
        static var forceQuit: String { tr("panel.forceQuit") }
        static var forceQuitEllipsis: String { tr("panel.forceQuitEllipsis") }
        static var showInActivityMonitor: String { tr("panel.showInActivityMonitor") }
        static var showInFinder: String { tr("panel.showInFinder") }
        static var copyNamePID: String { tr("panel.copyNamePID") }
        static var notResponding: String { tr("panel.notResponding") }
        static var forceQuitWarning: String { tr("panel.forceQuitWarning") }
        static func quitDone(_ n: String) -> String { tr("panel.quitDone", n) }
        static func freed(_ v: String) -> String { tr("panel.freed", v) }
        static func chipCores(_ chip: String, _ n: Int) -> String { tr("panel.chipCores", chip, n) }
        static func coreSplit(_ p: Int, _ e: Int) -> String { tr("panel.coreSplit", p, e) }
        static func coreCount(_ n: Int) -> String { tr("panel.coreCount", n) }
        static var pressureNormal: String { tr("panel.pressure.normal") }
        static var pressureWarning: String { tr("panel.pressure.warning") }
        static var pressureCritical: String { tr("panel.pressure.critical") }
        static var thermalNominal: String { tr("panel.thermal.nominal") }
        static var thermalFair: String { tr("panel.thermal.fair") }
        static var thermalSerious: String { tr("panel.thermal.serious") }
        static var thermalCritical: String { tr("panel.thermal.critical") }
        static func notConnectedKind(_ k: String) -> String { tr("panel.notConnectedKind", k) }
        static var wifi: String { tr("panel.wifi") }
        static var ethernet: String { tr("panel.ethernet") }
        static var network: String { tr("panel.network") }
        static var vpn: String { tr("panel.vpn") }
        static func chargingUntilFull(_ t: String) -> String { tr("panel.chargingUntilFull", t) }
        static func onBatteryRemaining(_ t: String) -> String { tr("panel.onBatteryRemaining", t) }
        static var cpuChartA11y: String { tr("panel.cpuChartA11y") }
        static var gpuChartA11y: String { tr("panel.gpuChartA11y") }
        static var pressureChartA11y: String { tr("panel.pressureChartA11y") }
        static var networkChartA11y: String { tr("panel.networkChartA11y") }
        static var diskChartA11y: String { tr("panel.diskChartA11y") }
        static var batteryChartA11y: String { tr("panel.batteryChartA11y") }
        static var user: String { tr("panel.user") }
        static var system: String { tr("panel.system") }
        static var cores: String { tr("panel.cores") }
        static var perfAverage: String { tr("panel.perfAverage") }
        static var effAverage: String { tr("panel.effAverage") }
        static var loadAverage: String { tr("panel.loadAverage") }
        static var load1: String { tr("panel.load1") }
        static var load5: String { tr("panel.load5") }
        static var load15: String { tr("panel.load15") }
        static var topUsage: String { tr("panel.topUsage") }
        static var topTraffic: String { tr("panel.topTraffic") }
        static var topDisk: String { tr("panel.topDisk") }
        static var utilization: String { tr("panel.utilization") }
        static var vram: String { tr("panel.vram") }
        static func limit(_ v: String) -> String { tr("panel.limit", v) }
        static var used: String { tr("panel.used") }
        static var frequency: String { tr("panel.frequency") }
        static var temperature: String { tr("panel.temperature") }
        static var power: String { tr("panel.power") }
        static func memoryUsedOf(_ used: String, _ total: String) -> String { tr("panel.memoryUsedOf", used, total) }
        static var composition: String { tr("panel.composition") }
        static var pressure: String { tr("panel.pressure") }
        static var notConnected: String { tr("panel.notConnected") }
        static var noConnection: String { tr("panel.noConnection") }
        static var networkSettings: String { tr("panel.networkSettings") }
        static var download: String { tr("panel.download") }
        static var upload: String { tr("panel.upload") }
        static func volumeAvailable(_ v: String) -> String { tr("panel.volumeAvailable", v) }
        static func updatedEvery(_ s: Int) -> String { tr("panel.updatedEvery", s) }
        static func ofTotal(_ v: String) -> String { tr("panel.ofTotal", v) }
        static func memoryBreakdown(_ a: String, _ w: String, _ c: String) -> String { tr("panel.memoryBreakdown", a, w, c) }
        static func unitAvailable(_ u: String) -> String { tr("panel.unitAvailable", u) }
        static func readWriteShort(_ r: String, _ w: String) -> String { tr("panel.readWriteShort", r, w) }
        static func healthShort(_ v: String) -> String { tr("panel.healthShort", v) }
        static func vramUsed(_ v: String) -> String { tr("panel.vramUsed", v) }
        static var openActivityMonitor: String { tr("panel.openActivityMonitor") }
    }

    enum Sensors {
        static var cpuPerformance: String { tr("sensors.cpuPerformance") }
        static var cpuEfficiency: String { tr("sensors.cpuEfficiency") }
        static var gpu: String { tr("sensors.gpu") }
        static var ssd: String { tr("sensors.ssd") }
        static var battery: String { tr("sensors.battery") }
        static var wireless: String { tr("sensors.wireless") }
        static var fan: String { tr("sensors.fan") }
        static func fanNumbered(_ n: Int) -> String { tr("sensors.fanNumbered", n) }
        static var thermalState: String { tr("sensors.thermalState") }
        static var temperatures: String { tr("sensors.temperatures") }
        static var fans: String { tr("sensors.fans") }
        static func maxRPM(_ n: Int) -> String { tr("sensors.maxRPM", n) }
        static var fanless: String { tr("sensors.fanless") }
        static var systemPower: String { tr("sensors.systemPower") }
        static var cpuAverage: String { tr("sensors.cpuAverage") }
        static var power: String { tr("sensors.power") }
        static func choice(_ c: SensorChoice) -> String {
            switch c {
            case .cpuAverage: return cpuAverage
            case .cpuPerformance: return cpuPerformance
            case .cpuEfficiency: return cpuEfficiency
            case .gpu: return gpu
            case .ssd: return ssd
            case .battery: return battery
            }
        }
    }

    enum Memory {
        static var app: String { tr("memory.app") }
        static var wired: String { tr("memory.wired") }
        static var compressed: String { tr("memory.compressed") }
        static var cached: String { tr("memory.cached") }
        static var free: String { tr("memory.free") }
        static var swap: String { tr("memory.swap") }
        static var used: String { tr("memory.used") }
        static var total: String { tr("memory.total") }
    }

    enum Network {
        static var localIP: String { tr("network.localIP") }
        static var router: String { tr("network.router") }
        static var publicIP: String { tr("network.publicIP") }
        static var lastConnected: String { tr("network.lastConnected") }
        static var today: String { tr("network.today") }
        static var session: String { tr("network.session") }
        static var interface: String { tr("network.interface") }
        static func downUp(_ d: String, _ u: String) -> String { tr("network.downUp", d, u) }
    }

    enum Disk {
        static var read: String { tr("disk.read") }
        static var write: String { tr("disk.write") }
        static var sinceBoot: String { tr("disk.sinceBoot") }
        static var readSinceBoot: String { tr("disk.readSinceBoot") }
        static var writeSinceBoot: String { tr("disk.writeSinceBoot") }
        static func readWriteTotals(_ r: String, _ w: String) -> String { tr("disk.readWriteTotals", r, w) }
        static var external: String { tr("disk.external") }
        static func available(_ v: String) -> String { tr("disk.available", v) }
        static func eject(_ n: String) -> String { tr("disk.eject", n) }
        static func usedOf(_ u: String, _ t: String) -> String { tr("disk.usedOf", u, t) }
        static var used: String { tr("disk.used") }
        static var free: String { tr("disk.free") }
        static var total: String { tr("disk.total") }
    }

    enum Monitor {
        static var backToNow: String { tr("monitor.backToNow") }
        static func cpuChartA11y(_ v: String) -> String { tr("monitor.cpuChartA11y", v) }
        static func gpuChartA11y(_ v: String) -> String { tr("monitor.gpuChartA11y", v) }
        static func memoryChartA11y(_ v: String) -> String { tr("monitor.memoryChartA11y", v) }
        static func networkChartA11y(_ v: String) -> String { tr("monitor.networkChartA11y", v) }
        static func diskChartA11y(_ v: String) -> String { tr("monitor.diskChartA11y", v) }
        static func tempChartA11y(_ v: String) -> String { tr("monitor.tempChartA11y", v) }
        static var totalUsage: String { tr("monitor.totalUsage") }
        static func peakTop(_ v: String) -> String { tr("monitor.peakTop", v) }
        static var peakTopNone: String { tr("monitor.peakTopNone") }
        static var load1: String { tr("monitor.load1") }
        static var load5: String { tr("monitor.load5") }
        static var load15: String { tr("monitor.load15") }
        static var topCPU: String { tr("monitor.topCPU") }
        static var topGPU: String { tr("monitor.topGPU") }
        static var topMemory: String { tr("monitor.topMemory") }
        static var topNetwork: String { tr("monitor.topNetwork") }
        static var peaks24h: String { tr("monitor.peaks24h") }
        static var noPeaks: String { tr("monitor.noPeaks") }
        static func peakValue(_ v: String) -> String { tr("monitor.peakValue", v) }
        static func totalValue(_ v: String) -> String { tr("monitor.totalValue", v) }
        static func usedValue(_ v: String) -> String { tr("monitor.usedValue", v) }
        static var unifiedMemory: String { tr("monitor.unifiedMemory") }
        static func usedOfLimit(_ v: String) -> String { tr("monitor.usedOfLimit", v) }
        static var current: String { tr("monitor.current") }
        static var average: String { tr("monitor.average") }
        static var highest: String { tr("monitor.highest") }
        static var appMemory: String { tr("monitor.appMemory") }
        static var compressed: String { tr("monitor.compressed") }
        static var cache: String { tr("monitor.cache") }
        static var cpuAverageShort: String { tr("monitor.cpuAverageShort") }
        static var system: String { tr("monitor.system") }
        static func compositionA11y(_ a: String, _ w: String, _ c: String, _ k: String, _ f: String) -> String { tr("monitor.compositionA11y", a, w, c, k, f) }
    }

    enum Settings {
        static var startup: String { tr("settings.startup") }
        static var launchAtLogin: String { tr("settings.launchAtLogin") }
        static var loginItemNeedsApproval: String { tr("settings.loginItemNeedsApproval") }
        static var openLoginItems: String { tr("settings.openLoginItems") }
        static var appearance: String { tr("settings.appearance") }
        static var accent: String { tr("settings.accent") }
        static var temperatureUnit: String { tr("settings.temperatureUnit") }
        static var language: String { tr("settings.language") }
        static var restartToApply: String { tr("settings.restartToApply") }
        static var followSystem: String { tr("settings.followSystem") }
        static var chinese: String { tr("settings.chinese") }
        static var english: String { tr("settings.english") }
        static var performance: String { tr("settings.performance") }
        static var refreshInterval: String { tr("settings.refreshInterval") }
        static func seconds(_ v: Int) -> String { tr("settings.seconds", v) }
        static var slowOnBattery: String { tr("settings.slowOnBattery") }
        static var light: String { tr("settings.light") }
        static var dark: String { tr("settings.dark") }
        static var restoreDefaults: String { tr("settings.restoreDefaults") }
        static var preview: String { tr("settings.preview") }
        static func previewA11y(_ v: String) -> String { tr("settings.previewA11y", v) }
        static var display: String { tr("settings.display") }
        static var displayMode: String { tr("settings.displayMode") }
        static var separate: String { tr("settings.separate") }
        static var combined: String { tr("settings.combined") }
        static var iconColor: String { tr("settings.iconColor") }
        static var colorOnHighLoad: String { tr("settings.colorOnHighLoad") }
        static var modules: String { tr("settings.modules") }
        static func showInMenubarNamed(_ v: String) -> String { tr("settings.showInMenubarNamed", v) }
        static func moreSettings(_ v: String) -> String { tr("settings.moreSettings", v) }
        static func iconStyleNamed(_ v: String) -> String { tr("settings.iconStyleNamed", v) }
        static var backToMenubar: String { tr("settings.backToMenubar") }
        static var showInMenubar: String { tr("settings.showInMenubar") }
        static var menubarGroup: String { tr("settings.menubarGroup") }
        static var iconStyle: String { tr("settings.iconStyle") }
        static var panelGroup: String { tr("settings.panelGroup") }
        static var showValue: String { tr("settings.showValue") }
        static var graphContent: String { tr("settings.graphContent") }
        static var totalUsage: String { tr("settings.totalUsage") }
        static var userSystem: String { tr("settings.userSystem") }
        static var valueType: String { tr("settings.valueType") }
        static var color: String { tr("settings.color") }
        static var percent: String { tr("settings.percent") }
        static var usedGB: String { tr("settings.usedGB") }
        static var byPressure: String { tr("settings.byPressure") }
        static var showUnit: String { tr("settings.showUnit") }
        static var order: String { tr("settings.order") }
        static var uploadTop: String { tr("settings.uploadTop") }
        static var downloadTop: String { tr("settings.downloadTop") }
        static var speedUnit: String { tr("settings.speedUnit") }
        static var unitBytes: String { tr("settings.unitBytes") }
        static var unitBits: String { tr("settings.unitBits") }
        static var diskContent: String { tr("settings.diskContent") }
        static var freeSpace: String { tr("settings.freeSpace") }
        static var usedPercent: String { tr("settings.usedPercent") }
        static var readWrite: String { tr("settings.readWrite") }
        static var whichDisk: String { tr("settings.whichDisk") }
        static var startupDisk: String { tr("settings.startupDisk") }
        static var showTimeRemaining: String { tr("settings.showTimeRemaining") }
        static var showBolt: String { tr("settings.showBolt") }
        static var colorWhenLow: String { tr("settings.colorWhenLow") }
        static var whichSensor: String { tr("settings.whichSensor") }
        static var byTemperature: String { tr("settings.byTemperature") }
        static var showCores: String { tr("settings.showCores") }
        static var splitCores: String { tr("settings.splitCores") }
        static var showLoad: String { tr("settings.showLoad") }
        static var showProcesses: String { tr("settings.showProcesses") }
        static var processCount: String { tr("settings.processCount") }
        static var showVRAM: String { tr("settings.showVRAM") }
        static var showFrequency: String { tr("settings.showFrequency") }
        static var showTempPower: String { tr("settings.showTempPower") }
        static var showComposition: String { tr("settings.showComposition") }
        static var showPressure: String { tr("settings.showPressure") }
        static var showSwap: String { tr("settings.showSwap") }
        static var showPublicIP: String { tr("settings.showPublicIP") }
        static var graphDuration: String { tr("settings.graphDuration") }
        static var showAllDisks: String { tr("settings.showAllDisks") }
        static var showRWGraph: String { tr("settings.showRWGraph") }
        static var showHealth: String { tr("settings.showHealth") }
        static var showCycles: String { tr("settings.showCycles") }
        static var showChargingPower: String { tr("settings.showChargingPower") }
        static var showBluetooth: String { tr("settings.showBluetooth") }
        static var showAllTemps: String { tr("settings.showAllTemps") }
        static var showFans: String { tr("settings.showFans") }
        static var showPower: String { tr("settings.showPower") }
        static var alertsEnabled: String { tr("settings.alertsEnabled") }
        static var notificationsOff: String { tr("settings.notificationsOff") }
        static var openNotificationSettings: String { tr("settings.openNotificationSettings") }
        static var rules: String { tr("settings.rules") }
        static var ruleCPU: String { tr("settings.ruleCPU") }
        static var ruleFor: String { tr("settings.ruleFor") }
        static var ruleMemory: String { tr("settings.ruleMemory") }
        static var yellow: String { tr("settings.yellow") }
        static var red: String { tr("settings.red") }
        static var ruleDisk: String { tr("settings.ruleDisk") }
        static var ruleBattery: String { tr("settings.ruleBattery") }
        static var ruleTemp: String { tr("settings.ruleTemp") }
        static var ruleNetwork: String { tr("settings.ruleNetwork") }
        static var ruleToggle: String { tr("settings.ruleToggle") }
        static var delivery: String { tr("settings.delivery") }
        static var notificationStyle: String { tr("settings.notificationStyle") }
        static var changeInSystemSettings: String { tr("settings.changeInSystemSettings") }
        static var playSound: String { tr("settings.playSound") }
        static var colorMenubar: String { tr("settings.colorMenubar") }
        static var selfUsage: String { tr("settings.selfUsage") }
        static var thisMac: String { tr("settings.thisMac") }
        static var chip: String { tr("settings.chip") }
        static var macOS: String { tr("settings.macOS") }
        static func palette(_ p: AccentPalette) -> String { tr("settings.palette." + p.rawValue) }
    }

    enum Style {
        static var graph: String { tr("style.graph") }
        static var bar: String { tr("style.bar") }
        static var iconValue: String { tr("style.iconValue") }
        static var twoLine: String { tr("style.twoLine") }
        static var ring: String { tr("style.ring") }
        static var arrows: String { tr("style.arrows") }
        static var dots: String { tr("style.dots") }
        static var singleLine: String { tr("style.singleLine") }
        static var iconOnly: String { tr("style.iconOnly") }
        static var readWrite: String { tr("style.readWrite") }
        static var iconPercent: String { tr("style.iconPercent") }
        static var percentOnly: String { tr("style.percentOnly") }
        static var iconTemp: String { tr("style.iconTemp") }
        static var tempOnly: String { tr("style.tempOnly") }
        static var fan: String { tr("style.fan") }
    }

    enum MainMenu {
        static var about: String { tr("mainMenu.about") }
        static var hide: String { tr("mainMenu.hide") }
        static var hideOthers: String { tr("mainMenu.hideOthers") }
        static var edit: String { tr("mainMenu.edit") }
        static var copy: String { tr("mainMenu.copy") }
        static var selectAll: String { tr("mainMenu.selectAll") }
        static var window: String { tr("mainMenu.window") }
        static var minimize: String { tr("mainMenu.minimize") }
        static var close: String { tr("mainMenu.close") }
    }
}
