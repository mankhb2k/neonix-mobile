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
        case coastEndedFriction = "coast_ended_friction"
        case coastEndedEdge = "coast_ended_edge"
        case coastInterrupted = "coast_interrupted"
        case pinchEvents = "pinch_events"
    }

    /// Durations in milliseconds; each second reports p50 / p95 / max.
    enum Series: String, CaseIterable {
        case inputHandlerMs = "input_handler_ms"
        case seekServiceMs = "seek_service_ms"
        case seekEndToEndMs = "seek_e2e_ms"
        case seekHopMs = "seek_hop_ms"
        case seekLandingErrorMs = "seek_landing_error_ms"
        case displayAgeMs = "display_age_ms"
        case settleMs = "settle_ms"
        case frameGapMs = "frame_gap_ms"
        case sampleLayerMs = "sample_layer_ms"
        case metalDrawMs = "metal_draw_ms"
        /// Not milliseconds: timeline ms per second at release.
        case coastReleaseSpeed = "coast_release_speed"
        case coastDurationMs = "coast_duration_ms"
        /// Timeline milliseconds travelled by one coast.
        case coastDistanceMs = "coast_distance_ms"
        /// Not milliseconds: finger speed in points/sec at lift, as
        /// `DragGesture.Value.velocity` reports it — zoom-independent, so a
        /// simulator mouse flick and a real finger flick compare directly.
        case releaseFingerPxPerSecond = "release_finger_px_s"
        /// Same quantity re-derived from the last ~100 ms of drag samples, to
        /// catch `.velocity` over/under-reporting. Points/sec, not ms.
        case releaseEstimatedPxPerSecond = "release_est_px_s"
        /// Time from the last drag event to the lift. A long hold means the
        /// finger paused first, so a low release speed is the user's, not ours.
        case releaseHoldMs = "release_hold_ms"
        /// Wall-clock gap between momentum ticks: the refresh rate and any
        /// main-thread stall the coast actually ran at.
        case coastTickMs = "coast_tick_ms"
        /// Per display tick while scrubbing/coasting with video: how far (in
        /// content ms) the frame on screen is from the playhead.
        case displayErrorMs = "display_error_ms"
        /// The same error divided by how fast the playhead moves — i.e. how
        /// many *milliseconds of time* the picture trails the finger. This, not
        /// the content error, is what touch-latency perception studies
        /// (~25 ms) are about. Only sampled while the playhead moves > 100 ms/s.
        case visualLagMs = "visual_lag_ms"
        /// Not milliseconds: playhead speed in content ms per second, to bin the above.
        case playheadSpeedMsPerSecond = "playhead_speed_msps"
    }

    /// Point-in-time values, last one of the second wins.
    enum Gauge: String, CaseIterable {
        case unserved = "unserved"
        case playerSessions = "player_sessions"
        case sourcesTotal = "sources_total"
        case memoryMB = "memory_mb"
        case cpuPercent = "cpu_percent"
        case thermalState = "thermal_state"
        case enginesAlive = "engines_alive"
        case sessionsAlive = "sessions_alive"
        case timelineScale = "timeline_px_per_ms"
        /// The time ruler's tick spacing at the current zoom — "which ruler
        /// level are we at", the unit the zoom-aware policy is defined in.
        case rulerMinorMs = "ruler_minor_ms"
        /// Timeline panel width in points, to express a coast as screen widths.
        case timelineViewportPx = "timeline_viewport_px"
        /// `CoastTuning` in force, so a CSV says which arm it is.
        case coastGain = "coast_gain"
        case coastFriction = "coast_friction"
        /// Slack of the scrub seek most recently issued, in ms.
        case scrubToleranceMs = "scrub_tolerance_ms"
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
        Scenario(id: "T8", title: "T8 zoomed IN (ruler <= 3 frames), slow scrub back and forth"),
        Scenario(id: "T9", title: "T9 zoomed OUT (ruler >= 2 s), fast flicks across the project"),
    ]

    /// What the engine reports once per display tick. Provided by
    /// `EditorPlaybackEngine` so this file never imports engine types.
    struct Probe {
        var mode = "idle"
        /// Age of the target of the frame currently on screen, while any seek
        /// is unserved (0 when display and playhead agree). nil = no session.
        var displayAgeMs: Double?
        var hasUnserved = false
        /// Content ms between the playhead and the frame on screen; nil when
        /// not scrubbing/coasting or no video session covers the playhead.
        var displayErrorMs: Double?
        var playheadSpeedMsPerSecond = 0.0
        var playerSessions = 0
        var sourcesTotal = 0
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

    func liveCount(_ object: LiveObject) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return liveCounts[object, default: 0]
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
    /// Scenario id plus the optional `PLAYBACK_METRICS_TAG` (Debug) that
    /// labels an A/B arm, e.g. `T3:adaptive`.
    @MainActor private var scenarioLabel = "T0"
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

    /// Constant per run: which hardware produced these numbers, so a
    /// simulator CSV and a device CSV are told apart by the file itself.
    private static let environmentCells: [String] = {
        var machine = utsname()
        uname(&machine)
        let raw = withUnsafeBytes(of: &machine.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let env = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        let model = env["SIMULATOR_MODEL_IDENTIFIER"] ?? raw
        let isSimulator = "1"
        #else
        let model = raw
        let isSimulator = "0"
        #endif
        let hz = MainActor.assumeIsolated { UIScreen.main.maximumFramesPerSecond }
        // Model ids look like "iPhone14,5" — a comma would split the CSV cell.
        return [model.replacingOccurrences(of: ",", with: "-"), isSimulator, String(hz)]
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

        var tag: String?
        #if DEBUG
        tag = ProcessInfo.processInfo.environment["PLAYBACK_METRICS_TAG"]
        #endif
        scenarioLabel = tag.map { "\(scenario.id):\($0)" } ?? scenario.id
        let stamp = Self.fileStamp()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback-\(scenario.id)\(tag.map { "-\($0)" } ?? "")-\(stamp).csv")
        let header = (["t", "scenario", "mode", "device", "sim", "hz"] + Self.columns).joined(separator: ",") + "\n"
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

    // MARK: Unattended runs (Debug builds)

    #if DEBUG
    @MainActor private var autoRunConsumed = false

    /// Lets a run be driven from outside the app so the person testing only
    /// has to do the gesture: launch with
    /// `PLAYBACK_METRICS_SCENARIO=T3` (+ optional `PLAYBACK_METRICS_LEADIN`
    /// seconds, default 5, and `PLAYBACK_METRICS_SECONDS`, default 180). Once
    /// the editor opens it counts down, records, and stops by itself. One run
    /// per process launch.
    @MainActor
    func autoRunIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard !autoRunConsumed, !isRecording,
              let id = env["PLAYBACK_METRICS_SCENARIO"],
              let scenario = Self.scenarios.first(where: { $0.id == id })
        else { return }
        autoRunConsumed = true
        let leadIn = Int(env["PLAYBACK_METRICS_LEADIN"] ?? "") ?? 5
        let seconds = Int(env["PLAYBACK_METRICS_SECONDS"] ?? "") ?? 180
        UserDefaults.standard.set(true, forKey: "playbackMetricsArmed")

        for remaining in stride(from: leadIn, to: 0, by: -1) {
            PlaybackMetricsHUDModel.shared.setCountdown(scenario: scenario, seconds: remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        PlaybackMetricsHUDModel.shared.setCountdown(scenario: scenario, seconds: nil)
        start(scenario: scenario)
        defer { if isRecording { stop() } }
        for _ in 0..<seconds {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    #endif

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
        if let error = probe.displayErrorMs {
            record(.displayErrorMs, ms: error)
            if probe.playheadSpeedMsPerSecond >= 100 {
                record(.playheadSpeedMsPerSecond, ms: probe.playheadSpeedMsPerSecond)
                record(.visualLagMs, ms: error / probe.playheadSpeedMsPerSecond * 1000)
            }
        }
        gauge(.unserved, probe.hasUnserved ? 1 : 0)
        gauge(.playerSessions, Double(probe.playerSessions))
        gauge(.sourcesTotal, Double(probe.sourcesTotal))
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

        let cells = [String(format: "%.1f", t), scenarioLabel, previousMode] + Self.environmentCells
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
    /// Seconds until an unattended run starts recording (nil = none pending).
    private(set) var countdown: Int?
    /// Defaults to T3, the case that matters most — not T0, which is easy to
    /// start by accident and mislabel a real scrubbing run.
    var scenario = PlaybackMetrics.scenarios.first { $0.id == "T3" } ?? PlaybackMetrics.scenarios[0]

    fileprivate func setCountdown(scenario: PlaybackMetrics.Scenario, seconds: Int?) {
        self.scenario = scenario
        countdown = seconds
    }

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
