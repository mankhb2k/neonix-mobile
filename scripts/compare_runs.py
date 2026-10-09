#!/usr/bin/env python3
"""Side-by-side comparison of two playback-metrics CSVs (e.g. simulator vs a real
iPhone) focused on momentum / drag feel. Usage:

    scripts/compare_runs.py sim.csv device.csv

Each CSV row is one second, and series columns are that second's p50/p95/max, so
every "median" below is a median of per-second p50s (an approximation, good
enough to see a 2x difference, not a precise percentile of raw events).
"""
import csv
import statistics as st
import sys


def load(path):
    rows = list(csv.DictReader(open(path)))
    zoom = 0.2
    for r in rows:
        v = r.get("timeline_px_per_ms", "")
        zoom = float(v) if v not in ("", None) else zoom
        r["_zoom"] = zoom
    return rows


def num(r, key):
    v = r.get(key, "")
    return float(v) if v not in ("", None) else None


def col(rows, key, where=None):
    return [x for r in rows if (where is None or where(r)) for x in [num(r, key)] if x is not None]


def med(v):
    return st.median(v) if v else None


def pct(v, q):
    if not v:
        return None
    s = sorted(v)
    return s[min(len(s) - 1, int(q * len(s)))]


def fmt(x, digits=0):
    return "-" if x is None else f"{x:.{digits}f}"


def summarize(rows):
    out = {}
    first = rows[0]
    out["device"] = first.get("device", "?")
    out["simulator"] = first.get("sim", "?")
    out["refresh Hz"] = first.get("hz", "?")
    out["seconds recorded"] = len(rows)

    fing = col(rows, "release_finger_px_s_p50")
    est = col(rows, "release_est_px_s_p50")
    hold = col(rows, "release_hold_ms_p50")
    out["lift speed, DragGesture px/s (p25 / median / p75 / max)"] = (
        f"{fmt(pct(fing, .25))} / {fmt(med(fing))} / {fmt(pct(fing, .75))} / {fmt(max(fing) if fing else None)}"
    )
    out["lift speed, own estimate px/s (median)"] = fmt(med(est))
    ratio = [a / b for a, b in zip(col(rows, "release_finger_px_s_p50"), col(rows, "release_est_px_s_p50")) if b]
    out["  .velocity / own estimate (1.0 = agree)"] = fmt(med(ratio), 2)
    out["finger paused before lift, ms (median)"] = fmt(med(hold))

    dist_ms = col(rows, "coast_distance_ms_p50")
    zooms = [r["_zoom"] for r in rows if num(r, "coast_distance_ms_p50") is not None]
    dist_px = [d * z for d, z in zip(dist_ms, zooms)]
    out["coast duration, ms (median)"] = fmt(med(col(rows, "coast_duration_ms_p50")))
    out["coast distance, px (median)"] = fmt(med(dist_px))
    widths = [num(r, "timeline_viewport_px") for r in rows if num(r, "coast_distance_ms_p50") is not None]
    screens = [d / w for d, w in zip(dist_px, widths) if w]
    out["coast distance, screen widths (median)"] = fmt(med(screens), 2)
    out["coast gain / friction scale in force"] = (
        f"{fmt(med(col(rows, 'coast_gain')), 2)} / {fmt(med(col(rows, 'coast_friction')), 2)}")
    out["coast distance, content ms (median)"] = fmt(med(dist_ms))

    total = sum(num(r, k) or 0 for r in rows for k in ("coast_ended_friction", "coast_ended_edge", "coast_interrupted"))
    for label, k in (("ended by friction", "coast_ended_friction"), ("ended at timeline edge", "coast_ended_edge"),
                     ("cut short by a touch", "coast_interrupted")):
        n = sum(num(r, k) or 0 for r in rows)
        out[f"coasts {label}"] = f"{int(n)} ({100 * n / total:.0f}%)" if total else "-"

    ticks = col(rows, "coast_tick_ms_p50")
    out["coast tick gap, ms (median p50 / worst p95 / worst max)"] = (
        f"{fmt(med(ticks), 1)} / {fmt(max(col(rows, 'coast_tick_ms_p95') or [0]), 1)} / {fmt(max(col(rows, 'coast_tick_ms_max') or [0]), 1)}"
    )

    coasting = lambda r: r["mode"] == "coasting"
    out["seek service p95 while coasting, ms (median)"] = fmt(med(col(rows, "seek_service_ms_p95", coasting)), 1)
    out["landing error while coasting, ms (median p50)"] = fmt(med(col(rows, "seek_landing_error_ms_p50", coasting)))
    out["display age while coasting, ms (median p95)"] = fmt(med(col(rows, "display_age_ms_p95", coasting)))
    out["seeks completed / s while coasting (median)"] = fmt(med(col(rows, "seek_completed", coasting)), 1)
    out["dropped frames / s while coasting (mean)"] = fmt(
        st.fmean(col(rows, "dropped_frames", coasting)) if col(rows, "dropped_frames", coasting) else None, 2)
    out["timeline zoom, px/ms (median)"] = fmt(med([r["_zoom"] for r in rows]), 3)
    return out


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    a, b = summarize(load(argv[1])), summarize(load(argv[2]))
    width = max(len(k) for k in a)
    print(f"{'':{width}}  {'A: ' + argv[1].split('/')[-1][:28]:30}  {'B: ' + argv[2].split('/')[-1][:28]}")
    for k in a:
        print(f"{k:{width}}  {str(a[k]):30}  {b[k]}")


if __name__ == "__main__":
    main(sys.argv)
