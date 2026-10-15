#!/usr/bin/env python3
"""Tải sticker từ Flaticon qua API chính thức (Freepik API), chia đều theo chủ đề.

Cần API key: https://www.freepik.com/developers/dashboard  ->  export FREEPIK_API_KEY=...

Ví dụ:
  python3 scripts/crawl_flaticon_stickers.py \
      --topics cat,food,travel,love,music --total 100 --out ~/Downloads/stickers

Ảnh free yêu cầu ghi công tác giả: xem attribution.json trong thư mục output.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

API = "https://api.freepik.com/v1"
PER_PAGE = 50
DELAY_S = 0.5


def session() -> requests.Session:
    key = os.environ.get("FREEPIK_API_KEY")
    if not key:
        sys.exit("Thiếu FREEPIK_API_KEY (export FREEPIK_API_KEY=...)")
    s = requests.Session()
    s.headers.update({"x-freepik-api-key": key, "Accept": "application/json"})
    return s


def get(s: requests.Session, url: str, **params):
    """GET có retry khi bị rate limit (429) hoặc lỗi mạng tạm thời."""
    for attempt in range(5):
        try:
            r = s.get(url, params=params, timeout=30)
        except requests.RequestException:
            time.sleep(2 ** attempt)
            continue
        if r.status_code == 429:
            time.sleep(2 ** attempt)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError(f"Request thất bại: {url}")


def search(s, term: str, want: int):
    """Trả về tối đa `want` icon cho từ khoá `term`."""
    found, page = [], 1
    while len(found) < want:
        data = get(s, f"{API}/icons", term=term, page=page, per_page=PER_PAGE).get("data", [])
        if not data:
            break
        found += data
        page += 1
        time.sleep(DELAY_S)
    return found[:want]


def download(s, icon: dict, dest: Path, size: int) -> bool:
    info = get(s, f"{API}/icons/{icon['id']}/download", format="png", png_size=size)
    url = info.get("data", {}).get("url")
    if not url:
        return False
    r = requests.get(url, timeout=60)
    r.raise_for_status()
    dest.write_bytes(r.content)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--topics", required=True, help="Các chủ đề, ngăn cách bằng dấu phẩy")
    ap.add_argument("--total", type=int, default=100)
    ap.add_argument("--out", default="stickers")
    ap.add_argument("--size", type=int, default=512, help="Cạnh ảnh PNG (px)")
    ap.add_argument("--suffix", default="sticker", help="Thêm vào từ khoá tìm kiếm ('' để tắt)")
    args = ap.parse_args()

    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    s = session()

    # chia đều, phần dư dồn cho các chủ đề đầu
    quota = {t: args.total // len(topics) + (i < args.total % len(topics)) for i, t in enumerate(topics)}
    attribution, seen = [], set()

    for topic, n in quota.items():
        folder = out / topic
        folder.mkdir(exist_ok=True)
        term = f"{topic} {args.suffix}".strip()
        got = 0
        # lấy dư để bù ảnh trùng / tải lỗi
        for icon in search(s, term, n * 2):
            if got >= n:
                break
            if icon["id"] in seen:
                continue
            dest = folder / f"{icon['id']}.png"
            try:
                if not dest.exists() and not download(s, icon, dest, args.size):
                    continue
            except (requests.RequestException, RuntimeError) as e:
                print(f"  bỏ qua {icon['id']}: {e}")
                continue
            seen.add(icon["id"])
            got += 1
            attribution.append({
                "id": icon["id"],
                "topic": topic,
                "file": str(dest.relative_to(out)),
                "name": icon.get("name"),
                "author": (icon.get("author") or {}).get("name"),
                "source": "Flaticon",
            })
            time.sleep(DELAY_S)
        print(f"[{topic}] {got}/{n}")

    (out / "attribution.json").write_text(json.dumps(attribution, ensure_ascii=False, indent=2))
    print(f"Xong: {len(attribution)} sticker -> {out}")


if __name__ == "__main__":
    main()
