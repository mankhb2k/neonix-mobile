import type { z } from "zod";
import type { V2Composition } from "./composition";
import type { V2Asset } from "./assets";
import type { V2Filter } from "./filter";
import type { V2AudioDomain } from "./audio";
import type { V2Marker } from "./markers";
import type { V2ClipPath } from "./clip";
import type { V2Mask } from "./mask";
import type { V2PaintServerDefinition } from "./paint";
import { V2LayerSchema } from "./layers";

export type MotionProtocolV2 = {
  format: "motion-protocol";
  formatVersion: 2;
  id: string;
  composition: V2Composition;
  assets: Array<V2Asset>;
  filters?: Array<V2Filter>;
  /** SVG-style marker definitions resolved by marker references on drawable layers. */
  markers?: Array<V2Marker>;
  clipPaths?: Array<V2ClipPath>;
  masks?: Array<V2Mask>;
  paintServers?: Array<V2PaintServerDefinition>;
  layers: Array<z.infer<typeof V2LayerSchema>>;
  audio: V2AudioDomain;
};
