import SwiftUI

/// Overlay for the editor that shows `PlaybackMetrics` live and controls a
/// recording run. Shown only when "Playback metrics HUD" is switched on in
/// Account > Developer. Layout of what each number means:
/// `PLAYBACK_PIPELINE.md` § 4.
///
/// Collapsed it is a tiny pill, so a measured run can be done with almost no
/// HUD drawing at all (observer effect — see the doc).
struct PlaybackMetricsHUD: View {
    @AppStorage("playbackMetricsArmed") private var armed = false
    @State private var expanded = false
    private let model = PlaybackMetricsHUDModel.shared

    var body: some View {
        if armed {
            VStack(alignment: .leading, spacing: 6) {
                pill
                if expanded { panel }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var pill: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isRecording ? Color.red : (model.countdown != nil ? Color.orange : Color.gray))
                    .frame(width: 8, height: 8)
                Text(pillText)
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pillText: String {
        if let countdown = model.countdown { return "\(model.scenario.id) starts in \(countdown)s - get ready" }
        if model.isRecording { return "REC \(model.scenario.id) \(Int(model.latest?.t ?? 0))s" }
        return "metrics"
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            if let row = model.latest {
                Text(lines(for: row))
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                if !model.trend.isEmpty {
                    Divider()
                    Text("TREND first10s -> last10s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    ForEach(model.trend) { line in
                        Text(String(format: "%-22@ %7.1f -> %7.1f  %@", line.name as NSString, line.baseline, line.recent, arrow(line)))
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            } else {
                Text(model.isRecording ? "waiting for first second..." : "not recording")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            @Bindable var bindable = PlaybackMetricsHUDModel.shared
            Menu {
                ForEach(PlaybackMetrics.scenarios) { scenario in
                    Button(scenario.title) { bindable.scenario = scenario }
                }
            } label: {
                Text(model.scenario.id + " v")
                    .font(.caption.monospaced())
            }
            .disabled(model.isRecording || model.countdown != nil)

            Button(model.isRecording ? "Stop" : "Start") {
                if model.isRecording {
                    PlaybackMetrics.shared.stop()
                } else {
                    PlaybackMetrics.shared.start(scenario: model.scenario)
                }
            }
            .font(.caption.bold())
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(model.countdown != nil)

            if let url = model.fileURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                }
            }
        }
    }

    private func arrow(_ line: PlaybackMetrics.TrendLine) -> String {
        guard line.baseline > 0 else { return "" }
        let change = (line.recent - line.baseline) / line.baseline
        if change > 0.25 { return "UP" }
        if change < -0.25 { return "down" }
        return "flat"
    }

    private func lines(for row: PlaybackMetrics.Row) -> String {
        func v(_ key: String, _ format: String = "%.0f") -> String {
            row.values[key].map { String(format: format, $0) } ?? "-"
        }
        func p(_ base: String, _ format: String = "%.0f") -> String {
            "\(v(base + "_p50", format))/\(v(base + "_p95", format))/\(v(base + "_max", format))"
        }
        return """
        t \(String(format: "%.0f", row.t))s  mode \(row.mode)
        INPUT   drag/s \(v("drag_events"))  handler ms p50/95/max \(p("input_handler_ms", "%.1f"))
        CLOCK   setTime/s \(v("set_time_calls"))  modeChg/s \(v("mode_changes"))
        SEEK    req/s \(v("seek_requested")) done/s \(v("seek_completed")) sup/s \(v("seek_superseded")) cancel/s \(v("seek_cancelled")) unserved \(v("unserved"))
                service ms \(p("seek_service_ms"))
                e2e ms     \(p("seek_e2e_ms"))
                main-hop ms \(p("seek_hop_ms", "%.1f"))
                landing err ms \(p("seek_landing_error_ms"))
        DISPLAY age ms \(p("display_age_ms"))  settle ms \(p("settle_ms"))
        PRESENT metal draws/s \(v("metal_draws")) empty/s \(v("metal_empty_buffers")) draw ms \(p("metal_draw_ms", "%.1f"))
        UI      frame gap ms \(p("frame_gap_ms", "%.1f")) dropped/s \(v("dropped_frames"))
                body/s shell \(v("shell_body_evals")) timeline \(v("timeline_body_evals")) layer \(v("layer_body_evals"))
                sampleLayer ms \(p("sample_layer_ms", "%.2f"))
        ZOOM    px/ms \(v("timeline_px_per_ms", "%.3f")) ruler tick \(v("ruler_minor_ms")) ms pinch/s \(v("pinch_events"))
        COAST   release ms/s \(p("coast_release_speed")) dur ms \(p("coast_duration_ms")) dist ms \(p("coast_distance_ms"))
                ended: friction \(v("coast_ended_friction")) edge \(v("coast_ended_edge")) interrupted \(v("coast_interrupted"))
        SOURCE  sessions \(v("player_sessions")) of \(v("sources_total")) layers
        SYSTEM  mem \(v("memory_mb")) MB  cpu \(v("cpu_percent"))%  thermal \(v("thermal_state"))
        (a/b/c = p50/p95/max over the last second)
        """
    }
}
