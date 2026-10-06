/** Public Protocol V2 API. */

import type { MotionProtocolV2 } from "./v2";
import { parseMotionProtocolV2WithMigration } from "./migration";

export * from "./v2";
export {
  migrateMotionProtocolV2,
  parseMotionProtocolV2WithMigration,
  type MotionProtocolV2Migration,
  type ProtocolMigrationDiagnostic,
} from "./migration";

export const MOTION_FORMAT_VERSION = 2 as const;

export function parseMotionProtocol(input: unknown): MotionProtocolV2 {
  return parseMotionProtocolV2WithMigration(input).project;
}

export function serializeMotionProtocol(project: MotionProtocolV2): string {
  return JSON.stringify(project);
}
