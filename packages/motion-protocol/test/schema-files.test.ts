import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { zodToJsonSchema } from "zod-to-json-schema";
import { MotionProtocolV2Schema } from "../src/index";

const schemaPath = join(__dirname, "..", "schema", "v2.json");

describe("committed Protocol V2 JSON Schema", () => {
  it("schema/v2.json exists", () => {
    expect(existsSync(schemaPath)).toBe(true);
  });

  it("schema/v2.json matches the V2 Zod source", () => {
    const committed = readFileSync(schemaPath, "utf8").replace(/\r\n/g, "\n");
    const generated = `${JSON.stringify(zodToJsonSchema(MotionProtocolV2Schema, {
      name: "MotionProtocolV2",
      target: "jsonSchema7",
    }), null, 2)}\n`;
    expect(committed).toBe(generated);
  });

  it("schema root is strict Protocol V2", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as {
      definitions?: Record<string, { properties?: Record<string, unknown> }>;
    };
    const root = schema.definitions?.MotionProtocolV2;
    expect(root?.properties?.format).toBeDefined();
    expect(root?.properties?.formatVersion).toBeDefined();
    expect(root?.properties?.layers).toBeDefined();
  });

  it("keeps every generated object schema strict", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as unknown;
    const visit = (value: unknown, location: string): void => {
      if (value === null || typeof value !== "object") return;
      if (Array.isArray(value)) {
        value.forEach((item, index) => visit(item, `${location}[${index}]`));
        return;
      }
      const record = value as Record<string, unknown>;
      if (record.type === "object" && record.properties !== undefined) {
        expect(record.additionalProperties, location).toBe(false);
      }
      Object.entries(record).forEach(([key, item]) => visit(item, `${location}.${key}`));
    };
    visit(schema, "schema");
  });

  it("contains only Protocol V2 markers", () => {
    const source = readFileSync(schemaPath, "utf8");
    expect(source).not.toMatch(/motion-project|formatVersion[^\n]*1|MotionProjectV1|bone/);
  });
});
