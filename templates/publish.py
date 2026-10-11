#!/usr/bin/env python3
"""Publishes a packed template through neonix-api exactly like a creator's app would:
create template -> upload preview -> create version -> upload zip -> complete -> submit.

  python3 templates/publish.py photo-slideshow --poster templates/media/photo-slideshow-poster.jpg
  python3 templates/publish.py video-highlights --poster templates/media/video-highlights-poster.jpg \\
      --preview templates/media/video-highlights-preview.mp4

--poster (still image) is required: cards and the viewer's first frame use it. --preview is an optional short
looping video (a few MB, played while the card is on screen).

Needs the API running with DEV_AUTH_BYPASS=true (dev) and R2 credentials that can WRITE to the buckets.
Use --token <session token> instead of --dev-user against a real server.
"""
import argparse, hashlib, json, mimetypes, sys, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def request(base, method, path, headers, body=None, raw=None):
    data = json.dumps(body).encode() if body is not None else raw
    h = dict(headers)
    if body is not None:
        h["content-type"] = "application/json"
    req = urllib.request.Request(path if path.startswith("http") else base + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            payload = r.read()
            return r.status, (json.loads(payload) if payload and "json" in r.headers.get("content-type", "") else payload)
    except urllib.error.HTTPError as e:
        payload = e.read()
        sys.exit(f"{method} {path} -> {e.code}: {payload[:300].decode(errors='replace')}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("slug")
    parser.add_argument("--poster", required=True, help="still image for cards and the viewer first frame")
    parser.add_argument("--preview", help="optional short looping mp4 played while the card is on screen")
    parser.add_argument("--base", default="http://localhost:8080")
    parser.add_argument("--dev-user", default="dev-creator")
    parser.add_argument("--token", help="session token (overrides --dev-user)")
    parser.add_argument("--category", default="general")
    parser.add_argument("--description", default="")
    parser.add_argument("--price", type=int, help="credit price (admin-only; dev server only, via the dev-admin user)")
    args = parser.parse_args()

    folder = ROOT / args.slug
    zip_path = ROOT / "dist" / f"{args.slug}.zip"
    if not zip_path.is_file():
        sys.exit(f"{zip_path} not found - run templates/build.py first")
    manifest = json.loads((folder / "manifest.json").read_text())
    comp = manifest["composition"]
    headers = {"authorization": f"Bearer {args.token}"} if args.token else {"x-dev-user": args.dev_user, "x-dev-role": "creator"}

    _, t = request(args.base, "POST", "/v1/creator/templates", headers, {"title": manifest["name"], "description": args.description, "category": args.category})
    tid = t["id"]
    print("template", tid)

    keys = {}
    for kind, file, field in (("poster", args.poster, "posterKey"), ("preview", args.preview, "previewKey")):
        if not file:
            continue
        path = Path(file)
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        _, up = request(args.base, "POST", f"/v1/creator/templates/{tid}/preview-upload", headers, {"contentType": ctype, "kind": kind})
        request(args.base, "PUT", up["upload"]["url"], {"content-type": ctype}, raw=path.read_bytes())
        keys[field] = up["key"]
        print(kind, up["key"])
    request(args.base, "PATCH", f"/v1/creator/templates/{tid}", headers, keys)

    zip_bytes = zip_path.read_bytes()
    _, v = request(args.base, "POST", f"/v1/creator/templates/{tid}/versions", headers, {"minAppVersion": manifest["minAppVersion"], "formatVersion": manifest["formatVersion"]})
    request(args.base, "PUT", v["upload"]["url"], {"content-type": "application/zip"}, raw=zip_bytes)
    request(args.base, "POST", f"/v1/creator/templates/{tid}/versions/{v['version']}/complete", headers, {
        "sha256": hashlib.sha256(zip_bytes).hexdigest(), "slotCount": len(manifest["slots"]),
        "width": comp["width"], "height": comp["height"], "durationMs": comp["durationMs"],
    })
    _, s = request(args.base, "POST", f"/v1/creator/templates/{tid}/versions/{v['version']}/submit", headers)
    print("version", v["version"], s["status"])
    if args.price is not None:
        admin = {"x-dev-user": "dev-admin", "x-dev-role": "admin"}
        request(args.base, "PATCH", f"/v1/admin/templates/{tid}", admin, {"creditCost": args.price})
        print("price", args.price)
    else:
        print("Set price + creator earning with PATCH /v1/admin/templates/%s (default price is 6 credits)." % tid)


if __name__ == "__main__":
    main()
