import { promises as fs } from "fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Resolve repo root relative to this script: scripts/.../copy-sharepoint-bundle.mjs -> go up 5 levels to repo root.
// Original logic produced C:\C:\ duplication under some Windows path resolutions.
const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
// Adjust depth: agents/skills/release-engineering/scripts -> repo root is 5 levels up from scripts directory.
const ROOT = path.resolve(scriptDir, "../../../..");
// Standalone SharePoint bundle is emitted by webpack.standalone.config.js to public/standalone.js
const DIST_DIR = path.join(ROOT, "public");
const TARGET_DIR = path.join(ROOT, "hosts", "sharepoint", "temp", "deploy");

async function main() {
  const hasDist = await fs
    .access(DIST_DIR)
    .then(() => true)
    .catch(() => false);
  if (!hasDist) {
    throw new Error(
      `Bundle directory not found: ${DIST_DIR}\n` +
        `Ensure you ran 'npm run build:standalone' at the repo root before sharepoint:copy.\n` +
        `Resolved ROOT: ${ROOT}\nScript Path: ${scriptPath}`,
    );
  }
  await fs.mkdir(TARGET_DIR, { recursive: true });
  const entries = (await fs.readdir(DIST_DIR)).filter((entry) =>
    entry === "standalone.js" || entry === "standalone.js.map"
  );
  let copiedCount = 0;
  await Promise.all(
    entries.map(async (entry) => {
      const source = path.join(DIST_DIR, entry);
      const destination = path.join(TARGET_DIR, entry);
      const stats = await fs.lstat(source);
      if (stats.isDirectory()) {
        await fs.cp(source, destination, { recursive: true });
      } else {
        await fs.copyFile(source, destination);
      }
      copiedCount += 1;
    }),
  );
  console.log(`Copied ${copiedCount} entries to ${TARGET_DIR}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
