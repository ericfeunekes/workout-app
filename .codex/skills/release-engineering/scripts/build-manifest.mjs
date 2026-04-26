#!/usr/bin/env node

import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
// From agents/skills/release-engineering/scripts/ to project root (4 levels up)
const projectRoot = resolve(__dirname, "../../../..");

const VALID_ENVIRONMENTS = ["dev", "qa", "stage", "prod"];

function parseArgs(argv) {
  const options = {
    env: null,
    envFile: null,
    out: null,
    variant: null,
    host: "taskpane",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--env") {
      options.env = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--env=")) {
      options.env = arg.split("=")[1];
      continue;
    }
    if (arg === "--env-file" || arg === "-e") {
      options.envFile = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--env-file=")) {
      options.envFile = arg.split("=")[1];
      continue;
    }
    if (arg === "--out" || arg === "-o") {
      options.out = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--out=")) {
      options.out = arg.split("=")[1];
      continue;
    }
    if (arg === "--variant" || arg === "-v") {
      options.variant = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--variant=")) {
      options.variant = arg.split("=")[1];
      continue;
    }
    if (arg === "--host") {
      options.host = argv[index + 1];
      index += 1;
      continue;
    }
    if (arg.startsWith("--host=")) {
      options.host = arg.split("=")[1];
      continue;
    }
  }

  return options;
}

// Deep merge objects
function deepMerge(target, source) {
  const output = { ...target };
  for (const key in source) {
    if (source[key] && typeof source[key] === "object" && !Array.isArray(source[key])) {
      output[key] = deepMerge(target[key] || {}, source[key]);
    } else {
      output[key] = source[key];
    }
  }
  return output;
}

// Load JSON config file
async function loadJsonFile(path) {
  try {
    await access(path, fsConstants.F_OK);
    const content = await readFile(path, "utf8");
    const parsed = JSON.parse(content);
    const { $schema, comment, ...data } = parsed;
    return data;
  } catch (error) {
    if (error.code === "ENOENT") {
      // Optional config files are allowed to be absent.
      console.debug(`[loadJsonFile] File not found (optional): ${path}`);
      return null;
    }
    throw error;
  }
}

// Resolve environment variables in config (e.g., ${AZURE_WEB_APP_URL})
function resolveEnvVars(config) {
  // Default values for local development when env vars not set
  const defaults = {
    AZURE_WEB_APP_URL: "https://localhost:3000",
  };

  function resolveValue(obj) {
    if (typeof obj === "string") {
      // Replace ${VAR_NAME} with process.env.VAR_NAME or default
      return obj.replace(/\$\{([A-Z_][A-Z0-9_]*)\}/g, (match, varName) => {
        return process.env[varName] || defaults[varName] || match;
      });
    } else if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      const resolved = {};
      for (const key in obj) {
        resolved[key] = resolveValue(obj[key]);
      }
      return resolved;
    } else if (Array.isArray(obj)) {
      return obj.map(resolveValue);
    }
    return obj;
  }

  return resolveValue(config);
}

// Load config from public-config directory
async function loadPublicConfig(env) {
  const configDir = resolve(projectRoot, "public-config");
  const configTypes = ["endpoints", "auth"];
  let merged = {};

  for (const type of configTypes) {
    const basePath = resolve(configDir, `${type}.base.json`);
    const baseConfig = await loadJsonFile(basePath);
    if (baseConfig) {
      merged = deepMerge(merged, baseConfig);
    }

    const envPath = resolve(configDir, `${type}.${env}.json`);
    const envConfig = await loadJsonFile(envPath);
    if (envConfig) {
      merged = deepMerge(merged, envConfig);
    }
  }

  // Resolve environment variables like ${AZURE_WEB_APP_URL}
  return resolveEnvVars(merged);
}

async function loadEnvFile(envPath) {
  const absolutePath = resolve(process.cwd(), envPath);
  const contents = await readFile(absolutePath, "utf8");
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) {
      continue;
    }
    const expression = line.startsWith("export ")
      ? line.slice("export ".length)
      : line;

    const equalsIndex = expression.indexOf("=");
    if (equalsIndex === -1) {
      continue;
    }

    const key = expression.slice(0, equalsIndex).trim();
    if (!key) {
      continue;
    }

    let value = expression.slice(equalsIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    // Don't overwrite existing env vars (allows CLI overrides)
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

function readEnv(key) {
  const value = process.env[key];
  if (!value) {
    return "";
  }
  const trimmed = value.trim();
  return trimmed;
}

function ensureEnv(key) {
  const value = readEnv(key);
  if (!value) {
    throw new Error(`[manifest] Missing required environment variable ${key}.`);
  }
  return value;
}

function ensureDirectoryUrl(value, key) {
  try {
    const url = new URL(value);
    const segments = url.pathname.split("/").filter(Boolean);
    const lastSegment =
      segments.length > 0 ? segments[segments.length - 1] : undefined;

    if (lastSegment && lastSegment.includes(".")) {
      throw new Error(
        `[manifest] ${key} must point to a directory URL, but "${lastSegment}" appears to be a file name.`,
      );
    }

    const normalizedPath = url.pathname.endsWith("/")
      ? url.pathname.slice(0, -1)
      : url.pathname;
    const directoryUrl = `${url.origin}${normalizedPath}`;
    return directoryUrl === "" ? url.origin : directoryUrl;
  } catch (error) {
    throw new Error(
      `[manifest] ${key} must be a valid absolute URL: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function joinUrl(base, path) {
  const normalizedBase = base.endsWith("/") ? base.slice(0, -1) : base;
  const normalizedPath = path.startsWith("/") ? path.slice(1) : path;
  return `${normalizedBase}/${normalizedPath}`;
}

function ensureTrailingSlash(url) {
  return url.endsWith("/") ? url : `${url}/`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  let deploymentEnv;
  let assetsBaseRaw;
  let clientId;
  let tenantId;
  let customApiScope;

  // If --env is specified, load from public-config
  if (args.env) {
    if (!VALID_ENVIRONMENTS.includes(args.env)) {
      throw new Error(`Invalid environment: ${args.env}. Must be one of: ${VALID_ENVIRONMENTS.join(", ")}`);
    }

    process.stdout.write(`[manifest] Loading config for environment: ${args.env}\n`);
    const config = await loadPublicConfig(args.env);

    clientId = config.clientId;
    tenantId = config.tenantId;
    customApiScope = config.customApiScope;
    deploymentEnv = args.env;

    // Derive assets URL from redirectUri
    if (config.redirectUri) {
      assetsBaseRaw = config.redirectUri.replace("/assets/auth.html", "");
    } else if (config.api?.baseUrl) {
      const apiUrl = new URL(config.api.baseUrl);
      assetsBaseRaw = apiUrl.origin;
    }
  } else {
    // Fall back to .env file loading
    if (args.envFile) {
      await loadEnvFile(args.envFile);
    } else {
      const defaultEnvPath = resolve(projectRoot, ".env");
      try {
        await access(defaultEnvPath, fsConstants.F_OK);
        await loadEnvFile(defaultEnvPath);
      } catch {
        // no local .env
      }
    }

    assetsBaseRaw = readEnv("REACT_APP_ASSETS_BASE_URL");
    clientId =
      readEnv("AZURE_ENTRA_CLIENT_ID") || readEnv("REACT_APP_AZURE_CLIENT_ID");
    tenantId =
      readEnv("AZURE_TENANT_ID") ||
      readEnv("AZURE_ENTRA_TENANT_ID") ||
      readEnv("REACT_APP_AZURE_TENANT_ID");

    if (!tenantId) {
      const authority = readEnv("REACT_APP_AZURE_AUTHORITY");
      if (authority) {
        try {
          const authorityUrl = new URL(authority);
          const parts = authorityUrl.pathname.split("/").filter(Boolean);
          const candidateTenantId = parts.at(-1);
          const guidRegex = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
          if (candidateTenantId && guidRegex.test(candidateTenantId)) {
            tenantId = candidateTenantId;
          } else {
            console.warn(
              `[manifest] Unable to extract valid tenantId from REACT_APP_AZURE_AUTHORITY path '${authorityUrl.pathname}'. Falling back to empty tenantId. Ensure REACT_APP_AZURE_AUTHORITY is a valid authority URL or set AZURE_TENANT_ID / REACT_APP_AZURE_TENANT_ID explicitly.`,
            );
          }
        } catch (error) {
          console.warn(
            `[manifest] Unable to parse REACT_APP_AZURE_AUTHORITY: ${
              error instanceof Error ? error.message : String(error)
            }. Falling back to empty tenantId. Ensure REACT_APP_AZURE_AUTHORITY is a valid URL or provide AZURE_TENANT_ID / REACT_APP_AZURE_TENANT_ID directly.`,
          );
        }
      }
    }
    deploymentEnv = readEnv("REACT_APP_DEPLOYMENT_ENV") || "dev";
  }

  if (!assetsBaseRaw) {
    throw new Error("[manifest] Could not determine assets base URL. Use --env or set REACT_APP_ASSETS_BASE_URL.");
  }
  if (!clientId) {
    throw new Error("[manifest] Could not determine client ID. Use --env or set AZURE_ENTRA_CLIENT_ID.");
  }
  if (!tenantId) {
    throw new Error("[manifest] Could not determine tenant ID. Use --env or set AZURE_TENANT_ID.");
  }

  const assetsBase = ensureDirectoryUrl(assetsBaseRaw, "assets base URL");

  // Size-specific icon URLs
  const icon16Url = joinUrl(assetsBase, "assets/icons/pwc-app-16x16.png");
  const icon32Url = joinUrl(assetsBase, "assets/icons/pwc-app-32x32.png");
  const icon64Url = joinUrl(assetsBase, "assets/icons/pwc-app-64x64.png");
  const icon80Url = joinUrl(assetsBase, "assets/icons/pwc-app-80x80.png");
  const icon128Url = joinUrl(assetsBase, "assets/icons/pwc-app-128x128.png");
  const supportUrl = joinUrl(assetsBase, "help");
  const taskpaneUrl = joinUrl(assetsBase, "taskpane.html");
  const commandsUrl = joinUrl(assetsBase, "commands.html");
  const appDomain = ensureTrailingSlash(assetsBase);

  process.stdout.write(`[manifest] Environment: ${deploymentEnv}\n`);
  process.stdout.write(`[manifest] Assets URL: ${assetsBase}\n`);
  process.stdout.write(`[manifest] Client ID: ${clientId}\n`);

  // Environment suffix for IDs (empty for prod, _env for others)
  const envSuffix = deploymentEnv === "prod" ? "" : `_${deploymentEnv}`;

  // Environment label for display names (empty for prod, " (Dev)" etc. for others)
  const envLabelMap = { dev: " (Dev)", qa: " (QA)", stage: " (Stage)", prod: "" };
  const envLabel = envLabelMap[deploymentEnv] ?? "";

  // Add-in ID per environment (XML manifest requires valid GUID)
  const addinIdMap = {
    dev: "0af7ef9a-0ef0-47bb-a108-b8226df6958f",
    qa: "20bb6ae1-1aee-4f75-9710-15bc1960754c",
    stage: "ed584627-1cf5-4efc-a7b5-37f3f48da5b1",
    prod: "5adea705-f388-4c12-be4b-120476a88742",
  };
  const addinId = readEnv("ADDIN_ID") || addinIdMap[deploymentEnv] || addinIdMap.dev;

  // Azure AD Resource - derive from customApiScope or use default
  // customApiScope format: api://{backend_id}/{frontend_id}/access_as_user
  // Resource format: api://{backend_id}/{frontend_id} (without scope suffix)
  const defaultResource =
    "api://59d4f275-30ad-496c-be0e-27a43f24929a/fa9a8102-49c7-4c49-8e8c-70bda0905cca";
  let azureAdResource = readEnv("AZURE_AD_RESOURCE");
  if (!azureAdResource && customApiScope) {
    // Extract resource from scope by removing the scope name suffix (e.g., /access_as_user)
    const lastSlashIndex = customApiScope.lastIndexOf("/");
    azureAdResource = lastSlashIndex > 0 ? customApiScope.slice(0, lastSlashIndex) : customApiScope;
  }
  azureAdResource = azureAdResource || defaultResource;

  const replacements = {
    ADDIN_ID: addinId,
    ICON_16: icon16Url,
    ICON_32: icon32Url,
    ICON_64: icon64Url,
    ICON_80: icon80Url,
    ICON_128: icon128Url,
    SUPPORT_URL: supportUrl,
    APP_DOMAIN: appDomain,
    TASKPANE_URL: taskpaneUrl,
    COMMANDS_URL: commandsUrl,
    AZURE_AD_APP_ID: clientId,
    AZURE_AD_RESOURCE: azureAdResource,
    ENV: deploymentEnv,
    ENV_LABEL: envLabel,
  };

  const templatePath = resolve(projectRoot, "manifest.template.xml");
  const template =
    args.host === "mailbox"
      ? await readFile(resolve(projectRoot, "manifest.mailbox.template.xml"), "utf8")
      : await readFile(templatePath, "utf8");

  const replaceTokens = (input, tokenMap) => {
    let output = input;
    for (const [token, value] of Object.entries(tokenMap)) {
      output = output.replace(new RegExp(`{{${token}}}`, "g"), value);
    }
    const unresolved = output.match(/{{([A-Z0-9_]+)}}/g);
    if (unresolved) {
      const unique = Array.from(new Set(unresolved));
      throw new Error(
        `[manifest] Unresolved template tokens: ${unique.join(", ")}`,
      );
    }
    return output;
  };

  const manifestXml = replaceTokens(template, replacements);

  const variantSuffix = args.variant ? `.${args.variant}` : "";
  const manifestBaseName =
    args.host === "mailbox" ? "manifest.mailbox" : "manifest";

  const xmlOutputPath = args.out
    ? resolve(process.cwd(), args.out)
    : resolve(projectRoot, "dist", `${manifestBaseName}${variantSuffix}.xml`);

  await mkdir(dirname(xmlOutputPath), { recursive: true });
  await writeFile(xmlOutputPath, manifestXml, "utf8");
  process.stdout.write(`[manifest] Wrote ${xmlOutputPath}\n`);

  // Teams manifest generation (taskpane-only)
  if (args.host === "mailbox") {
    return;
  }

  // Teams manifest generation
  const teamsTemplatePath = resolve(
    projectRoot,
    "manifest.teams.template.json",
  );
  const teamsTemplate = await readFile(teamsTemplatePath, "utf8");

  const webBaseRaw = readEnv("REACT_APP_WEB_BASE_URL") || assetsBaseRaw;
  const webBase = ensureDirectoryUrl(
    webBaseRaw,
    "REACT_APP_WEB_BASE_URL or REACT_APP_ASSETS_BASE_URL",
  );
  const webBaseWithSlash = ensureTrailingSlash(webBase);

  const teamsStaticTabUrl = joinUrl(webBase, "teams/index.html#/personal-chat");
  const teamsWebsiteUrl = webBaseWithSlash;
  const teamsTaskpaneUrl = joinUrl(webBase, "taskpane.html");
  const teamsCommandsUrl = joinUrl(webBase, "commands.html");
  const teamsCommandsScriptUrl = joinUrl(webBase, "commands.js");

  const outlineIconUrl = joinUrl(assetsBase, "assets/outline.png");
  const colorIconUrl = joinUrl(assetsBase, "assets/color.png");
  const teamsIcon16Url = joinUrl(assetsBase, "assets/icon-16.png");
  const teamsIcon32Url = joinUrl(assetsBase, "assets/icon-32.png");
  const teamsIcon80Url = joinUrl(assetsBase, "assets/icon-80.png");

  const domainsEnv = readEnv("REACT_APP_TEAMS_VALID_DOMAINS");
  const defaultDomains = [new URL(webBaseWithSlash).host];
  const extraDomains = domainsEnv
    ? domainsEnv
        .split(",")
        .map((domain) => domain.trim())
        .filter(Boolean)
    : [];
  const teamsValidDomains = JSON.stringify(
    Array.from(new Set([...defaultDomains, ...extraDomains])),
  );

  const teamsManifest = replaceTokens(teamsTemplate, {
    TEAMS_ICON_OUTLINE: outlineIconUrl,
    TEAMS_ICON_COLOR: colorIconUrl,
    TEAMS_ICON_16: teamsIcon16Url,
    TEAMS_ICON_32: teamsIcon32Url,
    TEAMS_ICON_80: teamsIcon80Url,
    TEAMS_VALID_DOMAINS: teamsValidDomains,
    TEAMS_STATIC_TAB_URL: teamsStaticTabUrl,
    TEAMS_WEBSITE_URL: teamsWebsiteUrl,
    TEAMS_TASKPANE_URL: teamsTaskpaneUrl,
    TEAMS_COMMANDS_URL: teamsCommandsUrl,
    TEAMS_COMMANDS_SCRIPT_URL: teamsCommandsScriptUrl,
    AZURE_AD_APP_ID: clientId,
    AZURE_AD_RESOURCE: azureAdResource,
    ENV: deploymentEnv,
    ENV_SUFFIX: envSuffix,
    ENV_LABEL: envLabel,
  });

  const teamsOutputPath = resolve(
    projectRoot,
    "dist",
    `teams.manifest${variantSuffix}.json`,
  );
  await mkdir(dirname(teamsOutputPath), { recursive: true });
  await writeFile(teamsOutputPath, teamsManifest, "utf8");
  process.stdout.write(`[manifest] Wrote ${teamsOutputPath}\n`);

  const teamsManifestPath = resolve(projectRoot, "manifest.json");
  await writeFile(teamsManifestPath, teamsManifest, "utf8");
  process.stdout.write(`[manifest] Updated ${teamsManifestPath}\n`);
}

main().catch((error) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : String(error)}\n`,
  );
  process.exitCode = 1;
});
