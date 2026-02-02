import { access } from "node:fs/promises";
import path from "node:path";

export type ArchiveTrustMode = "registry-first";

export type ArchiveEntry = {
  id: string;
  name: string;
  scope: "tool" | "software" | "archive";
  path: string;
};

export type ArchiveRegistry = {
  entries: ArchiveEntry[];
};

export type ArchivePlan = {
  name: string;
  fromPath: string;
  toPath: string;
  nextScope: "archive";
};

async function exists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function planArchiveMove(
  args: { name: string; trustMode: ArchiveTrustMode },
  registry: ArchiveRegistry,
  roots: { archiveRoot: string },
): Promise<ArchivePlan> {
  if (args.trustMode !== "registry-first") {
    throw new Error("strap archive supports registry-first trust mode only");
  }

  const entry = registry.entries.find((item) => item.name === args.name || item.id === args.name);
  if (!entry) {
    throw new Error(`Registry entry '${args.name}' not found`);
  }

  if (!(await exists(entry.path))) {
    throw new Error(`Registry path drift detected for '${entry.name}'. Run 'strap doctor --fix-paths'.`);
  }

  const toPath = path.join(roots.archiveRoot, path.basename(entry.path));
  if (await exists(toPath)) {
    throw new Error(`Destination already exists: ${toPath}`);
  }

  return {
    name: entry.name,
    fromPath: entry.path,
    toPath,
    nextScope: "archive",
  };
}
