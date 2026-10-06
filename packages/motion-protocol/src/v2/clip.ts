import { z } from "zod";
import {
  V2FiniteNumberSchema,
  V2IdSchema,
  V2PositiveNumberSchema,
} from "./common";
import { V2PaintSchema } from "./paint";
import { V2PathContourSchema } from "./path-geometry";
import { V2SvgTransformOperationSchema } from "./transform";

export const V2ClipPathUnitsSchema = z.enum(["userSpaceOnUse", "objectBoundingBox"]);
export const V2SvgDefinitionTransformSchema = z.array(V2SvgTransformOperationSchema).max(128);

const V2SvgDefinitionStyle = {
  fill: V2PaintSchema.optional(),
  fillOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
  stroke: V2PaintSchema.optional(),
  strokeWidth: V2PositiveNumberSchema.optional(),
  strokeOpacity: V2FiniteNumberSchema.min(0).max(1).optional(),
} as const;

export type V2SvgDefinitionNode =
  | ({ type: "path"; contours: z.infer<typeof V2PathContourSchema>[]; fillRule?: "nonzero" | "evenodd" } & V2SvgDefinitionNodeCommon)
  | ({ type: "rect"; x: number; y: number; width: number; height: number; rx?: number; ry?: number } & V2SvgDefinitionNodeCommon)
  | ({ type: "circle"; cx: number; cy: number; r: number } & V2SvgDefinitionNodeCommon)
  | ({ type: "ellipse"; cx: number; cy: number; rx: number; ry: number } & V2SvgDefinitionNodeCommon)
  | ({ type: "line"; x1: number; y1: number; x2: number; y2: number } & V2SvgDefinitionNodeCommon)
  | ({ type: "polyline"; points: Array<{ x: number; y: number }> } & V2SvgDefinitionNodeCommon)
  | ({ type: "polygon"; points: Array<{ x: number; y: number }> } & V2SvgDefinitionNodeCommon)
  | ({ type: "group"; children: V2SvgDefinitionNode[]; opacity?: number } & V2SvgDefinitionNodeCommon);

type V2SvgDefinitionNodeCommon = {
  transform?: z.infer<typeof V2SvgDefinitionTransformSchema>;
  clipPath?: string;
  fill?: z.infer<typeof V2PaintSchema>;
  fillOpacity?: number;
  stroke?: z.infer<typeof V2PaintSchema>;
  strokeWidth?: number;
  strokeOpacity?: number;
};

export const V2SvgDefinitionNodeSchema: z.ZodType<V2SvgDefinitionNode> = z.lazy(() => z.union([
  z.object({ type: z.literal("path"), contours: z.array(V2PathContourSchema).min(1), fillRule: z.enum(["nonzero", "evenodd"]).optional(), ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("rect"), x: V2FiniteNumberSchema, y: V2FiniteNumberSchema, width: V2PositiveNumberSchema, height: V2PositiveNumberSchema, rx: V2FiniteNumberSchema.nonnegative().optional(), ry: V2FiniteNumberSchema.nonnegative().optional(), ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("circle"), cx: V2FiniteNumberSchema, cy: V2FiniteNumberSchema, r: V2PositiveNumberSchema, ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("ellipse"), cx: V2FiniteNumberSchema, cy: V2FiniteNumberSchema, rx: V2PositiveNumberSchema, ry: V2PositiveNumberSchema, ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("line"), x1: V2FiniteNumberSchema, y1: V2FiniteNumberSchema, x2: V2FiniteNumberSchema, y2: V2FiniteNumberSchema, ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("polyline"), points: z.array(z.object({ x: V2FiniteNumberSchema, y: V2FiniteNumberSchema }).strict()).min(2), ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("polygon"), points: z.array(z.object({ x: V2FiniteNumberSchema, y: V2FiniteNumberSchema }).strict()).min(3), ...V2SvgDefinitionStyle, transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
  z.object({ type: z.literal("group"), children: z.array(V2SvgDefinitionNodeSchema).min(1), opacity: V2FiniteNumberSchema.min(0).max(1).optional(), transform: V2SvgDefinitionTransformSchema.optional(), clipPath: V2IdSchema.optional() }).strict(),
]));

export const V2ClipPathNodeSchema = V2SvgDefinitionNodeSchema;

export const V2ClipPathSchema = z
  .object({
    id: V2IdSchema,
    clipPathUnits: V2ClipPathUnitsSchema.default("userSpaceOnUse"),
    transform: V2SvgDefinitionTransformSchema.optional(),
    children: z.array(V2ClipPathNodeSchema).min(1),
  })
  .strict();

export const V2ClipPathListSchema = z
  .array(V2ClipPathSchema)
  .max(256)
  .superRefine((clips, ctx) => {
    const ids = new Set<string>();
    clips.forEach((clip, index) => {
      if (ids.has(clip.id)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Duplicate clipPath id: ${clip.id}`, path: [index, "id"] });
      ids.add(clip.id);
    });
  });

export type V2ClipPathUnits = z.infer<typeof V2ClipPathUnitsSchema>;
export type V2ClipPath = z.infer<typeof V2ClipPathSchema>;
export type V2ClipPathList = z.infer<typeof V2ClipPathListSchema>;
