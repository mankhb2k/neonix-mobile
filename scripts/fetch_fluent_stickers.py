#!/usr/bin/env python3
"""Tải sticker PNG (Fluent Emoji 3D, MIT) từ github.com/microsoft/fluentui-emoji, chia đều theo nhóm.

Không cần API key. Ví dụ:
  python3 scripts/fetch_fluent_stickers.py --total 100 --out public/preview/stickers
"""
import argparse
import json
import random
import re
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = "microsoft/fluentui-emoji"
GROUPS = ["Smileys & Emotion", "Animals & Nature", "Food & Drink",
          "Travel & Places", "Activities", "Objects"]
PNG_RE = re.compile(r"^assets/([^/]+)/3D/[^/]+\.png$")  # bỏ biến thể màu da (có thêm thư mục con)


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "neonix"}), timeout=30) as r:
        return r.read()


def raw(path: str) -> str:
    return f"https://raw.githubusercontent.com/{REPO}/main/{urllib.parse.quote(path)}"


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--total", type=int, default=100)
    ap.add_argument("--out", default="public/preview/stickers")
    ap.add_argument("--groups", default=",".join(GROUPS), help="Nhóm emoji, ngăn cách bằng dấu phẩy")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    quota = {g: args.total // len(groups) + (i < args.total % len(groups)) for i, g in enumerate(groups)}
    out = Path(args.out)

    tree = json.loads(fetch(f"https://api.github.com/repos/{REPO}/git/trees/main?recursive=1"))["tree"]
    pngs = {m.group(1): p["path"] for p in tree if (m := PNG_RE.match(p["path"]))}
    names = sorted(pngs)
    random.Random(args.seed).shuffle(names)

    def group_of(name):
        try:
            return json.loads(fetch(raw(f"assets/{name}/metadata.json"))).get("group")
        except Exception:
            return None

    picked, counts = [], dict.fromkeys(groups, 0)
    with ThreadPoolExecutor(16) as pool:
        for i in range(0, len(names), 48):
            batch = names[i:i + 48]
            for name, g in zip(batch, pool.map(group_of, batch)):
                if g in counts and counts[g] < quota[g]:
                    counts[g] += 1
                    picked.append((g, name))
            if counts == quota:
                break

    def save(item):
        g, name = item
        dest = out / slug(g) / f"{slug(name)}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(fetch(raw(pngs[name])))
        return {"file": str(dest.relative_to(out)), "name": name, "group": g,
                "source": f"https://github.com/{REPO}", "license": "MIT"}

    with ThreadPoolExecutor(8) as pool:
        meta = list(pool.map(save, picked))
    (out / "stickers.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    print(counts)
    print(f"Xong: {len(meta)} sticker -> {out}")


if __name__ == "__main__":
    main()
