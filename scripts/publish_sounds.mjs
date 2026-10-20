// Publishes the starter sound-effect set to R2 (bucket neonix-system-assets, prefix soudeffects/ - the folder was created with that spelling).
//   node scripts/publish_sounds.mjs --dry-run     show what would be uploaded
//   node scripts/publish_sounds.mjs               upload (credentials from api/.env)
// Source files: public/preview/sounds (made by scripts/generate_sfx.py; synthesized, no third-party material).
// Layout in the bucket: soudeffects/manifest.json, soudeffects/<category>/<slug>.m4a
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(path.join(root, "api", "package.json"));
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const PREFIX = "soudeffects";
const dryRun = process.argv.includes("--dry-run");
const sourceDir = path.join(root, "public/preview/sounds");
const source = JSON.parse(fs.readFileSync(path.join(sourceDir, "sounds.json"), "utf8"));

const sounds = source.sounds.map((s) => {
  const relative = s.file.replace(/^sounds\//, "");
  const local = path.join(sourceDir, relative);
  if (!fs.existsSync(local)) throw new Error(`missing file ${local}`);
  return { id: s.id, name: s.name, category: s.category, file: `${PREFIX}/${relative}`, durationMs: s.durationMs, mimeType: "audio/mp4", peaks: s.peaks, local };
});
const manifest = {
  version: 1,
  categories: source.categories,
  sounds: sounds.map(({ local, ...entry }) => entry),
};

const uploads = [
  { key: `${PREFIX}/manifest.json`, body: Buffer.from(JSON.stringify(manifest, null, 2)), type: "application/json", cache: "public, max-age=300" },
  ...sounds.map((s) => ({ key: s.file, body: fs.readFileSync(s.local), type: "audio/mp4" })),
];

console.log(`${sounds.length} sounds in ${manifest.categories.length} categories, ${uploads.length} objects, ${(uploads.reduce((n, u) => n + u.body.length, 0) / 1024).toFixed(0)} KB`);
if (dryRun) { for (const u of uploads.slice(0, 5)) console.log("  ", u.key); console.log("   ..."); process.exit(0); }

const env = {};
for (const line of fs.readFileSync(path.join(root, "api/.env"), "utf8").split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].replace(/^"|"$/g, "");
}
const bucket = env.R2_SYSTEM_ASSETS_BUCKET || "neonix-system-assets";
const client = new S3Client({
  region: "auto", endpoint: `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY },
});
let done = 0;
for (const u of uploads) {
  await client.send(new PutObjectCommand({ Bucket: bucket, Key: u.key, Body: u.body, ContentType: u.type, CacheControl: u.cache || "public, max-age=31536000, immutable" }));
  done += 1;
}
console.log(`uploaded ${done} objects to ${bucket}`);
