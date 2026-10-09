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
- Proxy transcode không phải nguyên nhân (nó chỉ bỏ chi phí keyframe-walk khi nhảy xa). **Đã bỏ proxy khỏi pipeline 2026-10-09** (quyết định của người dùng, xem §10).
- Sau khi đo T3 lần đầu (§9): hết khựng, nhưng **momentum không giống quán tính thật** (cảm giác bị phanh/bị chặn).
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
│ Nguồn: file gốc (đã bỏ proxy 2026-10-09)                           │
│   clip mẫu: keyframe mỗi 250 khung (hiếm gặp); video quay bằng     │
│   iPhone thường ~mỗi 30 khung. Xem rủi ro ở §10.                    │
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

**Không còn đường decode nào khác.** `VideoFrameServer`/`AVAssetReader`/`CGImage` (đường cũ) bị xoá 2026-10-09;
engine, dung sai seek (hằng số 0.2 s) và proxy cũng đã được đơn giản hoá (xem nhật ký thay đổi §10).
Bước [4] giờ chỉ là `AVPlayer` đọc file gốc.

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
| H3 | `EditorShellView.init` tạo `EditorPlaybackEngine` mới mỗi lần struct bị tạo lại (`State(initialValue:)` đánh giá biểu thức mỗi lần) → mỗi engine tạo AVPlayer. **Bằng chứng đầu tiên 2026-10-09: `engines_alive` = 2 khi mở 1 clip (§9). Chưa biết vì sao engine thừa bị giữ sống, chưa biết có tăng theo thời gian không (cần T3).** | `engines_alive` > 1 hoặc tăng | luôn = 1 |
| H4 | Main thread nghẽn khi kéo lâu (SwiftUI/Runtime) | `frame_gap_ms_p95`/`dropped_frames` tăng; `seek_hop_ms_p95` tăng | phẳng |
| H5 | Máy nóng, tự hạ xung (chỉ máy thật) | `thermal_state` ≥ 2 cùng lúc các số khác xấu đi | `thermal_state` = 0 |
| H6 | ~~Tạo proxy chạy chồng lúc người dùng đã kéo~~ | **không còn áp dụng** (proxy đã bỏ) | — |
| H7 | Vòng vẽ Metal chạy ngầm khi đứng yên (đường filter) | `metal_draws` > 0 trong T0 | = 0 |
| H8 | `draw()` Metal gọi đồng bộ `item.asset.tracks(...)` mỗi khung | `metal_draw_ms_p95` cao, nhất là lúc seek (T6) | thấp, phẳng |
| H9 | Tolerance 0.2s lúc kéo làm hình "nhảy bậc" dù seek nhanh | `display_age_ms` thấp nhưng người dùng vẫn thấy giật | — (cần mắt nhìn, không có số) |

**Đã xác nhận (2026-10-09, simulator, driver giả lập):**
- `shell_body_evals` = 0 suốt khi scrub → `EditorShellView.body` không còn bị dựng lại mỗi tick (fix #1 có hiệu lực).
- `engines_alive` = 2 và `sessions_alive` = 2 với 1 clip, trong khi kỳ vọng là 1 (H3). Chỗ duy nhất tạo engine trong app là `EditorShellView.init` (`EditorShellView.swift:67`).

**Sau lần đo T3 đầu tiên trên iPhone 13 thật (§9, 2026-10-09):**

| Giả thuyết | Trạng thái | Căn cứ |
|---|---|---|
| H1 AVPlayer tích tụ, seek chậm dần | **bị bác bỏ cho lần đo này** | `seek_service_ms_p95` phẳng ~9–11 ms suốt 184 s |
| H2 rò rỉ bộ nhớ | **bị bác bỏ cho lần đo này** | `memory_mb` 308 → 308 |
| H3 engine thừa | **đúng nhưng cố định, không tăng** | `engines_alive` = 2 từ đầu đến cuối |
| H4 main thread nghẽn | **bị bác bỏ cho lần đo này** | `dropped_frames` = 0 cả 185 giây; `frame_gap` phẳng |
| H5 nhiệt | **bị bác bỏ cho 3 phút này** | `thermal_state` = 1 không đổi |
| H6, H7, H8 | chưa thử (T1, T0/T6 trên máy thật) | — |
| H9 hình nhảy bậc do tolerance | **gần như bị bác bỏ** (máy thật): `seek_landing_error` p50 0 ms, p95 25 ms | — |
| H11 | Bộ nhớ tăng do `VideoFrameCache.cache` giữ mọi thumbnail filmstrip (+ batch bị bỏ dở vẫn chạy) | `memory_mb` phẳng sau khi bỏ ghi cache và huỷ batch, cùng kịch bản (trước: 29 → 316 MB / 100 s) | vẫn tăng → tìm nguồn khác (VideoToolbox/AVPlayer) |
| H12 | Khung rớt sau khi bấm Play do khởi động `AVAudioEngine` đồng bộ trên main + engine âm thanh chạy tiếp | `frame_gap_ms_max` ≈ 190 ms tại lần Play đầu; `dropped_frames` > 0 kéo dài sau Pause (quan sát 2026-10-09). Cần: chạy có/không Play; thử khởi động engine trước (lúc mở editor) | không rớt khung dù có Play |
| H10 | **(máy thật, keyframe dày: BỊ BÁC BỎ — không nhanh hơn, lệch gấp đôi; simulator đã dự đoán sai — §9)** Editor thật chọn **độ chính xác khung theo tốc độ nội dung** (gắn với mức zoom timeline): lướt nhanh → seek tới khung gần nhất/keyframe (rẻ, mắt không phân biệt), chậm/dừng → đúng khung. Pipeline hiện tại dùng dung sai cố định 0.2 s bất kể tốc độ (dung sai thích ứng từng có, mất sau các lần viết lại). Chỉ hiệu quả khi keyframe dày (clip mẫu keyframe/250 khung: vô dụng; video iPhone ~1 s: dùng được) — **bổ sung cho proxy, không thay thế** | thử dung sai thích ứng: `seek_service_ms_p95` giảm, `seek_completed`/s tăng, `seek_landing_error_ms` tăng (cái giá phải trả) trên clip GOP 29 và clip mẫu GOP 250 | không đổi `seek_service`, hoặc landing error tăng tới mức hình sai lệch rõ |

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

### [1b] Momentum (thả tay → trôi)
| Cột | Đo gì | Ngưỡng / cách đọc |
|---|---|---|
| `coast_release_speed_*` | tốc độ lúc thả tay, ms timeline / giây (không phải ms) | để biết cú vuốt thực tế nhanh cỡ nào (0.2 px/ms: 10 000 ms/s = 2000 px/s) |
| `coast_duration_ms_*` | thời gian một lần trôi kéo dài | so với mô hình: `MomentumDecay` dự đoán `ln(v0/50)/2.0` giây |
| `coast_distance_ms_*` | quãng timeline một lần trôi đi được | mô hình dự đoán `v0/2.0` nếu không chạm biên |
| `coast_ended_friction` | số lần trôi tắt dần vì ma sát (đúng ý) | — |
| `coast_ended_edge` | số lần **dừng cứng vì chạm đầu/cuối timeline** | nếu chiếm phần lớn → "bị chặn để vừa khung" là thật, việc kế tiếp là xử lý biên |
| `coast_interrupted` | số lần chạm tay lại khi đang trôi | — |

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
| `seek_service_ms_*` | từ lúc gọi `AVPlayer.seek` đến completion handler = công việc của AVFoundation | p95 < 33 ms; **không tăng theo thời gian** (khi còn proxy, T3 đo được ~10 ms) |
| `seek_e2e_ms_*` | từ lúc `request` đến completion = gồm cả thời gian chờ sau seek trước | p95 < 50 ms |
| `seek_hop_ms_*` | từ completion handler đến lúc main actor chạy `Task` = **độ tắc main thread** | p95 < 5 ms |
| `unserved` (gauge) | 1 nếu còn seek chưa phục vụ ở thời điểm lấy mẫu | — |

### [4] Decode / nguồn
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `player_sessions` | số `StagePlayerSession` của engine đang dùng | = số layer video |
| `sessions_alive` | tổng `StagePlayerSession` còn sống toàn app | = `player_sessions` |
| `engines_alive` | tổng `EditorPlaybackEngine` còn sống | **= 1** khi editor mở |
| `sources_total` | số layer video của engine | = `player_sessions` |

### [0] Cảm nhận người dùng
| Cột | Đo gì | Ngưỡng |
|---|---|---|
| `display_age_ms_*` | trong lúc còn seek chưa phục vụ: tuổi của mục tiêu của khung đang hiện = `now − max(thời điểm bắt đầu đoạn chưa phục vụ, request của seek hoàn tất gần nhất trong đoạn đó)`. 0 khi hình đã khớp playhead. **Suy ra từ sổ sách seek, không phải thời điểm photon lên màn hình.** *Định nghĩa đã sửa 2026-10-09 (§10): bản đầu tính từ seek hoàn tất trước đó nên cộng cả khoảng nghỉ vào, số lần đo T3 đầu tiên không dùng được.* | p95 < 50 ms |
| `seek_landing_error_ms_*` | sai lệch giữa thời điểm đã yêu cầu và thời điểm `AVPlayer` thật sự dừng lại sau khi seek xong (`abs(currentTime − target)`). Với tolerance 0.2 s lúc kéo, sai lệch tới 200 ms là *được phép*; đây là thước đo H9 (hình "nhảy bậc") | chỉ để so sánh, chưa có ngưỡng |
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
3. Mở một project vào editor. Một viên thuốc `metrics` hiện phía trên Stage, dưới nút Huỷ.
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
| T1 | Mở editor lần đầu (khởi chạy lại app), kéo chậm tiến | 20 s | `dropped_frames` 5 s đầu, `seek_service`, `memory_mb` | không rớt khung lúc khởi động |
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
| `Playback/SeekTolerancePolicy.swift` | chính sách dung sai (`fixed`/`adaptive`), công tắc A/B `PLAYBACK_SEEK_POLICY` |
| `UI/Editor/TimelineZoom.swift` | giới hạn zoom, bậc thang thước, cửa sổ hiển thị (thuần, có test) |
| `Playback/EditorPlaybackEngine.swift` | `set_time_calls`, `scrub_speed_msps`, `seek_tolerance_ms`, probe (mode, sessions, sources), `coast_*`, `engines_alive` |
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
nên `drag_events` do driver tự đếm, `input_handler_ms` trống), clip portrait 31.2 s (lúc đó còn dùng proxy).

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

### 2026-10-09 · T0 (idle 14 s) · simulator iPhone 17 · kiểm tra cột mới (không phải baseline)

Mở 1 project 1 clip, không chạm. Kết quả đáng chú ý:

| | giá trị |
|---|---|
| `metal_draws` | 0 (H7 không xảy ra trên đường không filter — chưa thử có filter) |
| `shell_body_evals`, `timeline_body_evals` | 0 khi đứng yên |
| `engines_alive` | **2** (kỳ vọng 1) |
| `sessions_alive` | **2** (kỳ vọng 1) |
| `memory_mb` | 527 → 575 (≈ 4 s đầu), rồi phẳng |
| `cpu_percent` | 52 → 12 |

→ **H3 có bằng chứng đầu tiên**: có một engine thứ hai (và một `AVPlayer` thứ hai) đang
sống. Việc kế tiếp theo §7 **không phải sửa ngay** mà là đo T3 trên máy thật và xem
`engines_alive`/`sessions_alive`/`memory_mb` có **tăng** theo thời gian không — vì một
engine thừa cố định (2 thay vì 1) khác hẳn với engine thừa tích tụ (2, 3, 4…).
Lưu ý: lần chạy này dùng mở editor tự động bằng code kiểm chứng tạm, chưa phải đường người
dùng thật.

### 2026-10-09 · T3 · iPhone 13 (iPhone14,5) · build Debug sau commit e2d173a
file: `playback-T3-20261009-172401.csv` (185 dòng, 184 s). Đo không người giám sát qua `devicectl`.

| | first10s | last10s | max |
|---|---|---|---|
| seek service p95 (ms) | 10.0 | 11.1 | 33.9 |
| seek end-to-end p95 (ms) | 12.3 | 12.0 | 33.9 |
| seek main-hop p95 (ms) | 0.8 | 0.1 | 13.4 |
| frame gap p95 (ms) | 16.6 | 16.6 | 16.6 |
| dropped frames/s | 0.0 | 0.0 | 0.0 |
| shell body evals/s | 0 | 0 | 0 |
| memory (MB) | 308.8 | 308.0 | 311 |
| cpu % | 34.9 | 27.9 | 45.1 |
| thermal | 1 | 1 | 1 |
| engines_alive / sessions_alive | 2 / 2 | 2 / 2 | 2 / 2 |

Theo cửa sổ 20 s: không cột nào tăng dần (svc p95 8.6–11.5 ms, mem 308.8–309.8 MB, CPU 27–35%).
Tổng: 8782 seek được yêu cầu, 8554 hoàn tất (phần chênh là seek bị đè có chủ đích); `seek_cancelled` = 1.

**Hạn chế của lần đo này (quan trọng):**
- Chế độ trong 185 s: **coasting 146 s, idle 36 s, scrubbing chỉ 3 s.** `drag_events` trung bình 4/s.
  Cử chỉ thực tế là rất nhiều cú flick rồi để trôi (`mode_changes` = 413), *không phải* kéo liên tục
  bằng ngón tay. T3 đúng nghĩa ("kéo qua lại liên tục") chưa được đo.
- `display_age_ms` lần này **không dùng được**: max từng giây lên tới 1.8–2.1 s trong khi seek chỉ mất
  ≤ 34 ms. Nguyên nhân là lỗi định nghĩa của công cụ (tính từ seek hoàn tất *trước* khoảng nghỉ, nên cộng cả
  khoảng nghỉ vào). Đã sửa (xem §10).
- Người dùng nói bộ ghi **không tự dừng** sau 180 s. CSV cho thấy ghi dừng ở 184.2 s và dòng cuối có mode
  `idle`, tức nhìn từ file thì đã dừng. Chưa rõ người dùng thấy gì trên HUD — cần hỏi lại.
- Chưa ghi nhận cảm giác mượt/giật của người dùng trong lần chạy này.

**Kết luận:** ở các tầng đã đo, **pipeline không xấu đi trong 3 phút** với kiểu thao tác này: không rớt khung,
seek nhanh và phẳng, bộ nhớ phẳng, nhiệt ổn định. Nếu người dùng vẫn cảm thấy kém dần thì nguyên nhân hoặc
(a) nằm ở thứ chưa đo được — khung thật sự lên màn hình, độ "nhảy bậc" do tolerance (H9), hoặc
(b) chỉ xuất hiện với kiểu thao tác khác (kéo liên tục bằng ngón tay, mode `scrubbing`). Việc kế tiếp: chạy lại
T3 với kéo liên tục và xem `seek_landing_error_ms`, `display_age_ms` (đã sửa).

### 2026-10-09 · T3 tổng hợp · simulator iPhone 17 · SAU KHI BỎ PROXY + momentum mới (không phải baseline)

Driver giả lập (không phải ngón tay thật): 20 s kéo qua lại hình sin + 6 cú flick tốc độ biết trước
(±3000, ±6000, ±12000 ms/s) từ giữa timeline. Cùng driver với lần đo có proxy trước đó.

**Seek, kéo qua lại liên tục 20 s, p95 mỗi giây (mean):**

| Nguồn video | seek service | settle | rớt khung (tổng) |
|---|---|---|---|
| có proxy (720p, keyframe/10 khung) — lần đo trước | ~7–10 ms | ~16 ms | ≈ 0–3 |
| **không proxy**, clip giả iPhone (1080×1920, keyframe/29 khung, 10 Mbps) | 60–396 ms (≈230) | 58 ms | 27 |
| **không proxy**, clip mẫu gốc (1080×1920, keyframe/250 khung) | 242–2457 ms (≈1100) | 883–1450 ms | ≫ |

Clip giả iPhone do tôi tự mã hoá lại clip mẫu ở **độ phân giải gốc** với keyframe mỗi 29 khung (đã kiểm bằng
đếm sync sample: 37 keyframe / 940 khung, khoảng cách tối đa 29). `display_age` p95 lần lượt ~50 ms (có proxy,
ước lượng) → 390–650 ms (GOP 29) → 2–4 s (GOP 250).

**Momentum (mô hình `MomentumDecay`, k = 2.002/s) so với số đo:**

| Tốc độ thả | Thời gian trôi (đo / mô hình) | Quãng trôi (đo / mô hình) | Kết thúc |
|---|---|---|---|
| ±3000 ms/s | 2050 / 2045 ms | 1474 / 1498 ms | ma sát |
| ±6000 ms/s | 2400 / 2390 ms | 2972 / 2997 ms | ma sát |
| ±12000 ms/s | 550 / 549 ms | 4000 (chạm biên) | **chạm biên** |

Mô hình khớp số đo. Lưu ý về biên: dự án mẫu dài 8 s = 1600 px (0.2 px/ms); một cú vuốt mạnh (12000 ms/s
= 2400 px/s) từ giữa timeline chạm biên chỉ sau 0.55 s. `UIScrollView` thật cũng sẽ đi xa cỡ đó với cùng tốc độ. Với dự án ngắn,
dừng cứng ở biên là hành vi thường gặp → xem `coast_ended_edge` trong các lần đo thật.

**Kết luận (simulator, driver giả — chưa phải thiết bị thật):** momentum mới đúng như mô hình. Còn **bỏ proxy
làm seek chậm đi 8–110 lần** trên simulator, kể cả với clip có keyframe dày kiểu iPhone. Chưa đo trên iPhone
thật (bộ giải mã phần cứng khác simulator) — đây là số đo quyết định cho việc bỏ proxy.

### 2026-10-09 · iPhone 13 thật · bản KHÔNG proxy + momentum mới (so với bản có proxy)

files: `playback-T0-20261009-174726.csv` (78 dòng, 77 s — **nhãn T0 là nhầm**: người dùng bấm Start trên HUD
khi kịch bản mặc định đang là T0 nên lần ghi tự động T3 bị chặn; thực chất đây là một lần kéo/flick như T3),
so với `playback-T3-20261009-172401.csv` (có proxy, 184 s). Cả hai: cùng máy, cùng clip, kiểu thao tác "flick
liên tục" (≈80% thời gian ở chế độ coasting). Trung bình trên các giây có seek.

| | A: có proxy | B: không proxy |
|---|---|---|
| seek service p50 (ms) | 5.5 | 28.6 |
| **seek service p95 (ms)** | **9.7** | **159.6** (max 194) |
| seek end-to-end p95 (ms) | 11.8 | 167.8 |
| display age p95 (ms, định nghĩa đã sửa chỉ ở B) | — | 264 |
| seek hoàn tất /s | 47.8 | 27.5 |
| seek bị đè /s | 1.3 | 24.9 |
| khung rớt /s | 0 | 0 |
| frame gap p95 (ms) | 16.6 | 16.6 |
| memory MB | 309.3 | 309.5 |
| cpu % | 32.6 | 16.7 |
| landing error p50 / p95 (ms) | — | 0 / 25 |

Không proxy trên **máy thật**: seek chậm hơn ~16 lần (p95 10 → 160 ms), số khung hình cập nhật/s tụt
48 → 28, hình trễ sau playhead ~160–260 ms. Main thread vẫn mượt (không rớt khung, bộ nhớ phẳng, CPU thấp hơn vì
làm ít việc hơn). Tệ hơn proxy nhưng **nhẹ hơn nhiều so với simulator** (≈1100 ms với cùng clip): bộ giải mã
phần cứng của iPhone nhanh hơn. Clip dùng ở đây vẫn là clip mẫu keyframe/250 khung; clip quay bằng iPhone
(keyframe ~30 khung) **chưa đo trên máy thật**.

`seek_landing_error` p50 = 0 ms, p95 ≈ 25 ms → tolerance 0.2 s **không** gây "nhảy bậc" đáng kể (H9 gần như
bị bác bỏ: AVPlayer dừng đúng nơi được yêu cầu).

**Momentum (B, 77 s): 107 lần trôi — chỉ 1 lần tắt dần tự nhiên vì ma sát.**

| Kết thúc | Số lần | Tỉ lệ |
|---|---|---|
| ma sát (đúng ý) | 1 | 1% |
| **chạm biên timeline** | **38** | **36%** |
| **bị chạm tay ngắt giữa chừng** | **68** | **64%** |

Tốc độ thả: median **12 253 ms/s ≈ 2450 px/s** (cú vuốt rất mạnh), max 24 172. Dự án mẫu chỉ dài 8 s = 1600 px;
theo mô hình một cú 12 253 ms/s đi tổng cộng 6100 ms (76% cả dự án) và chạm biên sau ~0.55 s. Thời gian trôi
median 457 ms là do **bị cắt bởi biên hoặc bởi tay**, không phải do ma sát. → Giả thuyết cũ "ma sát quá mạnh" đã
được sửa; còn lại giải thích "bị chặn để vừa khung hình" là **timeline quá ngắn + dừng cứng ở biên** (36%) và
việc người dùng chạm lại liên tục (64%).

### 2026-10-09 · THÍ NGHIỆM H10: dung sai seek thích ứng theo tốc độ · simulator iPhone 17 (driver giả, chưa phải máy thật)

Cùng driver (20 s kéo qua lại hình sin, content speed median ≈ 3.6 s/s, rồi 6 cú flick), 2 clip × 2 chính sách,
dự án 8 s lúc đó. `adaptive` = `tolerance = clamp(tốc độ nội dung × 0.1 s, 0, 2 s)`; `fixed` = 0.2 s như cũ.
Số liệu: trung bình các giây của 20 s kéo liên tục.

| | fixed / GOP 250 | adaptive / GOP 250 | fixed / GOP 29 | adaptive / GOP 29 |
|---|---|---|---|---|
| seek service p50 (ms) | 942 | 580 | 66 | **3.2** |
| seek service p95 (ms) | 1086 | 928 | 147 | **76** |
| seek hoàn tất /s | 0.9 | 1.7 | 18.8 | **41.2** |
| display age p95 (ms) | 2033 | 1633 | 261 | **144** |
| landing error p50 (ms) | 0 | 0 | 1.8 | **108** |
| landing error p95 (ms) | 0 | 0 | 175 | **385** |
| tolerance p50 (ms) | 200 | 348 | 200 | 361 |
| settle p95 (ms, phần flick) | 642 | 389 | 8 | **0** |

Đọc kết quả:
- **Keyframe dày (GOP 29) + dung sai thích ứng**: seek nhanh hơn 20× ở median (66 → 3.2 ms), số khung cập nhật/s
  tăng 2.2× (18.8 → 41.2), hình trễ giảm gần một nửa. **Cái giá:** khung hiện ra lệch so với điểm yêu cầu median
  ~0.1 s, p95 ~0.39 s *trong lúc đang chuyển động* (lúc dừng thì chính xác: settle 0 ms).
- **Keyframe thưa (GOP 250)**: thích ứng chỉ cải thiện nhẹ (p95 1086 → 928 ms), vẫn ~1 giây mỗi seek. Cửa sổ dung
  sai (≈ ±0.35–0.5 s) không bao giờ chứa được keyframe cách nhau 8 s. Đúng như dự đoán: **dung sai thích ứng không
  thay thế được keyframe dày**.
- Trên GOP 29 dung sai vẫn chưa phủ hết khoảng cách keyframe (0.97 s) nên còn ~1/4 số seek phải "đi bộ"
  (p95 76 ms). Hệ số 0.1 s là điểm khởi đầu, chưa tối ưu.

Chính sách mặc định **vẫn là `fixed`** (`SeekTolerancePolicy.defaultPolicy`) cho tới khi có số đo máy thật.
Bật A/B bằng biến môi trường `PLAYBACK_SEEK_POLICY=adaptive|fixed` (Debug).

### 2026-10-09 · H10 trên iPhone 13 thật: dung sai cố định vs thích ứng · clip keyframe dày (GOP 29, 1080p) · dự án 31.2 s

files: `playback-T3-fixed-gop29-20261009-185353.csv` (78 s) và `playback-T3-adaptive-gop29-20261009-190244.csv` (45 s,
người dùng dừng sớm). Kiểu thao tác: flick + kéo + pinch zoom (213–224 sự kiện pinch mỗi lượt, zoom 0.01–1.44 px/ms).
Trung bình các giây có seek.

| | fixed 200 ms | adaptive | |
|---|---|---|---|
| seek service p50 / p95 (ms) | 7.6 / 23.0 | 4.2 / 23.6 | p95 không đổi |
| seek hoàn tất /s | 45.2 | 47.3 | +5% |
| display age p95 (ms) | 24.4 | 21.5 | không đổi |
| landing error p95 (ms) | 154 | **307** | **gấp đôi** |
| tolerance p50 (ms) | 200 | 499 | |
| khung rớt | 2 / 78 s | 0 / 45 s | |

**Theo mức zoom (px/ms):**

| | seek p95 (ms) | seek /s | landing p95 | tolerance p50 |
|---|---|---|---|---|
| fixed · xa (<0.1) | 27.1 | 43.5 | 163 | 200 |
| fixed · giữa (0.1–0.5) | 24.7 | 47.0 | 159 | 200 |
| fixed · gần (≥0.5) | **19.7** | 45.1 | 145 | 200 |
| adaptive · xa | 29.2 | 33.5 | 343 | **1275** |
| adaptive · giữa | 21.1 | 50.1 | 386 | 407 |
| adaptive · gần | 24.7 | 51.9 | 96 | 92 |

**Kết luận (máy thật, footage keyframe dày):**
1. Dung sai thích ứng **không làm nhanh hơn** (p95 23.0 vs 23.6 ms) mà làm khung hiện lệch gấp đôi. Mô phỏng
   simulator dự đoán tăng gấp đôi số khung/s — **sai trên máy thật**, vì giải mã trên simulator chậm hơn nhiều
   so với bộ giải mã phần cứng của iPhone. (Bài học: simulator không dùng được để đánh giá tối ưu giải mã.)
2. Ngay cả zoom ra xa với dung sai 1.27 s (chỉ nhảy keyframe), seek vẫn ~29 ms; zoom vào gần đòi chính xác từng
   khung vẫn chỉ ~20 ms. **Zoom gần không đắt hơn zoom xa** với footage này → không có chi phí để tiết kiệm bằng
   cách giảm độ chính xác theo mức zoom.
3. Sàn ~20 ms/seek và trần ~47 seek/s **không đến từ giải mã** (dung sai rộng hay hẹp đều như nhau): mỗi seek
   hoàn tất tuần tự một lần (1/0.021 s ≈ 47). Muốn lên 60 seek/s cần cách khác, không phải giảm độ chính xác.
4. Cảm giác "mượt hơn hẳn" của lượt cố định+clip GOP 29 so với lượt trước đến từ **keyframe dày** (GOP 250 → 29:
   seek p95 160 → 23 ms) và timeline 31 s (coast chạm biên 36% → 20%), **không phải** từ chính sách thích ứng.

→ H10 **không được máy thật ủng hộ cho footage keyframe dày**. Còn có thể hữu ích cho nguồn keyframe thưa nhưng
khi đó cửa sổ dung sai không chứa nổi keyframe (cách nhau 8 s) nên cũng vô dụng. `SeekTolerancePolicy.defaultPolicy`
giữ `fixed`.

### 2026-10-09 · T3 · iPhone 13 thật · FOOTAGE iPHONE THẬT, không proxy, dung sai cố định 200 ms

file `playback-T3-real-iphone-20261009-192741.csv` (116 dòng, 115 s). Clip `iphone-footage.MOV`: HEVC, 1080×1920,
60 fps, 17.6 Mbps, SDR 8-bit, keyframe mỗi 30 khung (0.5 s), có B-frame, có tiếng, 89.8 s. Người dùng: "mượt hơn
hẳn" (kể cả app Ảnh của iOS cũng giật với clip stock cũ → clip stock là nguyên nhân chính của "lỗi playback" trước đó).
Chế độ: coasting 82 s, idle 27 s, playing 7 s. 240 sự kiện pinch, zoom 0.01–1.44 px/ms (đủ cả hai cực trị).

| | giá trị |
|---|---|
| seek service p50 / p95 / max (ms) | 5.5 / 40.3 / 73 |
| seek hoàn tất /s | 43 (51–59 lúc coasting thường) |
| display age p95 (ms) | 42 |
| landing error p95 (ms) | 182 (dung sai 200 ms) |
| khung rớt | 32 / 115 s — **31 trong 20 s cuối (sau khi bấm Play)**, 2 trong 94 s đầu |
| frame gap max (ms) | 191.7 (đúng lúc bấm Play lần đầu, t=95) |
| bộ nhớ (MB) | **29 → 316** (tăng đều ~3 MB/s trong 100 s đầu, đi ngang ~313 ở 20 s cuối) |
| cpu % trung bình / thermal | 19 / 1 |
| coast: ma sát / chạm biên / bị tay ngắt | 1 / 16 / 86 |

**Theo bậc thước (mức zoom):**

| thước (ms) | giây | seek p95 | seek /s | age p95 | tốc độ nội dung (ms/s) |
|---|---|---|---|---|---|
| 33.3 (**1 khung**) | 20 | **34.5** | **54.4** | 49 | 1 265 |
| 66.7 | 1 | 33.3 | 17.0 | — | 538 |
| 166.7 (5 khung) | 20 | 39.0 | 52.6 | 35 | 4 938 |
| 500 (mặc định) | 47 | 42.3 | 39.1 | 41 | 10 023 |
| 5000 (**xa nhất**) | 13 | 44.3 | **27.0** | 45 | **160 529** |

Kết luận:
1. **Không cần proxy cho footage iPhone này** (HEVC 1080p60, keyframe 0.5 s) trên iPhone 13: seek p95 ~40 ms, ~43–54
   seek/s, hình trễ ~2.5 khung. Chậm hơn clip stock H.264 GOP 29 (p95 23 ms) vì HEVC 60 fps nặng hơn, nhưng đủ mượt.
   Chưa đo 4K60 / HDR.
2. **Zoom gần chính xác từng khung là rẻ nhất** (p95 34.5 ms, 54 seek/s); zoom xa nhất là đắt nhất về thông lượng
   (27 seek/s) — ở đó mỗi seek nhảy xa khỏi vị trí trước (160 s video mỗi giây), mất tính cục bộ của bộ giải mã. Ý
   "đừng bắt tính hết khung khi zoom gần" **không có căn cứ** với footage này; chỗ duy nhất có thể hưởng lợi từ dung
   sai rộng (nhảy keyframe) là zoom xa — chưa kiểm chứng riêng.
3. **Bộ nhớ tăng 29 → 316 MB** (H11). Nghi phạm cụ thể: `VideoFrameCache.cache` lưu mọi thumbnail filmstrip từng
   tải, không giới hạn, mà chỉ ảnh bìa đọc lại nó. Chưa xác nhận bằng số — đã sửa (bỏ ghi cache + huỷ batch bị bỏ
   dở), cần chạy lại cùng kịch bản để so độ dốc bộ nhớ.
4. **Khung rớt chỉ xuất hiện sau khi bấm Play** (H12): 11 khung rớt + gap 191 ms ngay lúc Play, rồi 1–2 khung/s kéo dài
   tới hết (cả lúc idle/coasting sau Pause); trước Play gần như không rớt. Nghi: khởi động `AVAudioEngine` đồng bộ trên
   main thread lúc Play đầu tiên + engine âm thanh chạy tiếp sau Pause. Chưa có số đo riêng.

### 2026-10-09 · T3 · iPhone 13 thật · SAU ĐƠN GIẢN HOÁ (4 bước) · footage iPhone, dung sai cố định 200 ms · tag `simplified`
Cùng kịch bản với lần trước (người dùng kéo qua lại 150 s, 131 dòng). So với lần "footage iPhone thật, trước đơn giản hoá":

| số đo | trước | sau |
|---|---|---|
| seek service p50 / p95 | 5.5 / 40.3 ms | 4.6 / **27.1** ms |
| seek hoàn tất/s | 43.0 | **54.5** |
| display age p95 | 42 ms | 33 ms |
| khung rớt (cả lượt) / gap tối đa | 32 / 192 ms | **16 / 59 ms** |
| bộ nhớ | 29 → 310 MB | **41 → 43 MB** (đỉnh 54) |
| sessions_alive / engines_alive | 2 / 2 | **1** / 2 (engine thứ hai vẫn bị giữ, vô hại vì không còn player) |

Theo mức zoom (vạch thước 0.17 s…5 s): p95 26–31 ms, 47–57 seek/s, rớt ≈ 0–0.2/s — **không phụ thuộc zoom**.

**Hai điều mới (chưa sửa gì, chờ A/B):**
1. **Hình hiển thị lệch so với mục tiêu seek**: `seek_landing_error_ms` p50 trung vị **75 ms** (≈4–5 khung @60 Hz), p95 ≈190 ms;
   102/107 giây có p50 > 2 khung, ở cả coasting / idle. Phù hợp với dung sai 200 ms trên clip keyframe 0.5 s: AVPlayer
   được phép dừng ở keyframe gần nhất. Khi kéo chậm hình sẽ đứng rồi nhảy từng bậc (nghi phạm cho "không mượt"). Số cũ ở
   clip GOP 29 không so trực tiếp được (khác clip, p50 chỉ 2.8 ms ở tốc độ cao).
2. **Momentum**: 128 cú coast — chỉ **5 % tắt vì ma sát**, 4 % chạm biên, **91 % bị chạm tay ngắt**. Coast trung vị kéo 0.7 s
   (mô hình k≈2.0/s cho cú flick tốc độ trung vị sẽ kéo dài ~2.1 s), quãng trôi trung vị ~1.3 s nội dung. Tốc độ thả
   trung vị ≈ 950 px/s (nhẹ). Kịch bản "kéo qua lại" tự nó khiến tay ngắt coast để đảo chiều → **không tách được "lực quá yếu"
   khỏi "người dùng chủ động đảo chiều"** từ lần chạy này.

### 2026-10-09 · T3 ngắn · simulator iPhone 17 (chuột) vs iPhone 13 thật (ngón tay) · so cảm giác momentum
Hai lần chạy ngắn (sim 25 s, máy thật 43 s), cùng footage iPhone, cùng build. **Lưu ý:** file CSV của lần này bị lệch cột
(mã máy `iPhone14,5` chứa dấu phẩy) — đã vá khi phân tích, build sau đã sửa; zoom khác nhau (sim 0.2, máy thật 0.08 px/ms).

| số đo (khi coasting) | simulator (chuột) | iPhone 13 (ngón tay) |
|---|---|---|
| tốc độ lúc thả, `DragGesture` px/s (p25 / trung vị / p75 / max) | 2469 / **3165** / 4858 / 6334 | 665 / **911** / 1684 / 2125 |
| quãng trôi trung vị (px / ms nội dung) | 1341 / 6704 | 347 / 2555 |
| coast kéo dài trung vị | 1017 ms | 731 ms |
| coast bị tay ngắt | 94 % | 90 % |
| nhịp tick momentum p50 / p95 / max | 16.7 / 33.3 / 46.2 ms | 16.6 / 17.1 / 32.8 ms |
| seek service p95 | 45.6 ms | **26.7 ms** |
| display age p95 | 66 ms | **33 ms** |
| seek hoàn tất/s | 47 | **59** |
| khung rớt/s | 0.61 | **0.06** |
| landing error p50 | 69 ms | 73 ms |

**Đọc:** đường video + nhịp khung trên máy thật *tốt hơn* simulator ở mọi số. Khác biệt cảm giác nằm ở **lực vào**: chuột
vuốt nhanh gấp ~3.5× ngón tay, mà quãng trôi = v₀/k tỉ lệ thẳng với v₀ (sim: 3165/2.0 ≈ 1580 px dự đoán, đo 1341; máy thật:
911/2.0 ≈ 455 px dự đoán, đo 347 — công thức chạy đúng ở cả hai). Màn hình iPhone chỉ rộng 390 pt nên một cú vuốt ngón tay
~900 px/s trôi chưa tới 1.2 màn hình. **Chưa phải bằng chứng "momentum sai"**; mới là "cùng công thức, đầu vào khác".
Hai cột ước lượng của mình (`release_est_px_s`, `release_hold_ms`) lần này **vô nghĩa** (500 000 px/s): handler SwiftUI nhận
nhiều sự kiện cảm ứng trong một lượt nên thời gian lúc xử lý cách nhau vài micro-giây. Đã đổi sang `value.time` (dấu thời gian
của chính cú chạm), chưa đo lại.

### 2026-10-09 · T3 · iPhone 13 thật · momentum gain 2.0 + ma sát ×0.7 (bản đã commit 952071b) · 64 s, zoom 0.03–0.46 px/ms
Một lần chạy, người dùng tự vuốt (72 % coast bị tay ngắt). So với lần máy thật trước (gain 1, ma sát 1, 43 s):

| số đo (khi coasting) | gain 1 | gain 2 · ma sát 0.7 |
|---|---|---|
| tốc độ lúc thả, `DragGesture` trung vị | 911 px/s | **1920 px/s** (vuốt mạnh hơn, và đang zoom gần hơn) |
| quãng trôi trung vị | 347 px | **2138 px (5.5 màn hình)** |
| coast tắt vì ma sát / chạm biên / bị ngắt | 5 / 5 / 90 % | 16 / 12 / 72 % |
| seek service p95, seek/s | 26.7 ms, 59 | 27.4 ms, 59 |
| display age p95, landing error p50 | 33, 73 ms | 30, 74 ms |
| khung rớt / s | 0.06 | 0.13 (7 khung/64 s, 3 trong giây đầu lúc mở app) |

Coast không bị ngắt ở zoom 0.38: trôi 2700–4500 px (7–12 màn hình) trong ~3.8–4.2 s — khớp mô hình (k = 1.40/s; dừng khi < 50 ms/s nội dung).
**Gain 2 không làm đường video tệ đi** trong lần chạy này. `DragGesture.velocity` / ước lượng 100 ms cuối của mình: p10 0.33,
trung vị **0.75**, p90 0.97 — `.velocity` thường thấp hơn tốc độ thật ở 100 ms cuối (chưa biết bên nào "đúng"; chưa chỉnh gì).
Giới hạn: một lần chạy, zoom đổi liên tục, người vuốt mạnh hơn lần trước nên không so được từng cú một.

### 2026-10-09 · T3 · iPhone 13 thật · dung sai cố định 0.2 s · lần đầu có `visual_lag` (80 s, zoom ~0.09 px/ms, không tag)
Chỉ có **một** nhánh (dung sai 0.2 s mặc định); các nhánh `0` / `0.05` / `prop:1.5` chưa chạy. Hình trễ sau ngón tay theo tốc độ playhead:

| tốc độ playhead | giây | trễ p50 | trễ p95 | lệch nội dung p50 |
|---|---|---|---|---|
| 0.1–0.3 s/s | 3 | **670 ms** | 754 | 115 ms |
| 0.3–0.6 | 5 | **106 ms** | 611 | 79 ms |
| 0.6–1.5 | 12 | **67 ms** | 285 | 83 ms |
| 1.5–3 | 10 | **38 ms** | 167 | 99 ms |
| 3–8 | 24 | 22 ms | 75 | 122 ms |
| > 8 s/s | 19 | 10 ms | 39 | 146 ms |

**Đọc:** lệch nội dung gần như không đổi (~80–150 ms, đúng bằng dung sai 0.2 s + trễ seek), nên trễ ∝ 1/tốc độ đúng như dự đoán:
chỉ khi playhead ≥ ~3 s/s hình mới trễ ≤ 25 ms (p50). **Dưới 1.5 s/s — kéo chậm và cả lúc coast sắp dừng — hình trễ 40–670 ms**,
tức nhảy từng bậc. Đây là chỗ cần cải thiện, và nó khớp với dung sai cố định, không phải với seek chậm (seek p95 7–35 ms).
Ngân sách: trễ ≤ 25 ms ⇒ lệch nội dung ≤ 25 ms × tốc độ(s/s) — chính là `prop:1.5` (1.5 khung chuyển động playhead).
`DragGesture.velocity` / ước lượng 100 ms cuối lần này trung vị **0.45** (lần trước 0.75): `.velocity` báo thấp hơn nhiều.
Giới hạn: một nhánh, một lần chạy; ngón vuốt nhẹ hơn lần trước (760 px/s).

### Baseline trên máy thật — tiến độ
- [ ] T0 · [ ] T1 · [ ] T2 · [~] **T3** (mới có bản coasting-heavy, 2026-10-09) · [ ] T4 · [ ] T5 · [ ] T6 · [ ] T7

## 10. Nhật ký quyết định / bằng chứng

### Rủi ro của quyết định bỏ proxy (cần xác minh, chưa phải kết luận)

- Clip mẫu (`13792197_1080_1920_30fps.mp4`) có **keyframe mỗi 250 khung (~8.3 s)**; đo trực tiếp:
  seek trên file gốc trung bình **1124 ms** (258–2354), trên proxy all-intra 5 ms (§ bằng chứng bên dưới).
  Khi còn proxy, T3 không khựng. **Bỏ proxy có thể làm khựng quay lại khi kéo ngược với clip này.**
- Nhưng video **quay bằng iPhone** thường có keyframe ~mỗi 30 khung (≈1 s), nên với footage thật chi phí
  này nhỏ hơn nhiều so với clip mẫu. Quan sát "app thật không tạo proxy" là hợp lý cho footage kiểu đó.
- **Đã đo trên simulator 2026-10-09 (§9):** không proxy chậm hơn 8–110 lần kể cả clip GOP 29. Chưa đo trên iPhone thật.
- Cách xác minh (theo §0): chạy lại **cùng kịch bản T3** và so `seek_service_ms_p95`/`seek_e2e_ms_p95`/
  `dropped_frames` với bản có proxy (10→11 ms, 0 rớt); rồi chạy thêm với **một clip quay bằng iPhone**.
  Nếu clip mẫu khựng mà clip iPhone không → đổi clip mẫu, không phải thêm proxy.

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
| 2026-10-09 | Sửa lỗi công cụ: `display_age_ms` tính từ seek hoàn tất trước khoảng nghỉ; thêm `seek_landing_error_ms` | số đo phải phản ánh độ trễ thật | `display_age` max 1.8–2.1 s dù seek ≤ 34 ms (vô lý) | chưa chạy lại | sửa công cụ; số T3 đầu của `display_age` bỏ |
| 2026-10-09 | **ĐƠN GIẢN HOÁ bước 4**: `EditorPlaybackEngine.init` chỉ đọc project; `AVPlayer` + audio mix tạo ở `prepare()` | H3: `EditorShellView.init` tạo engine hai lần → `sessions_alive` = 2 với 1 layer | sessions_alive 2 | test `testInitCreatesNoPlayersUntilPrepare`; máy thật: chờ đo | 98 test pass |
| 2026-10-09 | **ĐƠN GIẢN HOÁ bước 3**: xoá tab Proxy Test (`ProxyTranscodeView`, `ProxyTranscoder`) | proxy đã bị bỏ; thí nghiệm kết thúc, bằng chứng nằm ở §10 | — | — | 97 test pass |
| 2026-10-09 | **ĐƠN GIẢN HOÁ bước 2**: xoá `SeekTolerancePolicy` (dung sai thích ứng) + theo dõi tốc độ nội dung; dung sai kéo là hằng số 0.2 s | H10 bị bác bỏ trên máy thật (không nhanh hơn, lệch gấp đôi) | — | — | 97 test pass (−3 test của chính sách); bỏ cột `scrub_speed_msps`, `seek_tolerance_ms` |
| 2026-10-09 | **ĐƠN GIẢN HOÁ bước 1**: xoá đường frame-server (`VideoFrameServer.swift` gồm `VideoFrameDecoder`/`DecodeGate`/`SharpFrameLoader`, `VideoFrameView`, `framesReady`/`stalledSeconds`/`prefetchFrames` trong engine, tham số `refinesStills`, `playerEngine` thành bắt buộc) | editor không dùng đường này (mọi nguồn đã `usesNativePlayer`); chỉ còn là mã chết | — | — | 100 test pass (−1: `testPlaybackHoldsTheClockUntilFramesAreDecoded`, quyết định "clock giữ chờ khung" không còn áp dụng) |
| 2026-10-09 | Filmstrip: **bỏ ghi thumbnail vào `VideoFrameCache.cache`** + huỷ batch `AVAssetImageGenerator` khi bị bỏ dở | H11: bộ nhớ 29 → 316 MB / 100 s (footage thật, zoom + kéo) | 29 → 316 MB | **chưa đo lại** | chờ chạy lại T3 cùng kịch bản (không Play ở 90 s đầu) |
| 2026-10-09 | **Dùng footage iPhone thật làm mẫu** (`SampleClipOverride`: `Documents/ImportedMedia/iphone-footage.MOV`, kích thước + độ dài lấy từ file); bỏ clip thử "phone-like" | clip stock keyframe thưa làm sai lệch số đo; người dùng thấy mượt hơn hẳn | stock: seek p95 160 ms | footage iPhone: seek p95 40 ms | **bỏ proxy là ổn với footage 1080p60 HEVC** (iPhone 13) |
| 2026-10-09 | Thêm log theo mức zoom (`timeline_px_per_ms`, `ruler_minor_ms`) + kịch bản T8 (zoom gần) / T9 (zoom xa); `playback_report.py --by-zoom` | người dùng: cần log riêng cho zoom gần và xa | zoom chỉ ghi khi pinch | chia theo bậc thước trong cùng một lần chạy | công cụ |
| 2026-10-09 | **Zoom timeline bằng hai ngón** (`MagnifyGesture`, quanh playhead). Giới hạn do người dùng đặt: zoom ra xa nhất → vạch thước cách nhau **5 s**; zoom vào gần nhất → vạch cách nhau **1 khung**; cùng khoảng cách tối thiểu 48 pt giữa hai vạch ⇒ 0.0096 … 1.44 px/ms (@30 fps). Thước tự chọn bước vạch; thước + filmstrip chỉ dựng trong **cửa sổ đang thấy** (±1 màn hình, lượng tử hoá theo màn hình) | người dùng yêu cầu; giả thuyết H10 cần "zoom" để so tốc độ nội dung | không có zoom (0.2 px/ms cố định) | 9 test thuần + 3 UI test cử chỉ thật pass; ảnh chụp ở hai cực trị khớp (nhãn `00:00:02` cách 1 khung; vạch 5 s) | tính năng; `pinch_events`, `timeline_px_per_ms` được ghi vào CSV |
| 2026-10-09 | Dự án mẫu "Trip to Paris" dài **31.2 s** (đúng độ dài clip) thay vì 8 s | 8 s làm 36% cú flick chạm biên; không đủ chỗ để thử zoom | 36% coast kết thúc ở biên | — | cần đo lại T3/T2 trên máy thật |
| 2026-10-09 | Thumbnail filmstrip giới hạn 320×320 (trước: độ phân giải gốc ~8 MB/ô) | zoom sâu cần hàng trăm ô | — | — | sửa phòng ngừa, chưa đo |
| 2026-10-09 | **Bỏ proxy** (xoá `VideoProxyService`, engine dùng file gốc) | người dùng: "app thật load thẳng video, không tạo proxy" | máy thật, có proxy: seek service p95 9.7 ms, 48 seek/s | máy thật, không proxy (clip mẫu GOP 250): p95 **160 ms**, 28 seek/s, hình trễ ~260 ms; simulator 60–2457 ms | **chậm hơn ~16× trên máy thật** với clip mẫu. Chưa đo clip quay bằng iPhone trên máy thật → chờ số đó rồi quyết (giữ bỏ / proxy chỉ khi keyframe thưa) |
| 2026-10-09 | **Viết lại momentum** theo `MomentumDecay` (hằng số `UIScrollView.DecelerationRate.normal`, k≈2.0/s, dạng đóng theo thời gian) thay đường cong tự chỉnh (k≈3.2/s, mất 96%/giây) | cảm giác không giống quán tính thật; mô hình cũ phanh mạnh hơn iOS ~60% và dừng cứng ở biên | (không có số `coast_*`) | khớp mô hình trong 6/6 cú flick (simulator); máy thật: 1% tắt vì ma sát, 36% chạm biên, 64% bị tay ngắt | momentum đúng mô hình; vấn đề cảm nhận còn lại là biên + timeline ngắn, không còn là ma sát |
| 2026-10-09 | Thêm lớp đo + HUD + T0–T7 | cần số đo trước khi sửa | — | — | công cụ, không phải sửa. Lần đo đầu đã lộ `engines_alive`=2 (H3) |
| 2026-10-09 | Đơn giản hoá pipeline (4 bước: bỏ proxy/VideoFrameServer/policy dung sai thích ứng, engine khởi tạo rẻ + `prepare()`) | footage iPhone cho thấy GOP thưa của clip stock mới là nguyên nhân gốc; dung sai thích ứng bị máy thật bác | xem bảng simplified ở §9 | seek p95 27 ms, 54.5 seek/s, bộ nhớ phẳng 41→43 MB, sessions 1, rớt 16 | video path khoẻ trên số; còn nghi dung sai 200 ms (landing error p50 75 ms) và độ dài coast — cần A/B đo, chưa sửa |
| 2026-10-09 | **Momentum cho trôi xa hơn**: `CoastTuning` gain 2.0 + ma sát ×0.7 (k≈1.40/s thay vì 2.0/s), cố định trong code | iPhone thật: ngón tay thả ~911 px/s trôi ~1.2 màn hình, chuột trên sim ~3165 px/s trôi ~4 màn hình; người dùng thấy máy thật "chậm" | quãng trôi ≈ v/2.0 ≈ 455 px | ≈ gain·v/(0.7·2.0) ≈ 1300 px (~3.3 màn hình) | chọn **theo cảm giác người dùng** ("giá trị hiện tại rất tốt"), không có chuẩn benchmark; chưa đo seek/lệch hình ở tốc độ này trên máy thật. Cú "đá" lúc thả do gain 2 chưa đo |
| 2026-10-09 | **Gain momentum 2.0 → 4.0** (ma sát ×0.7 giữ nguyên) | người dùng yêu cầu trôi xa hơn nữa ("tăng gain lên 4") | ≈ 1300 px cho cú vuốt 911 px/s | ≈ 2600 px (~6.7 màn hình) | chọn theo cảm giác; cú "đá" lúc thả gấp 4 lần tốc độ ngón chưa đo, video theo kịp 4× tốc độ nội dung chưa đo (dải >8 s/s trước đó trễ 10 ms nên khả quan) |

## 11. Backlog đo thêm (khi bảng §7 chỉ về một khoảng trống)

- Thời gian từ chạm Play đến khung đầu tiên thật sự chạy (T4).
- Khung nào thật sự lên màn hình (đường `AVPlayerLayer`) — `AVPlayerItemVideoOutput`
  chỉ để đo, hoặc quay màn hình 120 fps.
- Thời gian GPU của đường Metal (`MTLCommandBuffer.gpuStartTime/gpuEndTime`).
- `os_signpost` quanh seek/draw để xem trong Instruments.
- Đếm số lần `EditorShellView.init` chạy (kiểm chứng trực tiếp H3).
- Ghi nhiệt độ theo thời gian dài (10+ phút) trên máy thật.

## 12. Đo bằng footage quay thật bằng iPhone

**Vì sao:** "clip giống iPhone" dùng để thí nghiệm là clip stock đã mã hoá lại (H.264, 1080p, 10 Mbps, keyframe
mỗi 29 khung) — chỉ mô phỏng khoảng cách keyframe. Footage iPhone thật khác ở nhiều điểm ảnh hưởng chi phí seek:
mặc định HEVC (không phải H.264), 4K và/hoặc 60 fps, bitrate 20–100 Mbps, thường HDR (Dolby Vision/HLG 10-bit),
B-frame, tần số khung thay đổi, metadata xoay. Kết luận "không cần proxy" **chưa được phép** rút ra cho tới khi
đo trên footage thật.

**Phân tích trước khi đo** (trên Mac): `swiftc -O scripts/probe_clip.swift -o /tmp/probe_clip && /tmp/probe_clip clip.mov`
→ codec, kích thước, fps đo được, bitrate, khoảng cách keyframe, B-frame, HDR, góc xoay. (Hai clip thử hiện có:
đều H.264 1080p, đều có B-frame; keyframe median 186 / 29 khung; không HDR.)

**Đưa clip vào máy** (không cần giao diện import): copy vào thư mục app đọc
(`Documents/ImportedMedia`, `bundledURL` tìm ở đó sau bundle):

```
xcrun devicectl device copy to --device <id> --domain-type appDataContainer \
  --domain-identifier com.neonix.editor --source clip.mov --destination Documents/ImportedMedia/clip.mov
```
rồi khởi chạy với `PLAYBACK_SAMPLE_CLIP=clip.mov` (Debug; kích thước + độ dài lấy từ chính file —
`EditorDocument/SampleClipOverride.swift`). Chạy cùng kịch bản (T3, và T8/T9 cho zoom) với dung sai `fixed`,
rồi so với clip stock (seek p95 23 ms, ~47 seek/s ở 1080p/H.264/GOP 29).

**Lấy clip từ iPhone sang Mac mà không bị đổi định dạng:** Ảnh → chọn video → Chia sẻ → Tuỳ chọn → *Tất cả dữ
liệu Ảnh* (nếu để "Tương thích nhất" iOS sẽ chuyển sang H.264/SDR và mất đúng thứ cần đo), rồi AirDrop. Hoặc
Lưu vào Tệp rồi AirDrop file.

**Từ 2026-10-09 mọi màn hình test dùng đúng một clip:** `public/preview/video/iphone-footage.MOV` (HEVC 1080×1920 60 fps,
keyframe 0.5 s, 89.8 s) — tab Playback Sandbox, tab Video Raw và dự án mẫu của editor đều đọc nó qua
`UI/Playback/TestFootage.swift` / `SampleClipOverride` (không còn bộ chọn clip stock). File 190 MB nên **không bundle**:
đẩy vào máy bằng lệnh `devicectl ... copy to` ở trên (hoặc chép vào `Documents/ImportedMedia` của simulator).

**Bộ clip đề xuất** (mỗi clip 20–40 s, có chuyển động thật): (1) cảnh quay bình thường ở cài đặt mặc định của
máy; (2) 4K 60 fps nếu bạn hay quay; (3) một clip HDR (Dolby Vision) nếu máy đang bật.


## 13. Mục tiêu "hình trễ ≤ 25 ms" — đo đúng đại lượng trước khi sửa

Người dùng đặt mục tiêu (2026-10-09): tìm hướng đưa độ trễ hình về ≤ 25 ms.

**Sửa một so sánh sai ở các mục trên.** Ngưỡng ~11 ms (nhận ra) / ~25 ms (hiệu suất giảm) từ nghiên cứu cảm ứng
(Deber, Jota) là **độ trễ theo thời gian** (ngón → hình). Còn `seek_landing_error_ms` là **sai lệch vị trí nội dung**
(hình dừng cách vị trí tay bao nhiêu ms *nội dung*). Hai đại lượng liên hệ qua tốc độ: trễ (ms thời gian) = sai lệch nội
dung ÷ tốc độ playhead. Cùng sai lệch 75 ms nội dung: ở 5 s/s chỉ là 15 ms trễ (không thấy), ở 0.3 s/s là 250 ms trễ
(hình đứng hẳn rồi nhảy). Vì vậy việc đặt 75 ms cạnh 25 ms trước đây là so táo với cam.

**Số có sẵn (thời gian thật, footage iPhone, máy thật, khi coasting):** seek end-to-end p50 5 ms / p95 29 ms,
display age p95 30 ms — phần *độ trễ* của đường seek đã gần ngưỡng 25 ms. Chưa có số cho phần *sai lệch nội dung* ở tốc độ
chậm: các lần chạy thật hầu như toàn coasting (nhanh).

**Phép đo mới** (mỗi tick màn hình lúc scrubbing/coasting): `display_error_ms` (frame đang hiện cách playhead bao nhiêu ms
nội dung; lấy từ `PlayerSeekCoordinator.lastLandedSeconds`, vì `AVPlayer.currentTime()` báo *đích* của seek đang chạy),
`playhead_speed_msps`, và `visual_lag_ms` = sai lệch ÷ tốc độ (chỉ lấy mẫu khi playhead > 100 ms/s).
`scripts/compare_runs.py` in `visual_lag` theo ba dải tốc độ (chậm 0.1–0.6 s/s, vừa, nhanh > 3 s/s).

**A/B dung sai seek** (`ScrubTolerancePolicy`, biến môi trường `PLAYBACK_SCRUB_TOLERANCE`, chạy bằng
`scripts/run_tolerance_arm.sh`): cố định `0.2` (hiện tại), `0` (luôn chính xác), `0.05`, và `prop:1.5` (slack = 1.5 khung của
chuyển động playhead, trần 0.2 s). Tiêu chí: `visual_lag` p95 ≤ 25 ms ở dải chậm và vừa, **không** làm seek service p95 > 35 ms
hay seek/s < 50. Lưu ý: lần thử dung sai thích ứng trước (H10) đánh giá bằng `landing_error` nội dung, không phải độ trễ
theo thời gian, nên kết luận "tệ hơn" của nó cần xem lại bằng phép đo mới.
