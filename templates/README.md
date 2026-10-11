# Starter templates

`photo-slideshow` (4 photo slots + title) and `video-highlights` (3 video slots + caption), 9:16, 12 s; `polaroid-collage`
places layers with `EditorTransform` (three tilted, overlapping polaroids built from a white shape layer + a photo slot,
the photo's transform derived from the frame's with `canvasPoint`).
Each is a template package (spec: `api/docs/template-package.md`): `manifest.json` + `document.json`.
Slot placeholders are media the app already bundles, so there is no `assets/`.

- **Edit** the builders in `ios-editor/Tests/AppModuleTests/TemplateFixturesTests.swift`, then regenerate the JSON:
  `TEST_RUNNER_WRITE_TEMPLATES=1 xcodebuild … test -only-testing:NeonixEditorTests/TemplateFixturesTests`.
  The same test fails if the files here are stale.
- **Pack:** `python3 templates/build.py` → `templates/dist/*.zip`.
- **Publish:** `python3 templates/publish.py <slug> --preview <image|video>` (see the script header).

## Demo set (Home)

`demo.json` lists 10 more templates (`moody-walk`, `city-weekend`, `soft-diary`, `fast-cuts`, `travel-reel`,
`memory-frames`, `golden-hour`, `night-out`, `mono-diary`, `quick-intro`): different slot counts/lengths, presets,
effects, frame shapes (9:16, 3:4, 2:3), categories and prices. Their structure is in `TemplateFixturesTests`; each one's
preview clip, poster, music offset, category and price are in `demo.json`.

```
TEST_RUNNER_WRITE_TEMPLATES=1 xcodebuild … test -only-testing:NeonixEditorTests/TemplateFixturesTests   # JSON
python3 templates/make_media.py      # music (assets/bgm.m4a) + preview/poster from public/preview/video
python3 templates/build.py           # zips
python3 templates/publish_demo.py    # publish all through the dev API (needs DEV_AUTH_BYPASS and R2 write access)
```

The preview clips are the videos dropped into `public/preview/video/` (third-party CapCut template previews with
their watermarks): demo/dev content only, never ship it.
