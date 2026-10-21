import Foundation

/// `Module` inside `L10n` means `L10n.Module`.
typealias AppModule = Module

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
        static var seal: String { tr("app.seal") }
    }

    enum Module {
        static var cpu: String { tr("module.cpu") }
        static var gpu: String { tr("module.gpu") }
        static var memory: String { tr("module.memory") }
        static var network: String { tr("module.network") }
        static var disk: String { tr("module.disk") }
        static var battery: String { tr("module.battery") }
        static var sensors: String { tr("module.sensors") }
        static var bluetooth: String { tr("module.bluetooth") }
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
        static var d30: String { tr("range.d30") }
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
        static var pause: String { tr("sidebar.pause") }
        static var resume: String { tr("sidebar.resume") }
        static var processes: String { tr("sidebar.processes") }
        static var sleep: String { tr("sidebar.sleep") }
        static var aboutMac: String { tr("sidebar.aboutMac") }
        static func turnOffModule(_ a: String) -> String { tr("sidebar.turnOffModule", a) }
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
        static var percentSign: String { tr("common.percentSign") }
        static var wattUnit: String { tr("common.wattUnit") }
        static func watts(_ n: Int) -> String { tr("common.watts", n) }
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
        static func videoDecode(_ a: String) -> String { tr("overview.gpu.videoDecode", a) }
        static func thermal(_ level: Int) -> String { tr("overview.thermal.\(min(max(level, 0), 3))") }
        static var cpuPeaks: String { tr("overview.cpuPeaks") }
        static var diskHealthy: String { tr("overview.diskHealthy") }
        static func cycles(_ a: String) -> String { tr("overview.cycles", a) }
        static var edit: String { tr("overview.edit") }
        static var done: String { tr("overview.done") }
        static var editA11y: String { tr("overview.editA11y") }
        static func moduleSwitch(_ a: String) -> String { tr("overview.moduleSwitch", a) }
        static var allOff: String { tr("overview.allOff") }
        static var localShort: String { tr("overview.localShort") }
        static var publicShort: String { tr("overview.publicShort") }
    }

    enum Battery {
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
        static func deviceCount(_ n: Int) -> String { tr("battery.deviceCount", n) }
        static var noBattery: String { tr("battery.noBattery") }
        static var ups: String { tr("battery.ups") }
        static func upsDetail(_ minutes: Int) -> String { tr("battery.upsDetail", minutes) }
        static var upsOnAC: String { tr("battery.upsOnAC") }
        static var low: String { tr("battery.low") }
        static var lowA11y: String { tr("battery.lowA11y") }
        static var chargingA11y: String { tr("battery.chargingA11y") }
        static func minutesShort(_ a: Int) -> String { tr("battery.minutesShort", a) }
    }

    enum Bluetooth {
        static var noDevices: String { tr("bluetooth.noDevices") }
        static func deviceCount(_ a: Int) -> String { tr("bluetooth.deviceCount", a) }
        static func lowCount(_ a: Int) -> String { tr("bluetooth.lowCount", a) }
        static var disconnected: String { tr("bluetooth.disconnected") }
        static func lastConnected(_ a: String) -> String { tr("bluetooth.lastConnected", a) }
        static var left: String { tr("bluetooth.left") }
        static var right: String { tr("bluetooth.right") }
        static var caseLabel: String { tr("bluetooth.case") }
        static func weeks(_ a: Int) -> String { tr("bluetooth.weeks", a) }
        static func days(_ a: Int) -> String { tr("bluetooth.days", a) }
        static func hours(_ a: Int) -> String { tr("bluetooth.hours", a) }
        static var underHour: String { tr("bluetooth.underHour") }
        static func chartA11y(_ a: String, _ b: String, _ c: String) -> String { tr("bluetooth.chartA11y", a, b, c) }
        static func deviceA11y(_ a: String, _ b: String) -> String { tr("bluetooth.deviceA11y", a, b) }
        static var lowA11y: String { tr("bluetooth.lowA11y") }
        static var device: String { tr("bluetooth.device") }
        static var nameSeparator: String { tr("bluetooth.nameSeparator") }
        static func devicesMore(_ a: String, _ b: Int) -> String { tr("bluetooth.devicesMore", a, b) }
        static var noHistory: String { tr("bluetooth.noHistory") }
        static func daysAgo(_ a: Int) -> String { tr("bluetooth.daysAgo", a) }
    }

    enum Menu {
        static var open: String { tr("menu.open") }
        static var settings: String { tr("menu.settings") }
        static var quit: String { tr("menu.quit") }
    }

    enum A11y {
        static var separator: String { tr("a11y.separator") }
        static var dotSeparator: String { tr("a11y.dotSeparator") }
        static func cpu(_ v: String) -> String { tr("a11y.cpu", v) }
        static func gpu(_ v: String) -> String { tr("a11y.gpu", v) }
        static func memory(_ v: String) -> String { tr("a11y.memory", v) }
        static func network(_ up: String, _ down: String) -> String { tr("a11y.network", up, down) }
        static var networkOffline: String { tr("a11y.networkOffline") }
        static func disk(_ v: String) -> String { tr("a11y.disk", v) }
        static func battery(_ v: String) -> String { tr("a11y.battery", v) }
        static func temperature(_ v: String) -> String { tr("a11y.temperature", v) }
        static func device(_ a: String, _ b: String) -> String { tr("a11y.device", a, b) }
        static func bluetooth(_ a: String) -> String { tr("a11y.bluetooth", a) }
    }

    enum Alerts {
        static var quitAction: String { tr("alerts.quitAction") }
        static func cpuBody(_ v: String, _ duration: String) -> String { tr("alerts.cpu.body", v, duration) }
        static func cpuCulprit(_ name: String, _ v: String) -> String { tr("alerts.cpu.culprit", name, v) }
        static func gpuBody(_ v: String, _ duration: String) -> String { tr("alerts.gpu.body", v, duration) }
        static func gpuCulprit(_ name: String, _ v: String) -> String { tr("alerts.gpu.culprit", name, v) }
        static var memoryBody: String { tr("alerts.memory.body") }
        static func memoryCulprit(_ name: String, _ v: String) -> String { tr("alerts.memory.culprit", name, v) }
        static var diskBody: String { tr("alerts.disk.body") }
        static var batteryBody: String { tr("alerts.battery.body") }
        static var tempBody: String { tr("alerts.temp.body") }
        static var networkBody: String { tr("alerts.network.body") }
        static func seconds(_ n: Int) -> String { tr("alerts.seconds", n) }
        static func minutes(_ n: Int) -> String { tr("alerts.minutes", n) }
        static func bluetoothLowTitle(_ a: String) -> String { tr("alerts.bluetooth.lowTitle", a) }
        static var bluetoothLowBody: String { tr("alerts.bluetooth.lowBody") }
        static func bluetoothDisconnectTitle(_ a: String) -> String { tr("alerts.bluetooth.disconnectTitle", a) }
        static var view: String { tr("alerts.view") }
        static var snooze: String { tr("alerts.snooze") }
        static var sentenceGap: String { tr("alerts.sentenceGap") }
        static func culpritSentence(_ a: String, _ b: String) -> String { tr("alerts.culpritSentence", a, b) }
        static func culpritDetail(_ a: String, _ b: String) -> String { tr("alerts.culpritDetail", a, b) }
        static func cpuHeadline(_ a: String, _ b: String, _ c: String) -> String { tr("alerts.cpuHeadline", a, b, c) }
        static func gpuHeadline(_ a: String, _ b: String, _ c: String) -> String { tr("alerts.gpuHeadline", a, b, c) }
        static func cpuBanner(_ v: String, _ duration: String) -> String { tr("alerts.cpuBanner", v, duration) }
        static func gpuBanner(_ v: String, _ duration: String) -> String { tr("alerts.gpuBanner", v, duration) }
        static var memoryBanner: String { tr("alerts.memoryBanner") }
        static var memoryBannerRed: String { tr("alerts.memoryBannerRed") }
        static func diskBanner(_ name: String, _ v: String) -> String { tr("alerts.diskBanner", name, v) }
        static func batteryBanner(_ v: String) -> String { tr("alerts.batteryBanner", v) }
        static func tempBanner(_ v: String) -> String { tr("alerts.tempBanner", v) }
        static var networkBanner: String { tr("alerts.networkBanner") }
        static func bluetoothLowBanner(_ name: String, _ v: String) -> String { tr("alerts.bluetoothLowBanner", name, v) }
        static func bluetoothDisconnectBanner(_ name: String) -> String { tr("alerts.bluetoothDisconnectBanner", name) }
        static func overYourLimit(_ v: String) -> String { tr("alerts.overYourLimit", v) }
        static func memoryHeadline(_ a: String) -> String { tr("alerts.memoryHeadline", a) }
        static func diskHeadline(_ a: String, _ b: String, _ c: String) -> String { tr("alerts.diskHeadline", a, b, c) }
        static func batteryHeadline(_ a: String, _ b: String) -> String { tr("alerts.batteryHeadline", a, b) }
        static func tempHeadline(_ a: String, _ b: String) -> String { tr("alerts.tempHeadline", a, b) }
        static var networkDown: String { tr("alerts.networkDown") }
        static func networkDownFor(_ a: String) -> String { tr("alerts.networkDownFor", a) }
        static func bluetoothLowHeadline(_ a: String, _ b: String, _ c: String) -> String { tr("alerts.bluetoothLowHeadline", a, b, c) }
        static var recovered: String { tr("alerts.recovered") }
        static func diskRecovered(_ a: String) -> String { tr("alerts.diskRecovered", a) }
        static func untilEmpty(_ a: String) -> String { tr("alerts.untilEmpty", a) }
        static func reconnected(_ a: String) -> String { tr("alerts.reconnected", a) }
        static var reconnectedPlain: String { tr("alerts.reconnectedPlain") }
        static var vpn: String { tr("alerts.vpn") }
        static var pillPressureRed: String { tr("alerts.pillPressureRed") }
        static var pillPressureYellow: String { tr("alerts.pillPressureYellow") }
        static func pillBelow(_ a: String) -> String { tr("alerts.pillBelow", a) }
        static func pillFreeBelow(_ a: String) -> String { tr("alerts.pillFreeBelow", a) }
        static var pillDisconnect: String { tr("alerts.pillDisconnect") }
        static func editA11y(_ a: String) -> String { tr("alerts.editA11y", a) }
        static var edit: String { tr("alerts.edit") }
        static var add: String { tr("alerts.add") }
        static var rules: String { tr("alerts.rules") }
        static func rulesOn(_ a: Int) -> String { tr("alerts.rulesOn", a) }
        static var recent: String { tr("alerts.recent") }
        static func thisWeek(_ a: Int) -> String { tr("alerts.thisWeek", a) }
        static var delivery: String { tr("alerts.delivery") }
        static var enabled: String { tr("alerts.enabled") }
        static var newA11y: String { tr("alerts.newA11y") }
        static func badgeA11y(_ a: Int) -> String { tr("alerts.badgeA11y", a) }
        static var noneYet: String { tr("alerts.noneYet") }
        static func overLimit(_ a: String) -> String { tr("alerts.overLimit", a) }
        static var rulesRow: String { tr("alerts.rulesRow") }
        static var rulesOff: String { tr("alerts.rulesOff") }
        static func ruleOn(_ a: String) -> String { tr("alerts.ruleOn", a) }
        static func rulesOnCount(_ a: Int) -> String { tr("alerts.rulesOnCount", a) }
        static func openRulesA11y(_ a: String) -> String { tr("alerts.openRulesA11y", a) }
        static var moduleOff: String { tr("alerts.moduleOff") }
    }

    enum Panel {
        static var untilFullLabel: String { tr("panel.untilFullLabel") }
        static var timeLeftLabel: String { tr("panel.timeLeftLabel") }
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
        static func ofTotal(_ v: String) -> String { tr("panel.ofTotal", v) }
        static func readWriteShort(_ r: String, _ w: String) -> String { tr("panel.readWriteShort", r, w) }
        static var health: String { tr("panel.health") }
        static func healthValue(_ a: String, _ b: String) -> String { tr("panel.healthValue", a, b) }
        static func volumeUsedPurgeable(_ a: String, _ b: String, _ c: String) -> String { tr("panel.volumeUsedPurgeable", a, b, c) }
        static var passiveCooling: String { tr("panel.passiveCooling") }
        static func fanCount(_ n: Int) -> String { tr("panel.fanCount", n) }
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
        static func downUpCompact(_ down: String, _ up: String) -> String { tr("network.downUpCompact", down, up) }
        static var localIP: String { tr("network.localIP") }
        static var router: String { tr("network.router") }
        static var publicIP: String { tr("network.publicIP") }
        static var lastConnected: String { tr("network.lastConnected") }
        static var today: String { tr("network.today") }
        static var session: String { tr("network.session") }
        static var interface: String { tr("network.interface") }
        static func downUp(_ d: String, _ u: String) -> String { tr("network.downUp", d, u) }
        static func ipVia(_ a: String, _ b: String) -> String { tr("network.ipVia", a, b) }
    }

    enum Disk {
        static func unitFree(_ unit: String) -> String { tr("disk.unitFree", unit) }
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
        static var internalDrive: String { tr("disk.internal") }
    }

    enum Monitor {
        static var degreeCPUAverage: String { tr("monitor.degreeCPUAverage") }
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
        static var activeState: String { tr("monitor.active") }
        static var idleState: String { tr("monitor.idleState") }
        static var idle: String { tr("monitor.idle") }
        static var adapter: String { tr("monitor.adapter") }
        static var allCores: String { tr("monitor.allCores") }
        static var performanceCores: String { tr("monitor.performanceCores") }
        static var efficiencyCores: String { tr("monitor.efficiencyCores") }
        static func averageMax(_ a: String, _ b: String) -> String { tr("monitor.averageMax", a, b) }
        static func batteryChartA11y(_ a: String) -> String { tr("monitor.batteryChartA11y", a) }
        static var batteryHealth: String { tr("monitor.batteryHealth") }
        static var capacity: String { tr("monitor.capacity") }
        static func capacityValue(_ a: String, _ b: String) -> String { tr("monitor.capacityValue", a, b) }
        static var chargePower: String { tr("monitor.chargePower") }
        static var chargingLegend: String { tr("monitor.chargingLegend") }
        static func checksA11y(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> String { tr("monitor.checksA11y", a, b, c, d) }
        static var connection: String { tr("monitor.connection") }
        static var connectionLog: String { tr("monitor.connectionLog") }
        static func coreGroup(_ a: Int) -> String { tr("monitor.coreGroup", a) }
        static func performanceGroup(_ a: Int) -> String { tr("monitor.performanceGroup", a) }
        static func efficiencyGroup(_ a: Int) -> String { tr("monitor.efficiencyGroup", a) }
        static func coreTotal(_ a: Int) -> String { tr("monitor.coreTotal", a) }
        static func coresA11y(_ a: String, _ b: String) -> String { tr("monitor.coresA11y", a, b) }
        static func cpuAverageMax(_ a: String) -> String { tr("monitor.cpuAverageMax", a) }
        static func cyclesOf(_ a: Int, _ b: Int) -> String { tr("monitor.cyclesOf", a, b) }
        static func diskHealth(_ a: String) -> String { tr("monitor.diskHealth", a) }
        static var fanAuto: String { tr("monitor.fanAuto") }
        static var fanManual: String { tr("monitor.fanManual") }
        static func fanRange(_ a: Int, _ b: Int) -> String { tr("monitor.fanRange", a, b) }
        static var fps: String { tr("monitor.fps") }
        static var frameRate: String { tr("monitor.frameRate") }
        static var frequencyGHz: String { tr("monitor.frequencyGHz") }
        static func gpuCores(_ a: Int) -> String { tr("monitor.gpuCores", a) }
        static var headroom: String { tr("monitor.headroom") }
        static var healthNormal: String { tr("monitor.healthNormal") }
        static var healthService: String { tr("monitor.healthService") }
        static var latency: String { tr("monitor.latency") }
        static var lifeRemaining: String { tr("monitor.lifeRemaining") }
        static func localIP(_ a: String) -> String { tr("monitor.localIP", a) }
        static func router(_ a: String) -> String { tr("monitor.router", a) }
        static var memoryPressure: String { tr("monitor.memoryPressure") }
        static func milliseconds(_ a: Int) -> String { tr("monitor.milliseconds", a) }
        static func ofTotal(_ a: String) -> String { tr("monitor.ofTotal", a) }
        static var other: String { tr("monitor.other") }
        static var peak24h: String { tr("monitor.peak24h") }
        static var powerSource: String { tr("monitor.powerSource") }
        static func powerValue(_ a: String) -> String { tr("monitor.powerValue", a) }
        static var proMotion: String { tr("monitor.proMotion") }
        static func processThreads(_ a: String, _ b: String) -> String { tr("monitor.processThreads", a, b) }
        static func readRate(_ a: String) -> String { tr("monitor.readRate", a) }
        static func writeRate(_ a: String) -> String { tr("monitor.writeRate", a) }
        static var renderer: String { tr("monitor.renderer") }
        static var tiler: String { tr("monitor.tiler") }
        static func sessionToday(_ a: String, _ b: String) -> String { tr("monitor.sessionToday", a, b) }
        static var smartGood: String { tr("monitor.smartGood") }
        static var smartFailing: String { tr("monitor.smartFailing") }
        static func swapFile(_ a: String) -> String { tr("monitor.swapFile", a) }
        static var systemDraw: String { tr("monitor.systemDraw") }
        static var totalWritten: String { tr("monitor.totalWritten") }
        static func usedOfTotal(_ a: String, _ b: String) -> String { tr("monitor.usedOfTotal", a, b) }
        static var videoDecode: String { tr("monitor.videoDecode") }
        static var videoEncode: String { tr("monitor.videoEncode") }
        static func volumeUsed(_ a: String, _ b: String) -> String { tr("monitor.volumeUsed", a, b) }
        static func volumeUsedPurgeable(_ a: String, _ b: String, _ c: String) -> String { tr("monitor.volumeUsedPurgeable", a, b, c) }
        static var vramUnified: String { tr("monitor.vramUnified") }
        static func zoneLow(_ a: String) -> String { tr("monitor.zoneLow", a) }
        static func zoneMid(_ a: String, _ b: String) -> String { tr("monitor.zoneMid", a, b) }
        static func zoneHigh(_ a: String) -> String { tr("monitor.zoneHigh", a) }
        static func usedSlashLimit(_ a: String, _ b: String) -> String { tr("monitor.usedSlashLimit", a, b) }
        static func thermalLevel(_ level: Int) -> String { tr("monitor.thermalLevel.\(min(max(level, 0), 3))") }
        static func pCoreTip(_ a: Int, _ b: String, _ c: String) -> String { tr("monitor.pCoreTip", a, b, c) }
        static func eCoreTip(_ a: Int, _ b: String, _ c: String) -> String { tr("monitor.eCoreTip", a, b, c) }
        static func coreTip(_ a: Int, _ b: String, _ c: String) -> String { tr("monitor.coreTip", a, b, c) }
        static func cyclesLimit(_ a: Int) -> String { tr("monitor.cyclesLimit", a) }
        static func publicIP(_ a: String) -> String { tr("monitor.publicIP", a) }
    }

    enum Settings {
        static var startup: String { tr("settings.startup") }
        static var launchAtLogin: String { tr("settings.launchAtLogin") }
        static var loginItemNeedsApproval: String { tr("settings.loginItemNeedsApproval") }
        static var openLoginItems: String { tr("settings.openLoginItems") }
        static var appearance: String { tr("settings.appearance") }
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
        static var speedUnit: String { tr("settings.speedUnit") }
        static var unitBytes: String { tr("settings.unitBytes") }
        static var unitBits: String { tr("settings.unitBits") }
        static var diskContent: String { tr("settings.diskContent") }
        static var freeSpace: String { tr("settings.freeSpace") }
        static var usedPercent: String { tr("settings.usedPercent") }
        static var readWrite: String { tr("settings.readWrite") }
        static var whichDisk: String { tr("settings.whichDisk") }
        static var startupDisk: String { tr("settings.startupDisk") }
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
        static var celsius: String { tr("settings.celsius") }
        static var fahrenheit: String { tr("settings.fahrenheit") }
        static var updates: String { tr("settings.updates") }
        static var autoCheckUpdates: String { tr("settings.autoCheckUpdates") }
        static var currentVersion: String { tr("settings.currentVersion") }
        static var checkForUpdates: String { tr("settings.checkForUpdates") }
        static var checkingUpdates: String { tr("settings.checkingUpdates") }
        static var upToDate: String { tr("settings.upToDate") }
        static var checkFailed: String { tr("settings.checkFailed") }
        static func downloadVersion(_ v: String) -> String { tr("settings.downloadVersion", v) }
        static var breadcrumb: String { tr("settings.breadcrumb") }
        static var networkInterface: String { tr("settings.networkInterface") }
        static func autoWith(_ v: String) -> String { tr("settings.autoWith", v) }
        static func interfaceOption(_ kind: String, _ name: String) -> String { tr("settings.interfaceOption", kind, name) }
        static var ruleCPUSwitch: String { tr("settings.ruleCPUSwitch") }
        static var ruleMemorySwitch: String { tr("settings.ruleMemorySwitch") }
        static var ruleDiskSwitch: String { tr("settings.ruleDiskSwitch") }
        static var ruleBatterySwitch: String { tr("settings.ruleBatterySwitch") }
        static var ruleTempSwitch: String { tr("settings.ruleTempSwitch") }
        static var ruleNetworkSwitch: String { tr("settings.ruleNetworkSwitch") }
        static var banner: String { tr("settings.banner") }
        static var alertStyle: String { tr("settings.alertStyle") }
        static func gigabytes(_ n: Int) -> String { tr("settings.gigabytes", n) }
        static func moduleSettings(_ a: String) -> String { tr("settings.moduleSettings", a) }
        static var processRefresh: String { tr("settings.processRefresh") }
        static var ruleGPU: String { tr("settings.ruleGPU") }
        static var ruleGPUSwitch: String { tr("settings.ruleGPUSwitch") }
        static var showBatteryTemperature: String { tr("settings.showBatteryTemperature") }
        static var showDiskHealth: String { tr("settings.showDiskHealth") }
        static var showLatency: String { tr("settings.showLatency") }
        static var showThermal: String { tr("settings.showThermal") }
        static var showVideo: String { tr("settings.showVideo") }
        static var tabModule: String { tr("settings.tabModule") }
        static var tabPanel: String { tr("settings.tabPanel") }
        static var tabWidgets: String { tr("settings.tabWidgets") }
        static var tabsA11y: String { tr("settings.tabsA11y") }
        static var timeFormat: String { tr("settings.timeFormat") }
        static var widgetStripA11y: String { tr("settings.widgetStripA11y") }
        static func moduleMonitor(_ a: String) -> String { tr("settings.moduleMonitor", a) }
        static func moduleViews(_ a: String) -> String { tr("settings.moduleViews", a) }
        static var noWidgets: String { tr("settings.noWidgets") }
        static var modulesInMenubar: String { tr("settings.modulesInMenubar") }
        static func blockedChip(_ a: String) -> String { tr("settings.blockedChip", a) }
        static var moduleSpacing: String { tr("settings.moduleSpacing") }
        static var systemSpacing: String { tr("settings.systemSpacing") }
        static var spacingStandard: String { tr("settings.spacingStandard") }
        static var spacingCompact: String { tr("settings.spacingCompact") }
        static var spacingTightest: String { tr("settings.spacingTightest") }
        static var barFont: String { tr("settings.barFont") }
        static var fontSystem: String { tr("settings.fontSystem") }
        static var fontMonospaced: String { tr("settings.fontMonospaced") }
        static func points(_ a: Int) -> String { tr("settings.points", a) }
        static func decrease(_ a: String) -> String { tr("settings.decrease", a) }
        static func increase(_ a: String) -> String { tr("settings.increase", a) }
        static var widgetGap: String { tr("settings.widgetGap") }
        static var lowLevel: String { tr("settings.lowLevel") }
        static func lowLevelValue(_ a: Int) -> String { tr("settings.lowLevelValue", a) }
        static func minutes(_ a: Int) -> String { tr("settings.minutes", a) }
        static var showBuds: String { tr("settings.showBuds") }
        static var showDisconnected: String { tr("settings.showDisconnected") }
        static var showHistory: String { tr("settings.showHistory") }
        static var bluetoothLowAlert: String { tr("settings.bluetoothLowAlert") }
        static var bluetoothLowAlertA11y: String { tr("settings.bluetoothLowAlertA11y") }
        static var bluetoothDisconnectAlert: String { tr("settings.bluetoothDisconnectAlert") }
        static var bluetoothDisconnectAlertA11y: String { tr("settings.bluetoothDisconnectAlertA11y") }
        static func percentValue(_ a: Int) -> String { tr("settings.percentValue", a) }
        static var modulesGroup: String { tr("settings.modulesGroup") }
        static var modulesOn: String { tr("settings.modulesOn") }
        static var combinedIconOnly: String { tr("settings.combinedIconOnly") }
        static var combinedIcon: String { tr("settings.combinedIcon") }
        static var iconAvatar: String { tr("settings.icon.avatar") }
        static var iconGauge: String { tr("settings.icon.gauge") }
        static var iconPulse: String { tr("settings.icon.pulse") }
        static var iconChart: String { tr("settings.icon.chart") }
        static var iconChip: String { tr("settings.icon.chip") }
        static var iconRunner: String { tr("settings.icon.runner") }
    }

    enum Notch {
        static var title: String { tr("notch.title") }
        static func hiddenCount(_ n: Int) -> String { tr("notch.hiddenCount", n) }
        static var merge: String { tr("notch.merge") }
        static var dontRemind: String { tr("notch.dontRemind") }
        static var openSettings: String { tr("notch.openSettings") }
        static var blocked: String { tr("notch.blocked") }
    }

    /// What she says while something runs high.
    enum Mood {
        static var cpu: String { tr("mood.cpu") }
        static var gpu: String { tr("mood.gpu") }
        static var memory: String { tr("mood.memory") }
        static var network: String { tr("mood.network") }
        static var disk: String { tr("mood.disk") }
        static var battery: String { tr("mood.battery") }
        static var bluetooth: String { tr("mood.bluetooth") }
        static var sensors: String { tr("mood.sensors") }
    }

    enum Onboarding {
        static var title: String { tr("onboarding.title") }
        static var greeting: String { tr("onboarding.greeting") }
        static var intro: String { tr("onboarding.intro") }
        static var done: String { tr("onboarding.done") }
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

    enum Runner {
        static var equalizer: String { tr("runner.equalizer") }
        static var character: String { tr("runner.character") }
        static var library: String { tr("runner.library") }
        static var importEllipsis: String { tr("runner.import") }
        static var delete: String { tr("runner.delete") }
        static var importA11y: String { tr("runner.importA11y") }
        static var importFailed: String { tr("runner.importFailed") }
        static var noImages: String { tr("runner.error.noImages") }
        static func tooManyFrames(_ a: Int) -> String { tr("runner.error.tooManyFrames", a) }
        static var unreadable: String { tr("runner.error.unreadable") }
        static var girl: String { tr("runner.girl") }
        static var cat: String { tr("runner.cat") }
    }

    enum Widget {
        static var align: String { tr("widget.align") }
        static var alignLeading: String { tr("widget.alignLeading") }
        static var alignCenter: String { tr("widget.alignCenter") }
        static var alignTrailing: String { tr("widget.alignTrailing") }
        static var arrows: String { tr("widget.arrows") }
        static var dots: String { tr("widget.dots") }
        static var boxed: String { tr("widget.boxed") }
        static var connected: String { tr("widget.connected") }
        static var disconnected: String { tr("widget.disconnected") }
        static var detailsContent: String { tr("widget.detailsContent") }
        static var downloadColor: String { tr("widget.downloadColor") }
        static var uploadColor: String { tr("widget.uploadColor") }
        static var readColor: String { tr("widget.readColor") }
        static var writeColor: String { tr("widget.writeColor") }
        static var fanValue: String { tr("widget.fanValue") }
        static var rpm: String { tr("widget.rpm") }
        static var freeOnTop: String { tr("widget.freeOnTop") }
        static var hidePercentWhenFull: String { tr("widget.hidePercentWhenFull") }
        static var icon: String { tr("widget.icon") }
        static var label: String { tr("widget.label") }
        static var labelText: String { tr("widget.labelText") }
        static var monochrome: String { tr("widget.monochrome") }
        static var monospaced: String { tr("widget.monospaced") }
        static var percentAndTime: String { tr("widget.percentAndTime") }
        static var percentOnly: String { tr("widget.percentOnly") }
        static var timeOnly: String { tr("widget.timeOnly") }
        static var points: String { tr("widget.points") }
        static var readTop: String { tr("widget.readTop") }
        static var writeTop: String { tr("widget.writeTop") }
        static var showIcon: String { tr("widget.showIcon") }
        static var showSymbol: String { tr("widget.showSymbol") }
        static var singleLine: String { tr("widget.singleLine") }
        static var twoLine: String { tr("widget.twoLine") }
        static func byValue(_ m: AppModule) -> String {
            switch m {
            case .memory: return tr("widget.byPressure")
            case .battery: return tr("widget.byLevel")
            case .sensors: return tr("widget.byTemperature")
            case .bluetooth: return tr("widget.byLevel")
            default: return tr("widget.byUsage")
            }
        }
        /// A widget's name; the pick sheet names some per module ("每核心竖条", "温度竖条").
        static func name(_ kind: WidgetKind, _ m: AppModule) -> String {
            let specific = "widget.name.\(m.rawValue).\(kind.rawValue)"
            let named = tr(specific)
            if named != specific { return named }
            switch (kind, m) {
            case (.bar, .memory), (.bar, .disk): return tr("widget.name.barPlain")
            case (.speed, .disk): return tr("widget.name.readWrite")
            case (.chart, .disk): return tr("widget.name.diskChart")
            default: return tr("widget.name.\(kind.rawValue)")
            }
        }
        static func palette(_ p: PaletteColor) -> String { tr("widget.palette.\(p.rawValue)") }
        static func iconName(_ m: AppModule, _ index: Int) -> String { tr("widget.icon.\(m.rawValue).\(index)") }
        static var order: String { tr("widget.order") }
        static var uploadFirst: String { tr("widget.uploadFirst") }
        static var downloadFirst: String { tr("widget.downloadFirst") }
        static var iconStyle: String { tr("widget.iconStyle") }
        static var iconStyleA11y: String { tr("widget.iconStyleA11y") }
        static var triangles: String { tr("widget.triangles") }
        static var letters: String { tr("widget.letters") }
        static var position: String { tr("widget.position") }
        static var positionA11y: String { tr("widget.positionA11y") }
        static var beforeNumber: String { tr("widget.beforeNumber") }
        static var afterNumber: String { tr("widget.afterNumber") }
        static var gap: String { tr("widget.gap") }
        static var gapA11y: String { tr("widget.gapA11y") }
        static var numbers: String { tr("widget.numbers") }
        static var unitStyle: String { tr("widget.unitStyle") }
        static var unitPerSecond: String { tr("widget.unitPerSecond") }
        static var unitBytes: String { tr("widget.unitBytes") }
        static var unitLetter: String { tr("widget.unitLetter") }
        static var fixedWidth: String { tr("widget.fixedWidth") }
        static var uploadLetter: String { tr("widget.uploadLetter") }
        static var downloadLetter: String { tr("widget.downloadLetter") }
        static var shownDevices: String { tr("widget.shownDevices") }
        static var autoDevices: String { tr("widget.autoDevices") }
        static var showDeviceIcon: String { tr("widget.showDeviceIcon") }
        static var redWhenLow: String { tr("widget.redWhenLow") }
        static var hideWhenFine: String { tr("widget.hideWhenFine") }
        static var iconRedWhenLow: String { tr("widget.iconRedWhenLow") }
    }

    enum Processes {
        static var viewAll: String { tr("processes.viewAll") }
        static var viewAllA11y: String { tr("processes.viewAllA11y") }
        static var search: String { tr("processes.search") }
        static var filterLabel: String { tr("processes.filterLabel") }
        static var filterAll: String { tr("processes.filterAll") }
        static var filterApps: String { tr("processes.filterApps") }
        static var filterMine: String { tr("processes.filterMine") }
        static var filterSystem: String { tr("processes.filterSystem") }
        static var name: String { tr("processes.name") }
        static var energy: String { tr("processes.energy") }
        static var listLabel: String { tr("processes.listLabel") }
        static var inspector: String { tr("processes.inspector") }
        static var closeInspector: String { tr("processes.closeInspector") }
        static func pidUser(_ a: String, _ b: String) -> String { tr("processes.pidUser", a, b) }
        static var systemProcess: String { tr("processes.systemProcess") }
        static var details: String { tr("processes.details") }
        static var cpuTime: String { tr("processes.cpuTime") }
        static var threads: String { tr("processes.threads") }
        static var diskReadWrite: String { tr("processes.diskReadWrite") }
        static var networkInOut: String { tr("processes.networkInOut") }
        static var started: String { tr("processes.started") }
        static var relations: String { tr("processes.relations") }
        static var parent: String { tr("processes.parent") }
        static var children: String { tr("processes.children") }
        static func childGroup(_ a: String, _ b: Int) -> String { tr("processes.childGroup", a, b) }
        static func childMore(_ a: String, _ b: Int) -> String { tr("processes.childMore", a, b) }
        static func sortedBy(_ a: String) -> String { tr("processes.sortedBy", a) }
        static var topEnergy: String { tr("processes.topEnergy") }
        static func wholeMac(_ a: String) -> String { tr("processes.wholeMac", a) }
    }

    enum Sleep {
        static var keepAwake: String { tr("sleep.keepAwake") }
        static var awake: String { tr("sleep.awake") }
        static var remaining: String { tr("sleep.remaining") }
        static var untilOff: String { tr("sleep.untilOff") }
        static func endsAt(_ a: String) -> String { tr("sleep.endsAt", a) }
        static var endsUnplugged: String { tr("sleep.endsUnplugged") }
        static var turnOff: String { tr("sleep.turnOff") }
        static var turnOn: String { tr("sleep.turnOn") }
        static var offTitle: String { tr("sleep.offTitle") }
        static var offSub: String { tr("sleep.offSub") }
        static var modesLabel: String { tr("sleep.modesLabel") }
        static var modeIndefinite: String { tr("sleep.modeIndefinite") }
        static func modeMinutes(_ a: Int) -> String { tr("sleep.modeMinutes", a) }
        static var modeHour: String { tr("sleep.modeHour") }
        static func modeUntil(_ a: String) -> String { tr("sleep.modeUntil", a) }
        static var modeCharging: String { tr("sleep.modeCharging") }
        static var modeCustom: String { tr("sleep.modeCustom") }
        static var customUntil: String { tr("sleep.customUntil") }
        static var start: String { tr("sleep.start") }
        static var keepDisplay: String { tr("sleep.keepDisplay") }
        static func lowBattery(_ a: String) -> String { tr("sleep.lowBattery", a) }
        static var blockers: String { tr("sleep.blockers") }
        static var preventsSystem: String { tr("sleep.preventsSystem") }
        static var preventsDisplay: String { tr("sleep.preventsDisplay") }
        static var open: String { tr("sleep.open") }
        static func openNamed(_ a: String) -> String { tr("sleep.openNamed", a) }
        static var macOS: String { tr("sleep.macOS") }
        static var playingAudio: String { tr("sleep.playingAudio") }
        static var playingVideo: String { tr("sleep.playingVideo") }
        static var nothing: String { tr("sleep.nothing") }
        static func hoursMinutes(_ a: Int, _ b: Int) -> String { tr("sleep.hoursMinutes", a, b) }
        static func minutes(_ a: Int) -> String { tr("sleep.minutes", a) }
        static var underMinute: String { tr("sleep.underMinute") }
        static func daysHours(_ a: Int, _ b: Int) -> String { tr("sleep.daysHours", a, b) }
    }

    enum About {
        static var copy: String { tr("about.copy") }
        static var copied: String { tr("about.copied") }
        static var copyA11y: String { tr("about.copyA11y") }
        static func inches(_ a: String) -> String { tr("about.inches", a) }
        static func year(_ a: String) -> String { tr("about.year", a) }
        static func macOS(_ a: String) -> String { tr("about.macOS", a) }
        static var hardware: String { tr("about.hardware") }
        static var software: String { tr("about.software") }
        static var storage: String { tr("about.storage") }
        static var chip: String { tr("about.chip") }
        static var memory: String { tr("about.memory") }
        static var display: String { tr("about.display") }
        static var modelID: String { tr("about.modelID") }
        static var system: String { tr("about.system") }
        static var build: String { tr("about.build") }
        static var kernel: String { tr("about.kernel") }
        static var computerName: String { tr("about.computerName") }
        static var booted: String { tr("about.booted") }
        static var architecture: String { tr("about.architecture") }
        static var appleSilicon: String { tr("about.appleSilicon") }
        static var intel: String { tr("about.intel") }
        static func cpuCores(_ a: Int, _ b: Int, _ c: Int) -> String { tr("about.cpuCores", a, b, c) }
        static func cores(_ a: Int) -> String { tr("about.cores", a) }
        static func displayValue(_ a: String, _ b: Int, _ c: Int) -> String { tr("about.displayValue", a, b, c) }
        static func resolution(_ a: Int, _ b: Int) -> String { tr("about.resolution", a, b) }
        static func volume(_ a: String, _ b: String) -> String { tr("about.volume", a, b) }
        static func copyLine(_ a: String, _ b: String) -> String { tr("about.copyLine", a, b) }
    }
}
