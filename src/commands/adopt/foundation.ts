import { readdir, stat } from "node:fs/promises";
import path from "node:path";

export type AdoptArgs = {
  scanDir: string;
  recursive: boolean;
  dryRun: boolean;
  yes: boolean;
  allowAutoArchive: boolean;
  scope?: "tool" | "software" | "archive";
  trustMode: "disk-discovery";
};

export type AdoptScanItem = {
  path: string;
  kind: "git" | "directory" | "file";
  alreadyRegistered: boolean;
};

export function parseAdoptArgs(argv: string[]): AdoptArgs {
  let scanDir: string | undefined;
  let recursive = false;
  let dryRun = false;
  let yes = false;
  let allowAutoArchive = false;
  let scope: AdoptArgs["scope"];

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--scan" && argv[i + 1]) {
      scanDir = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === "--recursive") recursive = true;
    if (token === "--dry-run") dryRun = true;
    if (token === "--yes") yes = true;
    if (token === "--allow-auto-archive") allowAutoArchive = true;
    if (token === "--scope" && argv[i + 1]) {
      const next = argv[i + 1] as AdoptArgs["scope"];
      if (!["tool", "software", "archive"].includes(next)) {
        throw new Error("--scope must be tool|software|archive");
      }
      scope = next;
      i += 1;
    }
  }

  if (!scanDir) {
    throw new Error("adopt requires --scan <dir>");
  }

  return {
    scanDir: path.resolve(scanDir),
    recursive,
    dryRun,
    yes,
    allowAutoArchive,
    scope,
    trustMode: "disk-discovery",
  };
}

export async function scanAdoptTopLevel(scanDir: string, registryPathsLower: Set<string>): Promise<AdoptScanItem[]> {
  const dirents = await readdir(scanDir, { withFileTypes: true });
  const out: AdoptScanItem[] = [];

  for (const dirent of dirents) {
    const full = path.join(scanDir, dirent.name);
    const alreadyRegistered = registryPathsLower.has(full.toLowerCase());

    if (dirent.isFile()) {
      out.push({ path: full, kind: "file", alreadyRegistered: false });
      continue;
    }

    if (dirent.isDirectory()) {
      const gitDir = path.join(full, ".git");
      let kind: AdoptScanItem["kind"] = "directory";
      try {
        const s = await stat(gitDir);
        if (s.isDirectory()) kind = "git";
      } catch {
        kind = "directory";
      }

      out.push({ path: full, kind, alreadyRegistered });
    }
  }

  return out.sort((a, b) => a.path.localeCompare(b.path));
}
