// Publishes the curated sticker set to R2 (bucket neonix-system-assets, prefix stickers/).
//   node scripts/publish_stickers.mjs --dry-run     show what would be uploaded
//   node scripts/publish_stickers.mjs               upload (credentials from api/.env)
// Source files: public/preview/stickers (made by scripts/fetch_fluent_stickers.py: Fluent Emoji 3D, MIT, Microsoft).
// Layout in the bucket: stickers/manifest.json, stickers/LICENSE-fluentui-emoji.txt, stickers/<category>/<slug>.png
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(path.join(root, "api", "package.json"));
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const dryRun = process.argv.includes("--dry-run");
const sourceDir = path.join(root, "public/preview/stickers");

// 50 of the 100 downloaded, picked by hand: general-audience, recognisable, a spread of 6 categories.
const PICKS = {
  "smileys-emotion": ["Astonished face", "Exploding head", "Face with rolling eyes", "Face with tears of joy", "Grinning face",
    "Grinning face with big eyes", "Kissing face", "Light blue heart", "Nerd face", "Partying face"],
  "animals-nature": ["Blossom", "Cherry blossom", "Chicken", "Fish", "Maple leaf", "Rabbit face", "Raccoon", "Rose", "Tulip"],
  "food-drink": ["Blueberries", "Burrito", "French fries", "Grapes", "Hot dog", "Peach", "Red apple", "Sushi"],
  "objects": ["Film frames", "Musical notes", "Notebook", "Studio microphone", "Shopping cart", "Bookmark"],
  "travel-places": ["Aerial tramway", "Cloud with lightning and rain", "Glowing star", "New moon face", "Rainbow", "Speedboat",
    "Waning crescent moon", "Wedding"],
  "activities": ["2nd place medal", "Baseball", "Magic wand", "Mirror ball", "Ping pong", "Piñata", "Ribbon", "Sparkler", "Tennis"],
};
const CATEGORY_TITLES = {
  "smileys-emotion": "Smileys", "animals-nature": "Nature", "food-drink": "Food", "objects": "Objects",
  "travel-places": "Travel", "activities": "Activities",
};

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const source = JSON.parse(fs.readFileSync(path.join(sourceDir, "stickers.json"), "utf8"));

const stickers = [];
for (const [category, names] of Object.entries(PICKS)) {
  for (const name of names) {
    const entry = source.find((s) => s.name === name && s.file.startsWith(category + "/"));
    if (!entry) throw new Error(`not found in stickers.json: ${category} / ${name}`);
    const file = `${category}/${path.basename(entry.file)}`;
    if (!fs.existsSync(path.join(sourceDir, file))) throw new Error(`missing file ${file}`);
    stickers.push({ id: slug(name), name, category, file: `stickers/${file}`, width: 256, height: 256 });
  }
}

const manifest = {
  version: 1,
  license: {
    name: "MIT", holder: "Microsoft Corporation", source: "https://github.com/microsoft/fluentui-emoji",
    file: "stickers/LICENSE-fluentui-emoji.txt",
  },
  categories: Object.keys(PICKS).map((id) => ({ id, title: CATEGORY_TITLES[id] })),
  stickers,
};

const licenseText = await (await fetch("https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/LICENSE")).text();
if (!licenseText.includes("MIT License")) throw new Error("could not fetch the Fluent Emoji LICENSE");

const uploads = [
  { key: "stickers/manifest.json", body: Buffer.from(JSON.stringify(manifest, null, 2)), type: "application/json", cache: "public, max-age=300" },
  { key: "stickers/LICENSE-fluentui-emoji.txt", body: Buffer.from(licenseText), type: "text/plain; charset=utf-8" },
  ...stickers.map((s) => ({ key: s.file, body: fs.readFileSync(path.join(sourceDir, s.file.replace(/^stickers\//, ""))), type: "image/png" })),
];

console.log(`${stickers.length} stickers in ${Object.keys(PICKS).length} categories, ${uploads.length} objects, ${(uploads.reduce((n, u) => n + u.body.length, 0) / 1024).toFixed(0)} KB`);
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
