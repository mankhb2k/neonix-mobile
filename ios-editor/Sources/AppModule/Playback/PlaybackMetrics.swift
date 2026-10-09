import Darwin
import Foundation
import Observation
import QuartzCore
import UIKit

/// Measurement layer for the playback pipeline. Design, metric catalogue,
/// test matrix and the running results log live in `PLAYBACK_PIPELINE.md`
/// (repo root) — read that first; this file only implements it.
///
/// Rules this type keeps so the measurement doesn't become the bug:
/// - **Nothing records unless a run is started** (`start(scenario:)`). Every
///   hook early-outs on one Bool read, so shipping the hooks costs ~nothing.
/// - **Hooks only append to lock-protected buffers.** Aggregation (p50/p95,
///   per-second rates), CSV writing and HUD updates happen once per second.
/// - **Not `@Observable`.** Hooks are called from inside SwiftUI `body`s; an
///   observed property read there would create exactly the per-tick
///   invalidation this layer exists to detect. Only
///   `PlaybackMetricsHUDModel` is observed, and it changes once a second.
final class PlaybackMetrics: @unchecked Sendable {
    static let shared = PlaybackMetrics()

    // MARK: Catalogue

    /// Events per second.
    enum Counter: String, CaseIterable {
        case dragEvents = "drag_events"
        case setTimeCalls = "set_time_calls"
        case modeChanges = "mode_changes"
        case seekRequested = "seek_requested"
        case seekCompleted = "seek_completed"
        case seekSuperseded = "seek_superseded"
        case seekCancelled = "seek_cancelled"
        case droppedFrames = "dropped_frames"
        case metalDraws = "metal_draws"
        case metalEmptyBuffers = "metal_empty_buffers"
        case layerBodyEvals = "layer_body_evals"
        case timelineBodyEvals = "timeline_body_evals"
        case shellBodyEvals = "shell_body_evals"
    }

    /// Durations in milliseconds; each second reports p50 / p95 / max.
    enum Series: String, CaseIterable {
        case inputHandlerMs = "input_handler_ms"
        case seekServiceMs = "seek_service_ms"
        case seekEndToEndMs = "seek_e2e_ms"
        case seekHopMs = "seek_hop_ms"
        case displayAgeMs = "display_age_ms"
        case settleMs = "settle_ms"
        case frameGapMs = "frame_gap_ms"
        case sampleLayerMs = "sample_layer_ms"
        case metalDrawMs = "metal_draw_ms"
    }

    /// Point-in-time values, last one of the second wins.
    enum Gauge: String, CaseIterable {
        case unserved = "unserved"
        case playerSessions = "player_sessions"
        case sourcesOnProxy = "sources_on_proxy"
        case sourcesTotal = "sources_total"
        case proxyEncoding = "proxy_encoding"
        case memoryMB = "memory_mb"
        case cpuPercent = "cpu_percent"
        case thermalState = "thermal_state"
        case enginesAlive = "engines_alive"
        case sessionsAlive = "sessions_alive"
    }

    /// Objects whose live count must stay flat. Tallied always (not only while
    /// recording) so a run that starts mid-session still reports the truth.
    enum LiveObject {
        case engine, stageSession
    }

    struct Scenario: Hashable, Identifiable {
        let id: String
        let title: String
    }

    static let scenarios: [Scenario] = [
        Scenario(id: "T0", title: "T0 idle 60 s, hands off"),
        Scenario(id: "T1", title: "T1 first open, slow scrub forward"),
        Scenario(id: "T2", title: "T2 fast flick + coast"),
        Scenario(id: "T3", title: "T3 scrub back and forth, 3 min"),
        Scenario(id: "T4", title: "T4 scrub then Play immediately"),
        Scenario(id: "T5", title: "T5 Play across a cut"),
        Scenario(id: "T6", title: "T6 = T3 with a filter (Metal path)"),
        Scenario(id: "T7", title: "T7 = T3 in fullscreen"),
    ]

    /// What the engine reports once per display tick. Provided by
    /// `EditorPlaybackEngine` so this file never imports engine types.
    struct Probe {
        var mode = "idle"
        /// Age of the target of the frame currently on screen, while any seek
        /// is unserved (0 when display and playhead agree). nil = no session.
        var displayAgeMs: Double?
        var hasUnserved = false
        var playerSessions = 0
        var sourcesOnProxy = 0
        var sourcesTotal = 0
        var proxyEncoding = false
    }

    struct Row: Identifiable {
        let id: Int
        let t: Double
        let mode: String
        let values: [String: Double]
    }

    struct TrendLine: Identifiable {
        var id: String { name }
        let name: String
        let baseline: Double
        let recent: Double
    }

    // MARK: Hot path (any thread)

    private let lock = NSLock()
    private var counters: [Counter: Int] = [:]
    private var samples: [Series: [Double]] = [:]
    private var gauges: [Gauge: Double] = [:]
    /// Read without the lock on purpose: a stale read at the very start/end of
    /// a run only costs or drops one sample.
    private(set) var isRecording = false

    func count(_ counter: Counter, _ n: Int = 1) {
        guard isRecording else { return }
        lock.lock()
        counters[counter, default: 0] += n
        lock.unlock()
    }

    func record(_ series: Series, ms: Double) {
        guard isRecording else { return }
        lock.lock()
        samples[series, default: []].append(ms)
        lock.unlock()
    }

    private var liveCounts: [LiveObject: Int] = [:]

    func track(_ object: LiveObject, _ delta: Int) {
        lock.lock()
        liveCounts[object, default: 0] += delta
        lock.unlock()
    }

    func gauge(_ gauge: Gauge, _ value: Double) {
        guard isRecording else { return }
        lock.lock()
        gauges[gauge] = value
        lock.unlock()
    }

    @discardableResult
    func measure<T>(_ series: Series, _ body: () -> T) -> T {
        guard isRecording else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        record(series, ms: (CACurrentMediaTime() - start) * 1000)
        return result
    }

    // MARK: Run control (main actor)

    @MainActor var probe: (() -> Probe)?

    @MainActor private var startedAt: CFTimeInterval = 0
    @MainActor private var scenario = scenarios[0]
    @MainActor private var rows: [Row] = []
    @MainActor private var displayLink: CADisplayLink?
    @MainActor private var linkTarget: MetricsLinkTarget?
    @MainActor private var flushTimer: Timer?
    @MainActor private var lastTickTimestamp: CFTimeInterval?
    @MainActor private var previousMode = "idle"
    @MainActor private var settleStart: CFTimeInterval?
    @MainActor private var fileHandle: FileHandle?
    @MainActor private var fileURL: URL?

    private static let columns: [String] = {
        var names = Counter.allCases.map(\.rawValue)
        for series in Series.allCases {
            names += ["\(series.rawValue)_p50", "\(series.rawValue)_p95", "\(series.rawValue)_max"]
        }
        names += Gauge.allCases.map(\.rawValue)
        return names
    }()

    private static let trendKeys: [(String, String)] = [
        ("seek service p95 ms", "seek_service_ms_p95"),
        ("seek end-to-end p95 ms", "seek_e2e_ms_p95"),
        ("display age p95 ms", "display_age_ms_p95"),
        ("frame gap p95 ms", "frame_gap_ms_p95"),
        ("sampleLayer p95 ms", "sample_layer_ms_p95"),
        ("metal draw p95 ms", "metal_draw_ms_p95"),
        ("memory MB", "memory_mb"),
        ("cpu %", "cpu_percent"),
    ]

    @MainActor
    func start(scenario: Scenario) {
        guard !isRecording else { return }
        self.scenario = scenario
        rows = []
        lastTickTimestamp = nil
        previousMode = "idle"
        settleStart = nil
        startedAt = CACurrentMediaTime()

        lock.lock()
        counters = [:]
        samples = [:]
        gauges = [:]
        lock.unlock()

        let stamp = Self.fileStamp()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-\(scenario.id)-\(stamp).csv")
        let header = (["t", "scenario", "mode"] + Self.columns).joined(separator: ",") + "\n"
        try? header.data(using: .utf8)?.write(to: url)
        fileHandle = try? FileHandle(forWritingTo: url)
        _ = try? fileHandle?.seekToEnd()
        fileURL = url

        isRecording = true

        let target = MetricsLinkTarget()
        let link = CADisplayLink(target: target, selector: #selector(MetricsLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        linkTarget = target
        displayLink = link

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PlaybackMetrics.shared.flush() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer

        PlaybackMetricsHUDModel.shared.began(scenario: scenario, fileURL: url)
    }

    @MainActor
    func stop() {
        guard isRecording else { return }
        flush()
        isRecording = false
        displayLink?.invalidate()
        displayLink = nil
        linkTarget = nil
        flushTimer?.invalidate()
        flushTimer = nil
        try? fileHandle?.close()
        fileHandle = nil
        if let fileURL { NSLog("PlaybackMetrics: wrote \(rows.count) rows to \(fileURL.path)") }
        PlaybackMetricsHUDModel.shared.ended()
    }

    // MARK: Per display tick (main actor)

    @MainActor
    fileprivate func displayTick(_ link: CADisplayLink) {
        guard isRecording else { return }
        let now = link.timestamp
        if let last = lastTickTimestamp {
            let gapMs = (now - last) * 1000
            let expectedMs = max((link.targetTimestamp - link.timestamp) * 1000, 1)
            record(.frameGapMs, ms: gapMs)
            if gapMs > expectedMs * 1.5 {
                count(.droppedFrames, max(1, Int((gapMs / expectedMs).rounded()) - 1))
            }
        }
        lastTickTimestamp = now

        guard let probe = probe?() else { return }
        if probe.mode != previousMode {
            count(.modeChanges)
            if probe.mode == "idle", previousMode == "scrubbing" || previousMode == "coasting" {
                settleStart = now
            } else if probe.mode != "idle" {
                settleStart = nil
            }
            previousMode = probe.mode
        }
        if let settleStart, !probe.hasUnserved {
            record(.settleMs, ms: (now - settleStart) * 1000)
            self.settleStart = nil
        }
        if let age = probe.displayAgeMs { record(.displayAgeMs, ms: age) }
        gauge(.unserved, probe.hasUnserved ? 1 : 0)
        gauge(.playerSessions, Double(probe.playerSessions))
        gauge(.sourcesOnProxy, Double(probe.sourcesOnProxy))
        gauge(.sourcesTotal, Double(probe.sourcesTotal))
        gauge(.proxyEncoding, probe.proxyEncoding ? 1 : 0)
    }

    // MARK: Once per second (main actor)

    @MainActor
    private func flush() {
        gauge(.memoryMB, Self.memoryMB())
        gauge(.cpuPercent, Self.cpuPercent())
        gauge(.thermalState, Double(ProcessInfo.processInfo.thermalState.rawValue))
        lock.lock()
        let engines = liveCounts[.engine, default: 0]
        let sessions = liveCounts[.stageSession, default: 0]
        lock.unlock()
        gauge(.enginesAlive, Double(engines))
        gauge(.sessionsAlive, Double(sessions))

        var values: [String: Double] = [:]
        lock.lock()
        for counter in Counter.allCases {
            values[counter.rawValue] = Double(counters[counter, default: 0])
        }
        for series in Series.allCases {
            let sorted = (samples[series] ?? []).sorted()
            guard !sorted.isEmpty else { continue }
            values["\(series.rawValue)_p50"] = Self.percentile(sorted, 0.5)
            values["\(series.rawValue)_p95"] = Self.percentile(sorted, 0.95)
            values["\(series.rawValue)_max"] = sorted[sorted.count - 1]
        }
        for gauge in Gauge.allCases {
            if let value = gauges[gauge] { values[gauge.rawValue] = value }
        }
        counters = [:]
        samples = [:]
        lock.unlock()

        let t = CACurrentMediaTime() - startedAt
        let row = Row(id: rows.count, t: t, mode: previousMode, values: values)
        rows.append(row)

        let cells = [String(format: "%.1f", t), scenario.id, previousMode]
            + Self.columns.map { key in values[key].map { String(format: "%.2f", $0) } ?? "" }
        if let data = (cells.joined(separator: ",") + "\n").data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }

        PlaybackMetricsHUDModel.shared.publish(row: row, trend: trendLines())
    }

    /// Mean of the run's first 10 seconds vs its last 10 — the whole point of
    /// T3 is whether these drift apart.
    @MainActor
    private func trendLines() -> [TrendLine] {
        guard rows.count >= 20 else { return [] }
        let head = rows.prefix(10)
        let tail = rows.suffix(10)
        func mean(_ slice: ArraySlice<Row>, _ key: String) -> Double? {
            let present = slice.compactMap { $0.values[key] }
            return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        }
        return Self.trendKeys.compactMap { name, key in
            guard let baseline = mean(head, key), let recent = mean(tail, key) else { return nil }
            return TrendLine(name: name, baseline: baseline, recent: recent)
        }
    }

    // MARK: Helpers

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    private static func cpuPercent() -> Double {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        var total = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        return total
    }
}

/// `CADisplayLink` retains its target; this is the only thing it retains.
private final class MetricsLinkTarget: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { PlaybackMetrics.shared.displayTick(link) }
    }
}

/// The one observed object — updated once per second, so the HUD can use
/// ordinary SwiftUI observation without feeding back into what it measures.
@MainActor
@Observable
final class PlaybackMetricsHUDModel {
    static let shared = PlaybackMetricsHUDModel()

    private(set) var latest: PlaybackMetrics.Row?
    private(set) var trend: [PlaybackMetrics.TrendLine] = []
    private(set) var isRecording = false
    private(set) var fileURL: URL?
    var scenario = PlaybackMetrics.scenarios[0]

    fileprivate func began(scenario: PlaybackMetrics.Scenario, fileURL: URL) {
        self.scenario = scenario
        self.fileURL = fileURL
        latest = nil
        trend = []
        isRecording = true
    }

    fileprivate func ended() {
        isRecording = false
    }

    fileprivate func publish(row: PlaybackMetrics.Row, trend: [PlaybackMetrics.TrendLine]) {
        latest = row
        self.trend = trend
    }
}
