import { describe, expect, it } from "vitest";
import { V2EmbeddedVideoAudioSchema } from "../src/v2/audio";
import { MotionProtocolV2Schema } from "../src/v2/project";

const RECTANGLE_PROJECT = {
  format: "motion-protocol",
  formatVersion: 2,
  id: "project-v2",
  composition: {
    width: 320,
    height: 180,
    fps: 30,
    background: "#101820",
    colorSpace: "srgb",
    view: {
      projection: { kind: "orthographic", zoom: 1, near: 1, far: 4000 },
      transform: {
        translate: { x: 0, y: 0, z: 0 },
        rotate: { x: 0, y: 0, z: 0 },
      },
    },
  },
  assets: [],
  layers: [
    {
      type: "shape",
      id: "rectangle",
      parentLayerId: null,
      order: 0,
      frame: { width: 96, height: 64 },
      transform: {
        translate: { x: 0, y: 0, z: 0 },
        scale: { x: 1, y: 1, z: 1 },
        rotate: { x: 0, y: 0, z: 0 },
        skew: { x: 0, y: 0 },
        anchor: { x: 0, y: 0, z: 0 },
      },
      opacity: 1,
      timing: { start: 0, duration: 1000 },
      payload: { shape: "rectangle" },
      style: { fill: "#00aa88" },
    },
  ],
  audio: {
    sampleRate: 48000,
    tracks: [],
  },
};

describe("Motion Protocol V2 schema", () => {
  it("accepts the strict rectangle protocol", () => {
    expect(MotionProtocolV2Schema.parse(RECTANGLE_PROJECT)).toEqual(
      RECTANGLE_PROJECT,
    );
  });

  it("accepts an explicit audio domain with trim, gain, pan, and fades", () => {
    const audio = {
      ...RECTANGLE_PROJECT,
      assets: [{
        id: "voice",
        kind: "audio" as const,
        uri: "/audio/voice.wav",
        mimeType: "audio/wav",
        duration: 4000,
        sampleRate: 48000,
        channels: 2,
      }],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "voice-track",
          gainDb: 0,
          pan: -0.25,
          muted: false,
          clips: [{
            id: "voice-clip",
            assetId: "voice",
            timing: { start: 1000, duration: 2000 },
            trim: { start: 500, end: 2500 },
            playbackRate: 1,
            enabled: true,
            gainDb: -3,
            pan: 0,
            fadeIn: { duration: 250, curve: "linear" as const },
            fadeOut: { duration: 250, curve: "equal-power" as const },
          }],
        }],
      },
    };
    expect(MotionProtocolV2Schema.parse(audio)).toEqual(audio);
  });

  it("rejects the removed audio loop field", () => {
    const project = {
      ...RECTANGLE_PROJECT,
      assets: [{
        id: "voice",
        kind: "audio" as const,
        uri: "/audio/voice.wav",
        mimeType: "audio/wav",
        duration: 4000,
        sampleRate: 48000,
        channels: 2,
      }],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "voice-track",
          gainDb: 0,
          pan: 0,
          muted: false,
          clips: [{
            id: "voice-clip",
            assetId: "voice",
            timing: { start: 0, duration: 2000 },
            trim: { start: 0, end: 2000 },
            playbackRate: 1,
            gainDb: 0,
            loop: true,
          }],
        }],
      },
    };
    expect(() => MotionProtocolV2Schema.parse(project)).toThrow();
  });

  it("rejects an audio clip whose duration exceeds its explicit trim range", () => {
    const project = {
      ...RECTANGLE_PROJECT,
      assets: [{
        id: "voice",
        kind: "audio" as const,
        uri: "/audio/voice.wav",
        mimeType: "audio/wav",
        duration: 4000,
        sampleRate: 48000,
        channels: 2,
      }],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "voice-track",
          gainDb: 0,
          pan: 0,
          muted: false,
          clips: [{
            id: "voice-clip",
            assetId: "voice",
            timing: { start: 0, duration: 3000 },
            trim: { start: 0, end: 2000 },
            playbackRate: 1,
            gainDb: 0,
          }],
        }],
      },
    };
    expect(() => MotionProtocolV2Schema.parse(project)).toThrow(/bounded trim range/);
  });

  it("normalizes omitted audio gain to unity in JSON", () => {
    const project = {
      ...RECTANGLE_PROJECT,
      assets: [{
        id: "voice",
        kind: "audio" as const,
        uri: "/audio/voice.wav",
        mimeType: "audio/wav",
        duration: 4000,
        sampleRate: 48000,
        channels: 2,
      }],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "voice-track",
          pan: 0,
          muted: false,
          clips: [{
            id: "voice-clip",
            assetId: "voice",
            timing: { start: 0, duration: 4000 },
            trim: { start: 0 },
            playbackRate: 1,
          }],
        }],
      },
    };

    const parsed = MotionProtocolV2Schema.parse(project);
    expect(parsed.audio.tracks[0]?.gainDb).toBe(0);
    expect(parsed.audio.tracks[0]?.clips[0]?.gainDb).toBe(0);
    expect(V2EmbeddedVideoAudioSchema.parse({ enabled: true })).toEqual({
      enabled: true,
      gainDb: 0,
      pan: 0,
    });
  });

  it("accepts embedded video audio and keeps its timing fields inherited", () => {
    const video = {
      ...RECTANGLE_PROJECT,
      id: "video-with-audio-v2",
      assets: [{
        id: "clip",
        kind: "video" as const,
        uri: "/video/clip.mp4",
        mimeType: "video/mp4",
        duration: 8000,
        fps: 30,
      }],
      layers: [{
        id: "video",
        type: "video" as const,
        parentLayerId: null,
        order: 0,
        frame: { width: 320, height: 180 },
        transform: RECTANGLE_PROJECT.layers[0].transform,
        opacity: 1,
        timing: { start: 2000, duration: 4000 },
        payload: {
          assetId: "clip",
          trimStart: 1000,
          trimEnd: 5000,
          audio: {
            enabled: true,
            gainDb: -3,
            pan: 0,
            fadeIn: { duration: 250, curve: "linear" as const },
          },
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(video)).toEqual(video);
    expect(() => MotionProtocolV2Schema.parse({
      ...video,
      layers: [{
        ...video.layers[0],
        payload: {
          ...video.layers[0].payload,
          audio: {
            ...video.layers[0].payload.audio,
            fadeIn: { duration: 4100, curve: "linear" as const },
          },
        },
      }],
    })).toThrow(/cannot exceed video duration/);
  });

  it("rejects invalid audio references and duplicate audio identities", () => {
    const audio = {
      ...RECTANGLE_PROJECT,
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          id: "track",
          gainDb: 0,
          pan: 0,
          muted: false,
          clips: [{
            id: "clip",
            assetId: "missing",
            timing: { start: 0, duration: 1000 },
            trim: { start: 0 },
            playbackRate: 1,
            gainDb: 0,
          }],
        }],
      },
    };
    expect(() => MotionProtocolV2Schema.parse(audio)).toThrow(/Unknown audio asset/);
    expect(() => MotionProtocolV2Schema.parse({
      ...audio,
      assets: [{
        id: "image",
        kind: "image" as const,
        uri: "/image.png",
        mimeType: "image/png",
      }],
      audio: {
        sampleRate: 48000 as const,
        tracks: [{
          ...audio.audio.tracks[0],
          clips: [{ ...audio.audio.tracks[0].clips[0], assetId: "image" }],
        }],
      },
    })).toThrow(/audio or video asset/);
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      audio: {
        sampleRate: 48000 as const,
        tracks: [
          { id: "track", gainDb: 0, pan: 0, muted: false, clips: [] },
          { id: "track", gainDb: 0, pan: 0, muted: false, clips: [] },
        ],
      },
    })).toThrow(/Duplicate audio track id/);
  });

  it("rejects the legacy composition audioSampleRate location", () => {
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      composition: {
        ...RECTANGLE_PROJECT.composition,
        audioSampleRate: 48000,
      },
    })).toThrow(/audioSampleRate/);
  });

  it("normalizes omitted layer opacity to one and rejects the legacy percent range", () => {
    const withoutOpacity = {
      ...RECTANGLE_PROJECT,
      layers: [(({ opacity: _opacity, ...layer }) => layer)(RECTANGLE_PROJECT.layers[0])],
    };
    expect(MotionProtocolV2Schema.parse(withoutOpacity).layers[0]).toMatchObject({ opacity: 1 });
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{ ...RECTANGLE_PROJECT.layers[0], opacity: 100 }],
    })).toThrow();
  });

  it("accepts ellipse as the second supported shape primitive", () => {
    const ellipse = {
      ...RECTANGLE_PROJECT,
      id: "ellipse-project-v2",
      layers: [
        {
          ...RECTANGLE_PROJECT.layers[0],
          id: "ellipse",
          payload: { shape: "ellipse" },
        },
      ],
    };
    expect(MotionProtocolV2Schema.parse(ellipse)).toEqual(ellipse);
  });

  it("accepts an open stroke-only path with join, cap, and dash semantics", () => {
    const path = {
      ...RECTANGLE_PROJECT,
      id: "open-path-project-v2",
      layers: [{
        ...RECTANGLE_PROJECT.layers[0],
        id: "open-path",
        type: "path" as const,
        frame: { width: 160, height: 40 },
        payload: {
          contours: [{
            id: "line",
            start: { x: 0, y: 20 },
            segments: [{ kind: "line" as const, to: { x: 160, y: 20 } }],
            closed: false,
          }],
          fillRule: "nonzero" as const,
        },
        style: {
          stroke: "#ff3366",
          strokeWidth: 8,
          strokeJoin: "round" as const,
          strokeCap: "round" as const,
          strokeDash: { array: [12, 6], offset: 2 },
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(path)).toEqual(path);
  });

  it("preserves SVG length tokens, pathLength calibration, and paint references", () => {
    const project = {
      ...RECTANGLE_PROJECT,
      paintServers: [{
        id: "brand-gradient",
        paint: {
          type: "linear-gradient" as const,
          stops: [{ offset: 0, color: "#00aa88" }, { offset: 1, color: "#ff3366" }],
        },
      }],
      layers: [{
        ...RECTANGLE_PROJECT.layers[0],
        type: "path" as const,
        payload: {
          contours: [{
            id: "open",
            start: { x: 0, y: 0 },
            segments: [{ kind: "line" as const, to: { x: 96, y: 0 } }],
            closed: false,
          }],
          fillRule: "nonzero" as const,
          pathLength: 100,
        },
        style: {
          fill: { type: "reference" as const, id: "brand-gradient", fallback: "#000000" },
          stroke: "#ffffff",
          strokeWidth: { value: 2, unit: "px" as const },
          strokeDash: { array: [0, { value: 10, unit: "percent" as const }], offset: { value: -4, unit: "px" as const } },
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(project)).toEqual(project);
    expect(() => MotionProtocolV2Schema.parse({
      ...project,
      layers: [{ ...project.layers[0], style: { ...project.layers[0].style, fill: { type: "reference", id: "missing" } } }],
    })).toThrow(/Unknown paint server reference/);
  });

  it("accepts an SVG path with omitted paint properties and applies no protocol-side rejection", () => {
    const path = {
      ...RECTANGLE_PROJECT,
      layers: [{
        ...RECTANGLE_PROJECT.layers[0],
        type: "path" as const,
        payload: {
          contours: [{
            id: "closed",
            start: { x: 0, y: 0 },
            segments: [
              { kind: "line" as const, to: { x: 40, y: 0 } },
              { kind: "line" as const, to: { x: 40, y: 40 } },
              { kind: "line" as const, to: { x: 0, y: 40 } },
            ],
            closed: true,
          }],
          fillRule: "nonzero" as const,
        },
        style: {},
      }],
    };
    expect(MotionProtocolV2Schema.parse(path)).toEqual(path);
  });

  it("accepts SVG marker definitions and validates marker references", () => {
    const marker = {
      id: "arrow",
      markerUnits: "userSpaceOnUse" as const,
      refX: 8,
      refY: 5,
      markerWidth: 10,
      markerHeight: 10,
      orient: "auto" as const,
      content: {
        contours: [{
          id: "arrow-head",
          start: { x: 0, y: 0 },
          segments: [
            { kind: "line" as const, to: { x: 10, y: 5 } },
            { kind: "line" as const, to: { x: 0, y: 10 } },
          ],
          closed: false,
        }],
        fill: "#ff3366",
      },
    };
    const path = {
      ...RECTANGLE_PROJECT,
      id: "marker-project-v2",
      markers: [marker],
      layers: [{
        ...RECTANGLE_PROJECT.layers[0],
        type: "path" as const,
        id: "marker-path",
        payload: {
          contours: [{ id: "line", start: { x: 0, y: 20 }, segments: [{ kind: "line" as const, to: { x: 160, y: 20 } }], closed: false }],
          fillRule: "nonzero" as const,
        },
        style: { stroke: "#00aa88", strokeWidth: 8, markerEnd: "arrow" },
      }],
    };
    expect(MotionProtocolV2Schema.parse(path)).toEqual(path);
    expect(() => MotionProtocolV2Schema.parse({ ...path, layers: [{ ...path.layers[0], style: { ...path.layers[0].style, markerEnd: "missing" } }] })).toThrow(/Unknown marker reference/);
  });

  it("accepts an image asset reference with SVG viewport semantics", () => {
    const image = {
      ...RECTANGLE_PROJECT,
      id: "image-project-v2",
      assets: [{
        id: "photo",
        kind: "image" as const,
        uri: "/docs/preview-image.svg",
        mimeType: "image/svg+xml",
        width: 200,
        height: 100,
      }],
      layers: [{
        id: "image",
        type: "image" as const,
        parentLayerId: null,
        order: 0,
        frame: { width: 320, height: 240 },
        transform: RECTANGLE_PROJECT.layers[0].transform,
        opacity: 1,
        timing: { start: 0, duration: 1000 },
        payload: {
          assetId: "photo",
          x: 10,
          y: 20,
          width: 320,
          height: 240,
          preserveAspectRatio: { align: "xMidYMid" as const, meetOrSlice: "slice" as const },
          imageRendering: "optimizeQuality" as const,
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(image)).toEqual(image);
    expect(() => MotionProtocolV2Schema.parse({
      ...image,
      layers: [{ ...image.layers[0], payload: { assetId: "photo", width: 0 } }],
    })).toThrow();
  });

  it("accepts a video asset with trim, mute, and frame policy", () => {
    const video = {
      ...RECTANGLE_PROJECT,
      id: "video-project-v2",
      assets: [{
        id: "clip",
        kind: "video" as const,
        uri: "/preview/video/demo-video.mp4",
        mimeType: "video/mp4",
        width: 1920,
        height: 1080,
        duration: 60500,
        fps: 30,
      }],
      layers: [{
        id: "video",
        type: "video" as const,
        parentLayerId: null,
        order: 0,
        frame: { width: 960, height: 540 },
        transform: RECTANGLE_PROJECT.layers[0].transform,
        opacity: 1,
        timing: { start: 0, duration: 3000 },
        payload: {
          assetId: "clip",
          fit: "cover" as const,
          trimStart: 1000,
          trimEnd: 4000,
          audio: { enabled: false, gainDb: 0, pan: 0 },
          framePolicy: "floor" as const,
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(video)).toEqual(video);
    expect(() => MotionProtocolV2Schema.parse({
      ...video,
      layers: [{ ...video.layers[0], payload: { ...video.layers[0].payload, trimStart: 4000, trimEnd: 1000 } }],
    })).toThrow(/trimEnd must be greater/);
    expect(() => MotionProtocolV2Schema.parse({
      ...video,
      layers: [{ ...video.layers[0], payload: { ...video.layers[0].payload, trimEnd: 61000 } }],
    })).toThrow(/trimEnd cannot exceed source duration/);
    expect(() => MotionProtocolV2Schema.parse({
      ...video,
      layers: [{ ...video.layers[0], timing: { start: 0, duration: 4000 } }],
    })).toThrow(/selected source range/);
  });

  it("accepts semantic SVG text chunks and animatable span properties", () => {
    const text = {
      ...RECTANGLE_PROJECT,
      id: "text-project-v2",
      assets: [{
        id: "noto-sans-regular",
        kind: "font" as const,
        uri: "/preview/font/Noto_Sans/NotoSans-Regular.ttf",
        weight: 400,
        integrity: "sha256:fe8c022f48d8dd29f17b744d16f9346f4357e16f7d4f7be58b000ae7c291b614",
      }],
      layers: [{
        id: "headline",
        type: "text" as const,
        parentLayerId: null,
        order: 0,
        frame: { width: 320, height: 100 },
        transform: RECTANGLE_PROJECT.layers[0].transform,
        opacity: 1,
        timing: { start: 0, duration: 1000 },
        payload: {
          source: { text: "NeonVideo", language: "en" },
          layout: {
            lineHeight: 56,
            textAlign: "center" as const,
            whiteSpace: "nowrap" as const,
            wrap: "none" as const,
            textOverflow: "clip" as const,
          },
          chunks: [{
            id: "headline-chunk",
            sourceRange: { start: 0, end: 9 },
            textAnchor: "middle" as const,
            spans: [{
              id: "headline-span",
              sourceRange: { start: 0, end: 9 },
              resolvedFontAssetIds: ["noto-sans-regular"],
              font: { families: ["Noto Sans", "sans-serif"], size: 48, weight: 700, variations: { wght: 700 } },
              fill: "#ffffff",
            }],
          }],
        },
      }],
    };
    expect(MotionProtocolV2Schema.parse(text)).toEqual(text);
    expect(() => MotionProtocolV2Schema.parse({
      ...text,
      layers: [{
        ...text.layers[0],
        payload: {
          ...text.layers[0].payload,
          layout: { ...text.layers[0].payload.layout!, textOverflow: "ellipsis" as const },
        },
      }],
    })).toThrow(/deterministic clipPath/);
    expect(MotionProtocolV2Schema.parse({
      ...text,
      layers: [{
        ...text.layers[0],
        tracks: [
          {
            id: "headline-color",
            path: "payload.chunks.spans.headline-span.fill",
            keyframes: [{ time: 0, value: { type: "color" as const, value: [1, 1, 1, 1] as const } }],
          },
          {
            id: "headline-size",
            path: "payload.chunks.spans.headline-span.font.size",
            keyframes: [{ time: 0, value: { type: "number" as const, value: 48 } }],
          },
        ],
      }],
    }).layers[0]?.tracks).toHaveLength(2);
    expect(MotionProtocolV2Schema.parse(text)).toEqual(text);
    expect(() => MotionProtocolV2Schema.parse({
      ...text,
      layers: [{
        ...text.layers[0],
        payload: {
          ...text.layers[0].payload,
          chunks: [{
            ...text.layers[0].payload.chunks[0],
            spans: [{
              ...text.layers[0].payload.chunks[0]!.spans[0],
              resolvedFontAssetIds: ["missing-font"],
            }],
          }],
        },
      }],
    })).toThrow(/Unknown resolved font asset/);
  });

  it("requires one explicit view projection with complete parameters", () => {
    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        composition: {
          ...RECTANGLE_PROJECT.composition,
          view: undefined,
        },
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        composition: {
          ...RECTANGLE_PROJECT.composition,
          view: {
            ...RECTANGLE_PROJECT.composition.view,
            projection: { kind: "orthographic", zoom: 1, near: 1 },
          },
        },
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        composition: {
          ...RECTANGLE_PROJECT.composition,
          view: {
            ...RECTANGLE_PROJECT.composition.view,
            projection: { kind: "perspective", fov: 60, near: 4, far: 1 },
          },
        },
      }),
    ).toThrow(/far must be greater/);
  });

  it("rejects V1 and high-level fields at the protocol boundary", () => {
    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        formatVersion: 1,
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        bone: { id: "legacy" },
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [{ ...RECTANGLE_PROJECT.layers[0], depth: 100 }],
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [
          {
            ...RECTANGLE_PROJECT.layers[0],
            matrix4: Array.from({ length: 16 }, () => 0),
          },
        ],
      }),
    ).toThrow();

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [
          {
            ...RECTANGLE_PROJECT.layers[0],
            transform: {
              ...RECTANGLE_PROJECT.layers[0].transform,
              origin: { x: 0.5, y: 0.5 },
            },
          },
        ],
      }),
    ).toThrow();
  });

  it("accepts group parents and rejects invalid hierarchy", () => {
    const group = {
      id: "group",
      type: "group" as const,
      parentLayerId: null,
      order: 0,
      frame: RECTANGLE_PROJECT.layers[0].frame,
      transform: RECTANGLE_PROJECT.layers[0].transform,
      opacity: 1,
      timing: RECTANGLE_PROJECT.layers[0].timing,
    };
    const child = {
      ...RECTANGLE_PROJECT.layers[0],
      id: "child",
      parentLayerId: "group",
      order: 1,
    };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [group, child],
    }).layers).toHaveLength(2);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{ ...RECTANGLE_PROJECT.layers[0], parentLayerId: "missing" }],
    })).toThrow(/Unknown parent layer/);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [
        { ...group, parentLayerId: "child" },
        child,
      ],
    })).toThrow(/cycle/);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [
        { ...RECTANGLE_PROJECT.layers[0], id: "parent", type: "shape" as const },
        { ...RECTANGLE_PROJECT.layers[0], id: "child", parentLayerId: "parent", order: 1 },
      ],
    })).toThrow(/Only group layers/);
  });

  it("rejects duplicate ids and duplicate sibling orders", () => {
    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [
          RECTANGLE_PROJECT.layers[0],
          { ...RECTANGLE_PROJECT.layers[0], order: 1 },
        ],
      }),
    ).toThrow(/Duplicate layer id/);

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [
          RECTANGLE_PROJECT.layers[0],
          { ...RECTANGLE_PROJECT.layers[0], id: "second", order: 0 },
        ],
      }),
    ).toThrow(/Duplicate order/);

    const group = {
      id: "order-group",
      type: "group" as const,
      parentLayerId: null,
      order: 1,
      frame: RECTANGLE_PROJECT.layers[0].frame,
      transform: RECTANGLE_PROJECT.layers[0].transform,
      opacity: 1,
      timing: RECTANGLE_PROJECT.layers[0].timing,
    };
    const child = {
      ...RECTANGLE_PROJECT.layers[0],
      id: "order-child",
      parentLayerId: "order-group",
      order: 0,
    };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [RECTANGLE_PROJECT.layers[0], group, child],
    }).layers).toHaveLength(3);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [
        RECTANGLE_PROJECT.layers[0],
        group,
        child,
        { ...child, id: "order-child-duplicate" },
      ],
    })).toThrow(/Duplicate order/);

    expect(() =>
      MotionProtocolV2Schema.parse({
        ...RECTANGLE_PROJECT,
        layers: [
          {
            ...RECTANGLE_PROJECT.layers[0],
            transform: {
              ...RECTANGLE_PROJECT.layers[0].transform,
              anchor: { x: Number.NaN, y: 0, z: 0 },
            },
          },
        ],
      }),
    ).toThrow();
  });

  it("accepts animating gradient sub-properties by stop index and rejects a field the gradient type doesn't declare", () => {
    const gradientLayer = {
      ...RECTANGLE_PROJECT.layers[0],
      style: {
        fill: {
          type: "linear-gradient" as const,
          x1: 0,
          y1: 0,
          x2: 1,
          y2: 0,
          stops: [
            { offset: 0, color: "#ff0000" },
            { offset: 1, color: "#0000ff" },
          ],
        },
      },
      tracks: [
        {
          id: "stop-color",
          path: "style.fill.stops.0.color",
          keyframes: [{ time: 0, value: { type: "color" as const, value: [1, 0, 0, 1] } }],
        },
        {
          id: "stop-offset",
          path: "style.fill.stops.1.offset",
          keyframes: [{ time: 0, value: { type: "number" as const, value: 1 } }],
        },
        {
          id: "angle",
          path: "style.fill.x2",
          keyframes: [{ time: 0, value: { type: "number" as const, value: 1 } }],
        },
      ],
    };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [gradientLayer],
    }).layers[0]?.tracks).toHaveLength(3);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{
        ...gradientLayer,
        // `radius` is a radial-gradient field, not linear-gradient.
        tracks: [{ id: "bad", path: "style.fill.radius", keyframes: [{ time: 0, value: { type: "number" as const, value: 1 } }] }],
      }],
    })).toThrow(/does not identify an animatable property/);
  });

  it("accepts project-level def tracks (filter/mask/paintServer) sampled at absolute composition time", () => {
    const withDefs = {
      ...RECTANGLE_PROJECT,
      filters: [{
        id: "glow",
        primitives: [{ id: "blur1", type: "feGaussianBlur" as const, stdDeviation: { x: 0, y: 0 } }],
        // Isotropic blur/shadow requires x and y to animate in lockstep
        // (see the "requires animating both x and y" check below).
        tracks: [
          { id: "blur-x", path: "primitives.blur1.stdDeviation.x", keyframes: [{ time: 0, value: { type: "number" as const, value: 0 } }] },
          { id: "blur-y", path: "primitives.blur1.stdDeviation.y", keyframes: [{ time: 0, value: { type: "number" as const, value: 0 } }] },
        ],
      }],
      masks: [{
        id: "reveal",
        width: 96,
        children: [{ type: "rect" as const, x: 0, y: 0, width: 10, height: 10 }],
        tracks: [{
          id: "width",
          path: "width",
          keyframes: [{ time: 0, value: { type: "number" as const, value: 96 } }],
        }],
      }],
      paintServers: [{
        id: "sweep",
        paint: {
          type: "linear-gradient" as const,
          stops: [{ offset: 0, color: "#ff0000" }, { offset: 1, color: "#0000ff" }],
        },
        tracks: [{
          id: "stop-color",
          path: "paint.stops.0.color",
          keyframes: [{ time: 0, value: { type: "color" as const, value: [1, 0, 0, 1] } }],
        }],
      }],
    };
    const parsed = MotionProtocolV2Schema.parse(withDefs);
    expect(parsed.filters?.[0]?.tracks).toHaveLength(2);
    expect(parsed.masks?.[0]?.tracks).toHaveLength(1);
    expect(parsed.paintServers?.[0]?.tracks).toHaveLength(1);

    expect(() => MotionProtocolV2Schema.parse({
      ...withDefs,
      filters: [{ ...withDefs.filters[0], tracks: [{ id: "bad", path: "primitives.blur1.radius", keyframes: withDefs.filters[0].tracks[0]!.keyframes }] }],
    })).toThrow(/does not identify an animatable property on filters/);

    expect(() => MotionProtocolV2Schema.parse({
      ...withDefs,
      masks: [{ ...withDefs.masks[0], tracks: [{ id: "bad", path: "maskType", keyframes: withDefs.masks[0].tracks[0]!.keyframes }] }],
    })).toThrow(/does not identify an animatable property on masks/);

    expect(() => MotionProtocolV2Schema.parse({
      ...withDefs,
      paintServers: [{ ...withDefs.paintServers[0], tracks: [{ id: "bad", path: "paint.radius", keyframes: withDefs.paintServers[0].tracks[0]!.keyframes }] }],
    })).toThrow(/does not identify an animatable property on paintServers/);
  });

  it("resolves an end-anchored keyframe against layer duration, staying correct when the clip is trimmed", () => {
    const fadeOutTrack = {
      id: "fade-out",
      path: "opacity",
      keyframes: [
        { time: 0, value: { type: "number" as const, value: 1 } },
        { time: { anchor: "end" as const, offsetMs: 300 }, value: { type: "number" as const, value: 0 } },
      ],
    };
    const fadeOutLayer = { ...RECTANGLE_PROJECT.layers[0], tracks: [fadeOutTrack] };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [fadeOutLayer],
    }).layers[0]?.tracks).toHaveLength(1);

    // A shorter, re-trimmed clip keeps the same authored offset and still
    // resolves correctly (300ms before the new, shorter end).
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{ ...fadeOutLayer, timing: { start: 0, duration: 500 } }],
    }).layers[0]?.tracks).toHaveLength(1);

    // layer.timing.duration is 1000; an end offset of 1200 resolves to -200.
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{
        ...fadeOutLayer,
        tracks: [{
          ...fadeOutTrack,
          keyframes: [
            fadeOutTrack.keyframes[0],
            { time: { anchor: "end" as const, offsetMs: 1200 }, value: { type: "number" as const, value: 0 } },
          ],
        }],
      }],
    })).toThrow(/cannot exceed layer duration/);
  });

  it("rejects an end-anchored keyframe combined with a looping animation", () => {
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{
        ...RECTANGLE_PROJECT.layers[0],
        tracks: [{
          id: "bad-loop",
          path: "opacity",
          keyframes: [{ time: { anchor: "end" as const, offsetMs: 100 }, value: { type: "number" as const, value: 1 } }],
          animation: {
            durationMs: 500,
            delayMs: 0,
            iterations: "infinite" as const,
            direction: "normal" as const,
            fillMode: "none" as const,
            playState: "running" as const,
          },
        }],
      }],
    })).toThrow(/cannot be combined with a looping animation/);
  });

  it("bounds a looping track's keyframes against animation.durationMs, independent of a shorter layer duration", () => {
    const loopingTrack = {
      id: "spin",
      path: "transform.rotate.z",
      keyframes: [
        { time: 0, value: { type: "number" as const, value: 0 } },
        { time: 1000, value: { type: "number" as const, value: 360 } },
      ],
      animation: {
        durationMs: 1000,
        delayMs: 0,
        iterations: "infinite" as const,
        direction: "normal" as const,
        fillMode: "none" as const,
        playState: "running" as const,
      },
    };
    const loopingLayer = {
      ...RECTANGLE_PROJECT.layers[0],
      timing: { start: 0, duration: 800 },
      tracks: [loopingTrack],
    };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [loopingLayer],
    }).layers[0]?.tracks).toHaveLength(1);

    // Without `animation`, the same keyframe shape bounds against the
    // (shorter) layer duration instead and is rejected.
    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{ ...loopingLayer, tracks: [{ id: loopingTrack.id, path: loopingTrack.path, keyframes: loopingTrack.keyframes }] }],
    })).toThrow(/cannot exceed layer duration/);
  });

  it("accepts animating transform.rotate.y (3D flip) with a plain number track, and rejects a value-kind mismatch", () => {
    const flipLayer = {
      ...RECTANGLE_PROJECT.layers[0],
      transform: {
        ...RECTANGLE_PROJECT.layers[0].transform,
        rotate: { x: 0, y: -90, z: 0 },
        perspective: 600,
      },
      tracks: [
        {
          id: "flip-y",
          path: "transform.rotate.y",
          keyframes: [
            { time: 0, value: { type: "number" as const, value: -90 } },
            { time: 400, value: { type: "number" as const, value: 0 } },
          ],
        },
      ],
    };
    expect(MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [flipLayer],
    }).layers[0]?.tracks).toHaveLength(1);

    expect(() => MotionProtocolV2Schema.parse({
      ...RECTANGLE_PROJECT,
      layers: [{
        ...flipLayer,
        tracks: [{
          id: "flip-y-bad-kind",
          path: "transform.rotate.y",
          keyframes: [{ time: 0, value: { type: "vec2" as const, value: [1, 1] } }],
        }],
      }],
    })).toThrow(/value type does not match/);
  });
});
