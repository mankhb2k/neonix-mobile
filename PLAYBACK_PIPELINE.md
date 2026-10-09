# PLAYBACK_PIPELINE.md

Tài liệu sống về pipeline phát/scrub video của editor: sơ đồ, hợp đồng từng
tầng, danh mục số đo, ma trận test, và **nhật ký kết quả + quyết định**.
Mỗi lần làm xong một việc, quay lại đây để quyết định việc kế tiếp.

Tạo 2026-10-09, sau một chuỗi vá liên tiếp (clock, hysteresis, proxy, Metal…)
mà không có số đo nào cho biết vá có trúng chỗ hay không.

---

## 0. Luật làm việc

1. **Không sửa pipeline nếu chưa có một con số chỉ ra tầng nghẽn.** "Có vẻ là…"
   không đủ. Mỗi thay đổi = **một giả thuyết + một số đo trước + một số đo sau**
   (ghi ở §10).
2. **Một thay đổi một lần.** Hai thay đổi cùng lúc thì không biết cái nào có tác dụng.
3. **Cùng điều kiện khi so sánh:** cùng máy, cùng clip, cùng kịch bản (§6), cùng
   HUD thu gọn (§8).
4. **Số trên simulator chỉ dùng để kiểm tra công cụ đo, không dùng làm baseline.**
   Baseline phải đo trên iPhone thật (nhiệt, bộ giải mã phần cứng, 120Hz đều khác).
5. Số đo lệch kỳ vọng → cập nhật §3 (giả thuyết), không âm thầm đổi ngưỡng.

**Vòng lặp:**

```
chạy case (§5, §6) → ghi vào §9 → đối chiếu bảng §7 → chọn 1 giả thuyết (§3)
   → sửa nhỏ nhất có thể → chạy lại CÙNG case → ghi §10 (đúng/sai) → lặp
```

## 1. Triệu chứng gốc (quan sát của người dùng, 2026-10-09)

- Mới vào editor: seek + momentum scroll **rất mượt**.
- Scroll qua lại **nhiều lần** thì **kém mượt dần**.
- Sandbox `AVPlayer` thuần (tab Playback) **kém mượt hơn** editor.
- Proxy transcode không phải nguyên nhân (nó chỉ bỏ chi phí keyframe-walk khi nhảy xa).
- Đã từng thấy màn đen đứng yên mãi trên simulator, **chưa lặp lại được, chưa có
  nguyên nhân** (xem §10, mục "Bằng chứng trước tài liệu này").

"Kém dần theo thời gian" = có thứ gì đó **tích tụ**. Mọi số đo ở dưới được chọn để
phát hiện sự tích tụ: so **10 giây đầu** với **10 giây cuối** của cùng một lần chạy.

## 2. Sơ đồ pipeline (đúng với code hiện tại)

```
 NGÓN TAY
    │ DragGesture.onChanged  (~60–120 lần/giây)
    ▼
┌─[1] INPUT ──────────────────────────────────────── main thread ─┐
│ UI/Editor/TimelineView.swift  translation → deltaMs              │
│ thả tay: velocity → engine.endScrub                              │
└───────────────────────────┬──────────────────────────────────────┘
                            ▼
┌─[2] CLOCK / STATE ──────────────────────────────── main thread ─┐
│ Playback/EditorPlaybackEngine.swift                              │
│ mode: idle | scrubbing | coasting | playing                      │
│ currentTimeMs ← setTime()        (kéo, momentum — DisplayLinkClock)
│               ← AVPlayer.currentTime  (khi Play: player là clock)│
└──────────┬──────────────────────────────┬────────────────────────┘
           │ mỗi lần currentTimeMs đổi     │
           ▼                              ▼
┌─[3] SEEK SCHEDULER ── main ─┐   ┌─[6] SWIFTUI RENDER ───── main ─┐
│ seekStageSessions()         │   │ UI/PreviewCanvas.swift          │
│  kéo/trôi: tolerance 0.2s   │   │  LayerNodeView → sampleLayer()  │
│  thả tay/Play: tolerance 0  │   │  (Runtime/KeyframeSampler)      │
│ Playback/PlayerSeekCoord…   │   │ UI/Editor/TimelineView.swift    │
│  1 seek chạy + 1 seek chờ   │   │  GeometryReader: offset, playhead│
│  (seek mới đè seek chờ cũ)  │   │ UI/Editor/EditorShellView.swift │
└──────────┬──────────────────┘   │  StagePreview (cô lập, fix #1)  │
           ▼                      └─────────────────────────────────┘
┌─[4] DECODE ───────────────────────────── hệ thống (AVFoundation) ─┐
│ Playback/StagePlayerSession.swift: 1 AVPlayer / layer video        │
│ Nguồn: proxy 720px, keyframe mỗi 10 khung                          │
│   (Runtime/VideoProxyService.swift, tạo trong prepare();           │
│    chưa xong thì dùng file gốc keyframe/250 khung)                 │
│ Giải mã phần cứng nằm trong AVPlayer                               │
└──────────┬────────────────────────────────────────────────────────┘
           ▼
┌─[5] PRESENT ──────────────────────────────────────────────────────┐
│ Không filter: AVPlayerLayer  (hệ thống vẽ, ngoài main thread)      │
│ Có filter:    AVPlayerItemVideoOutput → CIImage → FilterRenderer   │
│               → MTKView (vòng vẽ liên tục, chạy trên main)         │
└───────────────────────────────────────────────────────────────────┘
 [7] AUDIO  Playback/AudioMixEngine.swift — chỉ chạy khi Play (scrub im lặng)
```

**Đường dự phòng không dùng trong editor:** `Playback/VideoFrameServer.swift`
(`AVAssetReader` → `CGImage` cache). `EditorPlaybackEngine` đặt
`usesNativePlayer: true` cho mọi nguồn nên nhánh này chỉ chạy khi
`PreviewCanvas` được tạo không có engine. Nếu số đo cho thấy `VideoFrameServer`
đang hoạt động trong editor thì đó là bug.

Điểm cần nhớ: từ [2] có **hai nhánh song song cùng tranh main thread**: nhánh
seek [3]→[4]→[5] và nhánh dựng SwiftUI [6].

## 3. Hợp đồng từng tầng + giả thuyết còn mở

| Tầng | Được làm gì trên main thread | State có thể tích tụ theo thời gian |
|---|---|---|
| [1] Input | tính delta, gọi engine; phải rất rẻ | không |
| [2] Clock | ghi `currentTimeMs`, đổi mode | không |
| [3] Seek scheduler | gọi `AVPlayer.seek`, giữ ≤1 seek chờ | seek chờ không được > 1; completion bị bỏ khi bị đè |
| [4] Decode | không gì (phần cứng) | **bộ nhớ/buffer trong AVPlayer sau nhiều seek; số AVPlayer/Session sống** |
| [5] Present | Metal: toàn bộ `draw()` nằm trên main | drawable/pixel buffer giữ lại |
| [6] SwiftUI | dựng view; chỉ Stage + playhead được dựng lại mỗi tick | số lần dựng lại ngoài ý muốn |

### Giả thuyết (trạng thái: **chưa kiểm chứng** trừ khi ghi khác)

| # | Giả thuyết | Số đo xác nhận | Số đo bác bỏ |
|---|---|---|---|
| H1 | AVPlayer tích tụ state sau nhiều seek → seek chậm dần | `seek_service_ms_p95` tăng first10→last10 trong T3 | phẳng |
| H2 | Rò rỉ bộ nhớ (player/output/session) | `memory_mb` tăng đều; `sessions_alive` > số layer video | phẳng |
| H3 | `EditorShellView.init` tạo `EditorPlaybackEngine` mới mỗi lần struct bị tạo lại (`State(initialValue:)` đánh giá biểu thức mỗi lần) → mỗi engine tạo AVPlayer | `engines_alive` > 1 hoặc tăng | luôn = 1 |
| H4 | Main thread nghẽn khi kéo lâu (SwiftUI/Runtime) | `frame_gap_ms_p95`/`dropped_frames` tăng; `seek_hop_ms_p95` tăng | phẳng |
| H5 | Máy nóng, tự hạ xung (chỉ máy thật) | `thermal_state` ≥ 2 cùng lúc các số khác xấu đi | `thermal_state` = 0 |
| H6 | Tạo proxy chạy chồng lúc người dùng đã kéo | `proxy_encoding` = 1 trùng giai đoạn `dropped_frames`/seek chậm (T1) | không trùng |
| H7 | Vòng vẽ Metal chạy ngầm khi đứng yên (đường filter) | `metal_draws` > 0 trong T0 | = 0 |
| H8 | `draw()` Metal gọi đồng bộ `item.asset.tracks(...)` mỗi khung | `metal_draw_ms_p95` cao, nhất là lúc seek (T6) | thấp, phẳng |
| H9 | Tolerance 0.2s lúc kéo làm hình "nhảy bậc" dù seek nhanh | `display_age_ms` thấp nhưng người dùng vẫn thấy giật | — (cần mắt nhìn, không có số) |

**Đã xác nhận (2026-10-09, simulator, driver giả lập):** `shell_body_evals` = 0
suốt khi scrub → `EditorShellView.body` không còn bị dựng lại mỗi tick (fix #1 có hiệu lực).

## 4. Danh mục số đo

CSV mỗi giây một dòng: `t, scenario, mode, <các cột dưới>`. Counter = số lần/giây.
Series = p50/p95/max trong giây đó, cột `<tên>_p50`, `_p95`, `_max`. Gauge = giá trị cuối giây.
Số đo **không ghi** gì khi chưa bấm Start (mọi hook thoát ngay).

**Ngưỡng dưới đây là giả định khởi điểm của tôi, chưa phải ngưỡng đã đo. Phải sửa
lại sau khi có baseline thật (§9).**

### [1] Input
| Cột | Đo gì, ở đâu | Ngưỡng khởi điểm |
|---|---|---|
| `drag_events` | số lần `DragGesture.onChanged`/s (`TimelineView`) | ≈ 60–120 khi kéo |
| `input_handler_ms_*` | thời gian `beginScrub`+`scrub` trong `onChanged` | p95 < 1 ms |

### [2] Clock
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `set_time_calls` | `EditorPlaybackEngine.setTime`/s | ≈ `drag_events` |
| `mode_changes` | số lần đổi mode/s (từ probe mỗi tick) | gần 0 khi kéo liên tục |

### [3] Seek scheduler (nghi phạm số 1 cho "kém dần")
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `seek_requested` | số lần gọi `PlayerSeekCoordinator.request`/s | ≈ `set_time_calls` |
| `seek_completed` | seek hoàn tất đúng ID/s | gần `seek_requested`; tụt = đang tụt lại |
| `seek_superseded` | seek chờ bị seek mới đè trước khi chạy | > 0 là **bình thường** khi kéo nhanh hơn seek; quan trọng là xu hướng |
| `seek_cancelled` | `cancelPendingSeeks` lúc còn việc dở | ~0 |
| `seek_service_ms_*` | từ lúc gọi `AVPlayer.seek` đến completion handler = công việc của AVFoundation | p95 < 33 ms trên proxy; **không tăng theo thời gian** |
| `seek_e2e_ms_*` | từ lúc `request` đến completion = gồm cả thời gian chờ sau seek trước | p95 < 50 ms |
| `seek_hop_ms_*` | từ completion handler đến lúc main actor chạy `Task` = **độ tắc main thread** | p95 < 5 ms |
| `unserved` (gauge) | 1 nếu còn seek chưa phục vụ ở thời điểm lấy mẫu | — |

### [4] Decode / nguồn
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `player_sessions` | số `StagePlayerSession` của engine đang dùng | = số layer video |
| `sessions_alive` | tổng `StagePlayerSession` còn sống toàn app | = `player_sessions` |
| `engines_alive` | tổng `EditorPlaybackEngine` còn sống | **= 1** khi editor mở |
| `sources_on_proxy` / `sources_total` | nguồn đang dùng proxy / tổng | bằng nhau sau `prepare()` |
| `proxy_encoding` | 1 khi đang tạo proxy | 0 trong lúc đo (trừ T1) |

### [0] Cảm nhận người dùng
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `display_age_ms_*` | trong lúc còn seek chưa phục vụ: tuổi của mục tiêu của khung đang hiện (`now − requestedAt` của seek hoàn tất gần nhất). 0 khi hình đã khớp playhead. **Suy ra từ sổ sách seek, không phải thời điểm photon lên màn hình** | p95 < 50 ms |
| `settle_ms_*` | từ lúc thả tay (scrubbing/coasting → idle) đến khi hết seek chưa phục vụ (gồm seek chính xác tolerance 0) | p95 < 150 ms |

### [5] Present (chỉ đường Metal/filter)
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `metal_draws` | số `draw()`/s | ≈ tần số màn hình khi đang kéo; **0 khi đứng yên** (T0) |
| `metal_draw_ms_*` | thời gian trong `draw()` (CPU phía main) | p95 < 4 ms |
| `metal_empty_buffers` | `copyPixelBuffer` trả rỗng/s (khung chưa sẵn sàng) | ~0 |

Đường `AVPlayerLayer` (không filter) **không đo được** phía present: hệ thống tự vẽ.

### [6] SwiftUI / main thread
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `frame_gap_ms_*` | khoảng cách giữa 2 tick của một `CADisplayLink` riêng của bộ đo = **main run loop còn thở không** | p95 ≤ 1.2 × chu kỳ màn hình (20 ms@60Hz, 10 ms@120Hz) |
| `dropped_frames` | số tick bị lỡ/s (gap > 1.5 × chu kỳ) | ≈ 0 khi kéo |
| `sample_layer_ms_*` | thời gian `sampleLayer` mỗi layer (Runtime) | p95 < 0.5 ms |
| `layer_body_evals` | số lần `LayerNodeView.body`/s | ≈ số layer × `set_time_calls` |
| `timeline_body_evals` | số lần nội dung `GeometryReader` của timeline chạy/s | ≈ `set_time_calls` |
| `shell_body_evals` | số lần `EditorShellView.body`/s | **≈ 0 khi scrub** |

### Toàn hệ thống
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `memory_mb` | `phys_footprint` của app | **phẳng** first10→last10 (±10%) |
| `cpu_percent` | tổng % CPU các thread (có thể > 100) | không tăng dần |
| `thermal_state` | 0 nominal · 1 fair · 2 serious · 3 critical | 0–1 |

## 5. Cách chạy một lần đo

1. Cài bản debug lên **iPhone thật**. Ghi lại model + iOS.
2. Account → Developer → bật **Playback metrics HUD**.
3. Mở một project vào editor. Một viên thuốc `metrics` hiện ở giữa thanh trên.
4. Chạm viên thuốc → chọn kịch bản (Txx) → **Start**. **Chạm viên thuốc lần nữa để thu gọn**
   (panel mở cũng tốn CPU, gây nhiễu — §8).
5. Làm đúng kịch bản (§6), đúng thời lượng.
6. Mở panel → **Stop** → nút chia sẻ → AirDrop file CSV về Mac. File cũng nằm trong
   `Documents/playback-<Txx>-<thời gian>.csv` của app.
7. `python3 scripts/playback_report.py file.csv` — in bảng **first10s → last10s** + max.
   Hai file: `playback_report.py truoc.csv sau.csv`.
8. Ghi vào §9. Đối chiếu §7.

## 6. Ma trận test case

| ID | Kịch bản | Thời lượng | Xem gì trước | Đạt khi (khởi điểm) |
|---|---|---|---|---|
| T0 | Mở editor, **không chạm**, để im | 60 s | `metal_draws`, `cpu_percent`, `memory_mb`, `engines_alive` | `metal_draws`=0, CPU thấp, phẳng |
| T1 | Mở editor lần đầu (xoá cache proxy trước), kéo chậm tiến | 20 s | `proxy_encoding`, `dropped_frames` 5 s đầu, `seek_service` | không rớt khung dù đang tạo proxy |
| T2 | 10 lần flick nhanh rồi để trôi, nghỉ 3 s giữa các lần | ~60 s | `settle_ms`, `seek_e2e`, `mode_changes` | settle p95 < 150 ms |
| **T3** | **Kéo qua lại liên tục toàn timeline, ~1 lượt/3–4 s** | **180 s** | **bảng trend**: `seek_service`, `frame_gap`, `memory_mb`, `engines_alive` | **không chỉ số nào tăng** first10→last10 |
| T4 | Kéo đến điểm bất kỳ, thả, **bấm Play trong ≤300 ms**, lặp 20 lần | ~2 phút | `dropped_frames`, `frame_gap` quanh lúc Play; ghi tay: có khựng/đen không | không khựng. *Chưa có số đo thời gian từ Play đến khung đầu (§11)* |
| T5 | Cắt clip làm đôi (Split), Play xuyên qua điểm cắt | 20 s | `mode_changes`, `dropped_frames`, seek quanh điểm cắt | không khựng tại điểm cắt |
| T6 | Như T3 nhưng layer **có filter** (đường Metal) | 180 s | `metal_draw_ms`, `metal_empty_buffers`, `frame_gap` | `metal_empty_buffers` ~0 |
| T7 | Như T3 trong **fullscreen** | 180 s | như T3 | như T3 |

Cố định giữa các lần: cùng clip (`13792197_1080_1920_30fps.mp4`, 31.2 s), tốc độ kéo
tương đương, màn hình sáng cố định, không sạc, không chạy app khác.

## 7. Bảng chẩn đoán: số đo → tầng → việc tiếp theo

| Thấy | Nghi tầng | Việc kế tiếp (một việc!) |
|---|---|---|
| `seek_service_ms_p95` **tăng dần** | [4] AVPlayer tích tụ (H1) | Thử: tạo lại `AVPlayerItem` định kỳ / sau N seek; đo lại T3 |
| `memory_mb` tăng đều, `sessions_alive`/`engines_alive` > kỳ vọng | rò rỉ (H2/H3) | Tìm ai giữ; với H3: tạo engine một lần (không trong `init` của `State`) |
| `engines_alive` > 1 | H3 | Sửa chỗ tạo engine; đo lại T0/T3 |
| `seek_service` phẳng nhưng `seek_hop_ms` / `frame_gap_ms` / `dropped_frames` tăng | [6] main thread nghẽn (H4) | Xem `layer_body_evals`, `timeline_body_evals`: dựng quá nhiều → cô lập thêm / giảm việc mỗi tick |
| Mọi thứ phẳng nhưng `thermal_state` leo ≥2 | nhiệt (H5) | Không phải bug code; giảm tải (độ phân giải, tần số vẽ) |
| `proxy_encoding`=1 trùng đoạn xấu | [4] H6 | Hoãn tạo proxy tới lúc rảnh / đặt độ ưu tiên thấp |
| `metal_draws` > 0 khi T0 | [5] H7 | Dừng vòng vẽ khi đứng yên (`isPaused`, `enableSetNeedsDisplay`) |
| `metal_draw_ms` cao | [5] H8 | Bỏ `item.asset.tracks` đồng bộ khỏi `draw()` (cache transform) |
| Mọi số phẳng và tốt nhưng người dùng vẫn thấy giật | H9 / thứ chưa đo được | Quay màn hình 120 fps / Instruments; bổ sung số đo (§11) |
| `seek_superseded` rất cao + `display_age` cao | [3] bão tắc seek | Giảm tần suất gửi seek (throttle theo `seek_service`), không phải đổi decoder |

**Cấm:** đổi decoder, đổi sang Metal, viết lại clock khi bảng này chưa chỉ về đó.

## 8. Hiệu ứng người quan sát & giới hạn của lớp đo

- Bộ đo có **một `CADisplayLink` riêng + một timer 1 Hz** khi đang ghi. Chi phí nhỏ
  nhưng không bằng 0. **Luôn đo với panel HUD thu gọn.** So sánh hai lần chạy cùng
  điều kiện thì độ nhiễu triệt tiêu.
- Hook chỉ thêm vào bộ đệm có khoá; p50/p95, ghi CSV, cập nhật HUD làm **một lần/giây**.
- `PlaybackMetrics` **không** `@Observable` (hook được gọi trong `body`; một thuộc tính
  được quan sát ở đó sẽ tự tạo ra đúng cái invalidation mà ta đang đi tìm).
- **Không đo được:** thời điểm khung thật sự lên màn hình (đường `AVPlayerLayer`);
  thời gian từ chạm Play đến khung đầu tiên chạy; thời gian GPU; chất lượng cảm nhận
  (H9). `display_age_ms` là suy luận từ sổ sách seek.
- `frame_gap_ms` chỉ đo main run loop còn phản hồi hay không, không đo GPU/compositor.
- Dòng đầu CSV là giây khởi động, không dùng để so sánh.
- Số simulator ≠ số thiết bị.

### Điểm gắn đo (hook inventory)

| File | Gắn gì |
|---|---|
| `Playback/PlaybackMetrics.swift` | bộ thu, CADisplayLink, CSV, trend |
| `UI/Editor/PlaybackMetricsHUD.swift` | HUD + Start/Stop + chia sẻ CSV |
| `UI/Account/AccountView.swift` | công tắc Developer |
| `Playback/PlayerSeekCoordinator.swift` | `seek_*`, `display_age` (sổ sách), `unserved` |
| `Playback/EditorPlaybackEngine.swift` | `set_time_calls`, probe (mode, sessions, proxy, encoding), `engines_alive` |
| `Playback/StagePlayerSession.swift` | `sessions_alive` |
| `UI/Editor/TimelineView.swift` | `drag_events`, `input_handler_ms`, `timeline_body_evals` |
| `UI/PreviewCanvas.swift` | `sample_layer_ms`, `layer_body_evals`, `metal_*` |
| `UI/Editor/EditorShellView.swift` | `shell_body_evals`, gắn HUD |

Probe của engine được đăng ký trong `prepare()`, **không** trong `init` (init chạy cho
cả engine "thừa" mà `EditorShellView.init` tạo ra — chính nhận định này dẫn tới H3).

## 9. Nhật ký kết quả đo

Mẫu mỗi mục:

```
### YYYY-MM-DD · Txx · <máy, iOS> · build <commit/diff>
file: playback-Txx-….csv
first10s → last10s: seek_service p95 _→_ · frame_gap p95 _→_ · memory _→_ · engines_alive _
nhận xét: (số nào xấu / tăng; mắt thấy gì)
kết luận: giả thuyết nào được xác nhận / bác bỏ → việc kế tiếp
```

### 2026-10-09 · KIỂM TRA CÔNG CỤ ĐO (không phải baseline) · simulator iPhone 17

Driver giả lập kéo sin 26 s, gọi thẳng `engine.scrub(toMs:)` (không qua `DragGesture`
nên `drag_events` do driver tự đếm, `input_handler_ms` trống), clip portrait 31.2 s, proxy đã có sẵn.

| | first10s | last10s |
|---|---|---|
| seek service p95 (ms) | 9.6 | 7.8 |
| seek end-to-end p95 (ms) | 9.6 | 7.8 |
| display age p95 (ms) | 23.0 | 16.1 |
| frame gap p95 (ms) | 21.0 | 16.7 |
| dropped frames/s | 1.7 | 0.0 |
| shell body evals/s | **0** | **0** |
| timeline evals/s | 56.6 | 46.1 |
| memory (MB) | 542 | 581 |
| cpu % | 84.9 | 39.8 |

Điều công cụ đo xác nhận hoạt động: counter, p50/p95, gauge, probe, settle (16.7 ms
ghi được ở lần thả tay), trend, CSV, HUD. Lỗi **của công cụ** tìm thấy và đã sửa: (1) probe
đăng ký trong `init` trỏ nhầm engine thừa → mode luôn báo `idle`; (2) bộ đếm timeline
đặt trong `body` đếm 0 vì nội dung nằm trong closure `GeometryReader`.

Quan sát (CHƯA là kết luận, simulator + driver giả): bộ nhớ 346 MB → ~570 MB trong ~3 s
đầu rồi gần phẳng; rớt khung tập trung ở vài giây đầu. Cần T1/T3 trên máy thật để biết.

### Baseline trên máy thật — **CHƯA ĐO**
- [ ] T0 · [ ] T1 · [ ] T2 · [ ] **T3** · [ ] T4 · [ ] T5 · [ ] T6 · [ ] T7

## 10. Nhật ký quyết định / bằng chứng

### Bằng chứng trước tài liệu này (đã có, đáng tin ở mức ghi chú)

- **Seek trên file gốc rất chậm, trên proxy all-intra gần như bằng 0.** Tab Proxy Test,
  simulator, clip 31.2 s: seek zero-tolerance trung bình **1124 ms** (258–2354) trên
  bản gốc (keyframe/250 khung) vs **5 ms** (3–14) trên proxy all-intra 960 px; proxy
  nhỏ hơn (34.8 → 15.9 MB), tạo mất ~34–41 s một lần. → proxy giải quyết keyframe-walk,
  **không** giải quyết "kém dần".
- **`AVAudioEngine` đứng riêng:** 20/20 chu kỳ attach→play→stop→detach chạy sạch
  (4.8 s, heartbeat không dừng). Bằng chứng ban đầu "AudioMixEngine treo cứng" **không đủ
  chắc** — lần treo duy nhất log dừng trước cả dòng đầu của vòng kế tiếp; chưa lặp lại,
  chưa có nguyên nhân. Đừng coi audio là thủ phạm cho tới khi có số đo.
- **Bẫy SDK:** `AVAudioPlayerNode.scheduleSegment/scheduleFile` có thêm bản `async`
  cùng chữ ký; gọi từ hàm `async` Swift tự chọn bản async, chờ phát xong mới trả về →
  treo nếu gọi trước `engine.start()`. Code thật miễn nhiễm vì toàn bộ chuỗi gọi là hàm
  đồng bộ.
- **Momentum không phải nguyên nhân** (quan sát của người dùng khi tách vào sandbox).
- Sơ đồ clock từng chặn bởi `framesReady` (đường `VideoFrameServer` cũ) đã bị thay bằng
  `AVPlayer` + `PlayerSeekCoordinator`; `VideoFrameServer` giờ chỉ là dự phòng.

### Nhật ký thay đổi (một dòng/thay đổi: giả thuyết · số trước · số sau · kết luận)

| Ngày | Thay đổi | Giả thuyết | Trước | Sau | Kết luận |
|---|---|---|---|---|---|
| 2026-10-09 | `StagePreview` cô lập `currentTimeMs` khỏi `EditorShellView.body` | shell bị dựng lại mỗi tick | (chưa đo) | `shell_body_evals` = 0 | **đúng**: shell không dựng lại. Chưa biết có cải thiện cảm giác không |
| 2026-10-09 | Thêm lớp đo + HUD + T0–T7 | cần số đo trước khi sửa | — | — | công cụ, không phải sửa |

## 11. Backlog đo thêm (khi bảng §7 chỉ về một khoảng trống)

- Thời gian từ chạm Play đến khung đầu tiên thật sự chạy (T4).
- Khung nào thật sự lên màn hình (đường `AVPlayerLayer`) — `AVPlayerItemVideoOutput`
  chỉ để đo, hoặc quay màn hình 120 fps.
- Thời gian GPU của đường Metal (`MTLCommandBuffer.gpuStartTime/gpuEndTime`).
- `os_signpost` quanh seek/draw để xem trong Instruments.
- Đếm số lần `EditorShellView.init` chạy (kiểm chứng trực tiếp H3).
- Ghi nhiệt độ theo thời gian dài (10+ phút) trên máy thật.
