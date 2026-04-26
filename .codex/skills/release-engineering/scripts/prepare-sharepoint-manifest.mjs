import { promises as fs } from "fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../../../../");
const HOST_ROOT = path.join(ROOT, "hosts", "sharepoint");
const SRC_MANIFEST = path.join(
  HOST_ROOT,
  "src",
  "sharepoint-webpart.manifest.json",
);
const WRITE_CONFIG = path.join(HOST_ROOT, "config", "write-manifests.json");
const RELEASE_DIR = path.join(HOST_ROOT, "release", "manifests");

const COMPONENT_VERSIONS = Object.freeze({
  "@microsoft/sp-core-library": {
    id: "7263c7d0-1d6a-45ec-8d85-d4d1d234171b",
    version: "1.21.1",
  },
  "@microsoft/sp-loader": {
    id: "1c6c9123-7aac-41f3-a376-3caea41ed83f",
    version: "1.21.1",
  },
  "@microsoft/sp-webpart-base": {
    id: "a3d5c2cb-fd46-4b0d-a062-02a2b72a0ed8",
    version: "1.21.1",
  },
});

const loadJson = async (filePath) => {
  const raw = await fs.readFile(filePath, "utf8");
  return JSON.parse(raw);
};

const buildLoaderConfig = (cdnBasePath) => ({
  entryModuleId: "index",
  internalModuleBaseUrls: [cdnBasePath, "./"],
  scriptResources: {
    index: {
      type: "path",
      path: "sharepoint-webpart.js",
    },
    ...Object.fromEntries(
      Object.entries(COMPONENT_VERSIONS).map(([name, meta]) => [
        name,
        {
          type: "component",
          id: meta.id,
          version: meta.version,
        },
      ]),
    ),
  },
});

async function main() {
  const [manifest, writeConfig] = await Promise.all([
    loadJson(SRC_MANIFEST),
    loadJson(WRITE_CONFIG).catch(() => ({
      cdnBasePath: "https://localhost:3000/sharepoint",
    })),
  ]);

  const cdnBasePath =
    writeConfig.cdnBasePath || "https://localhost:3000/sharepoint";

  const nextManifest = {
    requiresCustomScript: false,
    ...manifest,
    loaderConfig: buildLoaderConfig(cdnBasePath.replace(/\/+$/, "/")),
  };

  await fs.rm(RELEASE_DIR, { recursive: true, force: true });
  await fs.mkdir(RELEASE_DIR, { recursive: true });

  const fileName = `${manifest.id.toLowerCase()}.manifest.json`;
  const outputPath = path.join(RELEASE_DIR, fileName);
  await fs.writeFile(
    outputPath,
    `${JSON.stringify(nextManifest, null, 2)}\n`,
    "utf8",
  );

  console.log(`Wrote SharePoint manifest to ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
