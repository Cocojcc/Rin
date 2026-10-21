import Foundation

enum Metric: Int, CaseIterable, Codable {
    case cpu, cpuUser, cpuSystem, gpu, memory, memoryPressure, swap
    case netDown, netUp, diskRead, diskWrite, battery
    case cpuTemp, gpuTemp, fan, power
    case charging, gpuRenderer, gpuTiler, videoDecode, videoEncode, fps
}

enum TimeRange: String, CaseIterable, Identifiable {
    case m5, m30, h1, h24, d7

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .m5: return 300
        case .m30: return 1800
        case .h1: return 3600
        case .h24: return 86_400
        case .d7: return 604_800
        }
    }

    var title: String {
        switch self {
        case .m5: return L10n.Range.m5
        case .m30: return L10n.Range.m30
        case .h1: return L10n.Range.h1
        case .h24: return L10n.Range.h24
        case .d7: return L10n.Range.d7
        }
    }
}

struct ChartPoint: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Aggregated history bucket (one minute or five minutes).
struct HistoryBucket: Codable {
    var start: TimeInterval
    var avg: [Float]
    var max: [Float]
    /// Busiest processes at the bucket's highest CPU sample, for the peak lookback.
    var top: [PeakProcess]
}

struct PeakMarker: Identifiable, Equatable {
    var date: Date
    var value: Double
    var top: [PeakProcess]
    var id: Date { date }
}

/// Raw samples for the short ranges plus minute / five-minute buckets for 24 h and 7 days.
/// Buckets persist across launches; raw samples are memory only.
final class History {
    private static let rawCapacity = 3600
    private static let minuteCapacity = 1440
    private static let fiveCapacity = 2016
    private let metricCount = Metric.allCases.count

    private var rawDates: [Date] = []
    private var raw: [[Float]]
    private(set) var minutes: [HistoryBucket] = []
    private(set) var fives: [HistoryBucket] = []

    private var minuteAcc = Accumulator(span: 60)
    private var fiveAcc = Accumulator(span: 300)
    private var lastSave = Date()

    private struct Accumulator {
        let span: TimeInterval
        var start: TimeInterval = 0
        /// Samples in the bucket, and per metric how many were read: a module that wasn't read
        /// for part of the bucket (switched off, or only watched while a view was open) leaves
        /// those samples out instead of counting them as zero.
        var count = 0
        var counts: [Int] = []
        var sum: [Double] = []
        var max: [Float] = []
        var topCPU: Float = -1
        var top: [PeakProcess] = []

        mutating func reset(at start: TimeInterval, metrics: Int) {
            self.start = start
            count = 0
            counts = [Int](repeating: 0, count: metrics)
            sum = [Double](repeating: 0, count: metrics)
            max = [Float](repeating: -.greatestFiniteMagnitude, count: metrics)
            topCPU = -1
            top = []
        }

        /// A metric with no reading in the bucket is NaN in both, a gap in the charts.
        func bucket() -> HistoryBucket {
            HistoryBucket(start: start,
                          avg: sum.indices.map { counts[$0] > 0 ? Float(sum[$0] / Double(counts[$0])) : .nan },
                          max: max.indices.map { counts[$0] > 0 ? max[$0] : .nan },
                          top: top)
        }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.plist")
    }

    private struct Stored: Codable {
        var minutes: [HistoryBucket]
        var fives: [HistoryBucket]
    }

    init() {
        raw = [[Float]](repeating: [], count: Metric.allCases.count)
        load()
    }

    // MARK: Recording

    func record(_ s: Snapshot) {
        var values = [Float](repeating: .nan, count: metricCount)
        // Modules switched off record nothing, so their charts show a gap rather than zeros.
        let on = s.monitored.contains
        if on(.cpu) {
            values[Metric.cpu.rawValue] = Float(s.cpu.total * 100)
            values[Metric.cpuUser.rawValue] = Float(s.cpu.user * 100)
            values[Metric.cpuSystem.rawValue] = Float(s.cpu.system * 100)
        }
        if on(.gpu) {
            values[Metric.gpu.rawValue] = Float(s.gpu.utilization * 100)
            if let v = s.gpu.renderer { values[Metric.gpuRenderer.rawValue] = Float(v * 100) }
            if let v = s.gpu.tiler { values[Metric.gpuTiler.rawValue] = Float(v * 100) }
            if let v = s.gpu.decodeWatts { values[Metric.videoDecode.rawValue] = Float(v) }
            if let v = s.gpu.encodeWatts { values[Metric.videoEncode.rawValue] = Float(v) }
            if let v = s.gpu.fps { values[Metric.fps.rawValue] = Float(v) }
        }
        if on(.memory) {
            values[Metric.memory.rawValue] = Float(s.memory.usedFraction * 100)
            values[Metric.memoryPressure.rawValue] = Float(s.memory.pressureLevel * 100)
            values[Metric.swap.rawValue] = Float(Double(s.memory.swapUsed) / 1_073_741_824)
        }
        if on(.network) {
            values[Metric.netDown.rawValue] = Float(s.network.down)
            values[Metric.netUp.rawValue] = Float(s.network.up)
        }
        if on(.disk) {
            values[Metric.diskRead.rawValue] = Float(s.disk.read)
            values[Metric.diskWrite.rawValue] = Float(s.disk.write)
        }
        if on(.battery), s.battery.hasBattery {
            values[Metric.battery.rawValue] = Float(s.battery.level * 100)
            values[Metric.charging.rawValue] = s.battery.isCharging ? 1 : 0
        }
        if on(.sensors) {
            if let t = s.sensors.cpuAverage { values[Metric.cpuTemp.rawValue] = Float(t) }
            if let t = s.sensors.value(.gpu) { values[Metric.gpuTemp.rawValue] = Float(t) }
            if let f = s.sensors.fans.first { values[Metric.fan.rawValue] = Float(f.rpm) }
            if let p = s.sensors.systemPower { values[Metric.power.rawValue] = Float(p) }
        }

        rawDates.append(s.date)
        for i in 0..<metricCount { raw[i].append(values[i]) }
        if rawDates.count > Self.rawCapacity {
            let drop = rawDates.count - Self.rawCapacity
            rawDates.removeFirst(drop)
            for i in 0..<metricCount { raw[i].removeFirst(drop) }
        }

        let t = s.date.timeIntervalSince1970
        accumulate(&minuteAcc, values: values, t: t, top: s.topCPUNow) { minutes.append($0); trim(&minutes, Self.minuteCapacity) }
        accumulate(&fiveAcc, values: values, t: t, top: s.topCPUNow) { fives.append($0); trim(&fives, Self.fiveCapacity) }

        if s.date.timeIntervalSince(lastSave) > 300 { save() }
    }

    private func trim(_ list: inout [HistoryBucket], _ capacity: Int) {
        if list.count > capacity { list.removeFirst(list.count - capacity) }
    }

    private func accumulate(_ acc: inout Accumulator, values: [Float], t: TimeInterval, top: [PeakProcess], emit: (HistoryBucket) -> Void) {
        let start = (t / acc.span).rounded(.down) * acc.span
        if acc.sum.isEmpty { acc.reset(at: start, metrics: metricCount) }
        if start != acc.start {
            if acc.count > 0 { emit(acc.bucket()) }
            acc.reset(at: start, metrics: metricCount)
        }
        acc.count += 1
        for i in 0..<metricCount where !values[i].isNaN {
            acc.counts[i] += 1
            acc.sum[i] += Double(values[i])
            acc.max[i] = Swift.max(acc.max[i], values[i])
        }
        let cpu = values[Metric.cpu.rawValue]
        if cpu > acc.topCPU {
            acc.topCPU = cpu
            acc.top = top
        }
    }

    // MARK: Queries

    /// Points for a chart, at most ~`maxPoints` (raw ranges are averaged down when dense).
    func points(_ metric: Metric, range: TimeRange, now: Date = Date(), maxPoints: Int = 300) -> [ChartPoint] {
        let from = now.addingTimeInterval(-range.seconds)
        switch range {
        case .m5, .m30, .h1:
            guard let first = rawDates.firstIndex(where: { $0 >= from }) else { return [] }
            let series = raw[metric.rawValue]
            let count = rawDates.count - first
            let stride = Swift.max(1, count / maxPoints)
            var result: [ChartPoint] = []
            result.reserveCapacity(count / stride + 1)
            var i = first
            while i < rawDates.count {
                let end = Swift.min(i + stride, rawDates.count)
                var sum: Float = 0, n: Float = 0
                for j in i..<end where !series[j].isNaN { sum += series[j]; n += 1 }
                if n > 0 { result.append(ChartPoint(date: rawDates[i], value: Double(sum / n))) }
                i = end
            }
            return result
        case .h24, .d7:
            let list = range == .h24 ? minutes + [minuteAcc.bucket()].filter { _ in minuteAcc.count > 0 }
                                     : fives + [fiveAcc.bucket()].filter { _ in fiveAcc.count > 0 }
            return list.filter { $0.start >= from.timeIntervalSince1970 && !$0.avg[metric.rawValue].isNaN }.map {
                ChartPoint(date: Date(timeIntervalSince1970: $0.start), value: Double($0.avg[metric.rawValue]))
            }
        }
    }

    /// The most recent `count` samples, oldest first.
    func last(_ metric: Metric, count: Int) -> [Double] {
        raw[metric.rawValue].suffix(count).filter { !$0.isNaN }.map(Double.init)
    }

    func latest(_ metric: Metric, seconds: TimeInterval, now: Date = Date()) -> [Double] {
        let from = now.addingTimeInterval(-seconds)
        guard let first = rawDates.firstIndex(where: { $0 >= from }) else { return [] }
        // Unread samples are left out, so a sparkline starts where the readings do.
        return raw[metric.rawValue][first...].filter { !$0.isNaN }.map(Double.init)
    }

    /// Highest point inside a range (raw or bucketed), for "峰值" summaries.
    func maximum(_ metric: Metric, range: TimeRange, now: Date = Date()) -> Double? {
        points(metric, range: range, now: now, maxPoints: 100_000).map(\.value).max()
    }

    /// Up to `limit` well-separated CPU peaks in the last 24 hours, highest first.
    func cpuPeaks(limit: Int = 3, minimum: Double = 40, separation: TimeInterval = 1800, now: Date = Date()) -> [PeakMarker] {
        let from = now.timeIntervalSince1970 - 86_400
        var candidates = minutes.filter { $0.start >= from }
        if minuteAcc.count > 0 { candidates.append(minuteAcc.bucket()) }
        let cpu = Metric.cpu.rawValue
        let sorted = candidates.filter { !$0.max[cpu].isNaN }.sorted { $0.max[cpu] > $1.max[cpu] }
        var picked: [PeakMarker] = []
        for b in sorted {
            let v = Double(b.max[cpu])
            guard v >= minimum else { break }
            if picked.contains(where: { abs($0.date.timeIntervalSince1970 - b.start) < separation }) { continue }
            picked.append(PeakMarker(date: Date(timeIntervalSince1970: b.start), value: v, top: b.top))
            if picked.count == limit { break }
        }
        return picked
    }

    /// The minute bucket nearest to `date` (for hovering the 24 h chart).
    func bucket(near date: Date) -> HistoryBucket? {
        let t = date.timeIntervalSince1970
        var all = minutes
        if minuteAcc.count > 0 { all.append(minuteAcc.bucket()) }
        return all.min { abs($0.start - t) < abs($1.start - t) }
    }

    // MARK: Persistence

    func save() {
        lastSave = Date()
        let stored = Stored(minutes: minutes, fives: fives)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(stored) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? PropertyListDecoder().decode(Stored.self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        // Buckets saved before metrics were added are padded rather than dropped.
        let count = metricCount
        let fit: (HistoryBucket) -> HistoryBucket? = { b in
            guard b.avg.count <= count, b.max.count == b.avg.count else { return nil }
            var b = b
            b.avg += [Float](repeating: .nan, count: count - b.avg.count)
            b.max += [Float](repeating: .nan, count: count - b.max.count)
            return b
        }
        minutes = stored.minutes.compactMap(fit).filter { $0.start >= now - 86_400 }
        fives = stored.fives.compactMap(fit).filter { $0.start >= now - 604_800 }
    }
}
