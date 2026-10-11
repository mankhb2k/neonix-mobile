#!/usr/bin/env python3
"""Builds the media a published template needs, from templates/demo.json and the generated manifests:

  - templates/<slug>/assets/bgm.m4a   a music excerpt as long as the template (from public/preview/audio)
  - templates/media/<slug>-preview.mp4 / -poster.jpg   a light preview clip and a still from its source video

Run after the manifests exist (the Swift generator, see README). Needs macOS (uses AVFoundation via `swift`).
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
MEDIA = ROOT / "media"
MUSIC = REPO / "public/preview/audio/audio-demo.mp3"
VIDEOS = REPO / "public/preview/video"
PREVIEW_SECONDS = 12


def swift(script, *args):
    result = subprocess.run(["xcrun", "swift", str(ROOT / "tools" / script), *map(str, args)], capture_output=True, text=True)
    lines = [l for l in result.stdout.splitlines() if l.startswith(("ok", "video:", "poster", "failed"))]
    return lines


def main():
    only = set(sys.argv[1:])   # optional: slugs to build, default all
    MEDIA.mkdir(exist_ok=True)
    for entry in json.loads((ROOT / "demo.json").read_text()):
        slug = entry["slug"]
        if only and slug not in only:
            continue
        manifest_path = ROOT / slug / "manifest.json"
        if not manifest_path.exists():
            sys.exit(f"{slug}: no manifest.json - run the Swift generator first")
        seconds = json.loads(manifest_path.read_text())["composition"]["durationMs"] / 1000
        (ROOT / slug / "assets").mkdir(exist_ok=True)
        print(slug, *swift("cut_audio.swift", MUSIC, entry["musicStart"], seconds, ROOT / slug / "assets" / "bgm.m4a"))
        print(slug, *swift("make_preview.swift", VIDEOS / entry["source"], entry["previewStart"], PREVIEW_SECONDS,
                           MEDIA / f"{slug}-preview.mp4", MEDIA / f"{slug}-poster.jpg"))


if __name__ == "__main__":
    main()
