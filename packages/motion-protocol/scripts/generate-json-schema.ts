import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { zodToJsonSchema } from "zod-to-json-schema";
import { MotionProtocolV2Schema } from "../src/index";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const schemaDir = join(root, "schema");
const schemaPath = join(schemaDir, "v2.json");

if (!existsSync(schemaDir)) mkdirSync(schemaDir, { recursive: true });

const schema = zodToJsonSchema(MotionProtocolV2Schema, {
  name: "MotionProtocolV2",
  target: "jsonSchema7",
});

writeFileSync(schemaPath, `${JSON.stringify(schema, null, 2)}\n`, "utf8");
console.log("Generated schema/v2.json");
