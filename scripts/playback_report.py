#!/usr/bin/env python3
"""Summarise a PlaybackMetrics CSV (see PLAYBACK_PIPELINE.md).

  python3 scripts/playback_report.py run.csv            one run: first 10s vs last 10s
  python3 scripts/playback_report.py before.csv after.csv   two runs side by side

The point of a T3 run is the "first10 -> last10" column: a number that climbs
there is something accumulating, which is what the editor shows as "gets worse
the longer I scrub".
"""
import csv
import statistics
import sys

KEYS = [
    ("seek_service_ms_p95", "seek service p95 ms"),
    ("seek_e2e_ms_p95", "seek end-to-end p95 ms"),
    ("seek_hop_ms_p95", "seek main-hop p95 ms"),
    ("display_age_ms_p95", "display age p95 ms"),
    ("settle_ms_p95", "settle p95 ms"),
    ("frame_gap_ms_p95", "frame gap p95 ms"),
    ("dropped_frames", "dropped frames /s"),
    ("sample_layer_ms_p95", "sampleLayer p95 ms"),
    ("metal_draw_ms_p95", "metal draw p95 ms"),
    ("metal_draws", "metal draws /s"),
    ("metal_empty_buffers", "metal empty buffers /s"),
    ("shell_body_evals", "shell body evals /s"),
    ("timeline_body_evals", "timeline evals /s"),
    ("seek_superseded", "seek superseded /s"),
    ("memory_mb", "memory MB"),
    ("cpu_percent", "cpu %"),
    ("thermal_state", "thermal 0-3"),
    ("engines_alive", "engines alive"),
    ("sessions_alive", "sessions alive"),
    ("proxy_encoding", "proxy encoding"),
]


def load(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def column(rows, key):
    out = []
    for r in rows:
        v = r.get(key, "")
        if v not in ("", None):
            out.append(float(v))
    return out


def mean(xs):
    return statistics.fmean(xs) if xs else None


def fmt(x):
    return "-" if x is None else f"{x:8.1f}"


def summarise(rows):
    head, tail = rows[:10], rows[-10:]
    out = {}
    for key, _ in KEYS:
        all_v = column(rows, key)
        out[key] = (mean(column(head, key)), mean(column(tail, key)), max(all_v) if all_v else None)
    return out


def flag(a, b):
    if a is None or b is None or a == 0:
        return ""
    change = (b - a) / abs(a)
    return "UP" if change > 0.25 else "down" if change < -0.25 else ""


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    runs = [(p, load(p)) for p in argv[:2]]
    for path, rows in runs:
        scenario = rows[0].get("scenario", "?") if rows else "?"
        span = rows[-1]["t"] if rows else "0"
        print(f"{path}: scenario {scenario}, {len(rows)} rows, {span}s")
    print()
    sums = [summarise(rows) for _, rows in runs]
    if len(runs) == 1:
        print(f"{'metric':28} {'first10s':>8} {'last10s':>8} {'max':>8}")
        for key, label in KEYS:
            a, b, m = sums[0][key]
            if a is None and b is None:
                continue
            print(f"{label:28} {fmt(a)} {fmt(b)} {fmt(m)}  {flag(a, b)}")
    else:
        print(f"{'metric (last10s mean)':28} {'run A':>8} {'run B':>8}")
        for key, label in KEYS:
            a, b = sums[0][key][1], sums[1][key][1]
            if a is None and b is None:
                continue
            print(f"{label:28} {fmt(a)} {fmt(b)}  {flag(a, b)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
