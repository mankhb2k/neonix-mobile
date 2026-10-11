#!/usr/bin/env python3
"""Publishes every template in templates/demo.json (preview clip, poster, category, price) through the dev API.
Run build.py and make_media.py first. Dev server only (DEV_AUTH_BYPASS)."""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    only = set(sys.argv[1:])   # optional: slugs to publish, default all
    for entry in json.loads((ROOT / "demo.json").read_text()):
        slug = entry["slug"]
        if only and slug not in only:
            continue
        print("==", slug)
        result = subprocess.run([
            sys.executable, str(ROOT / "publish.py"), slug,
            "--poster", str(ROOT / "media" / f"{slug}-poster.jpg"),
            "--preview", str(ROOT / "media" / f"{slug}-preview.mp4"),
            "--category", entry["category"], "--description", entry["description"], "--price", str(entry["price"]),
        ])
        if result.returncode != 0:
            sys.exit(f"{slug}: publish failed")


if __name__ == "__main__":
    main()
