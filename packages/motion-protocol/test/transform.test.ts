import { describe, expect, it } from "vitest";
import { V2TransformSchema } from "../src/v2/transform";

const components = {
  translate: { x: 0, y: 0, z: 0 },
  scale: { x: 1, y: 1, z: 1 },
  rotate: { x: 0, y: 0, z: 0 },
  skew: { x: 0, y: 0 },
  anchor: { x: 0, y: 0, z: 0 },
};

describe("Protocol V2 layer transform", () => {
  it("accepts the component form alone, with no operations[]/extensions fields", () => {
    const transform = V2TransformSchema.parse(components);
    expect(transform).toEqual(components);
  });

  it("accepts 3D rotation plus perspective for flip-style transforms", () => {
    const transform = V2TransformSchema.parse({
      ...components,
      rotate: { x: 0, y: -90, z: 0 },
      perspective: 600,
    });
    expect(transform.rotate).toEqual({ x: 0, y: -90, z: 0 });
    expect(transform.perspective).toBe(600);
  });

  it("rejects a non-positive perspective", () => {
    expect(() => V2TransformSchema.parse({ ...components, perspective: 0 })).toThrow();
    expect(() => V2TransformSchema.parse({ ...components, perspective: -10 })).toThrow();
  });

  it("rejects an operations[] or extensions field — removed in favor of the explicit component form", () => {
    expect(() =>
      V2TransformSchema.parse({ ...components, operations: [{ type: "translate", x: 100, y: 0 }] }),
    ).toThrow();
    expect(() => V2TransformSchema.parse({ ...components, extensions: { anchor: { x: 0, y: 0, z: 10 } } })).toThrow();
  });
});
