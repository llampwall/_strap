import { copyFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

type RegistryEntryV1 = {
  id: string;
  name: string;
  scope: "tool" | "software";
  path: string;
};

type RegistryV1 = {
  registry_version: 1;
  updated_at: string;
  entries: RegistryEntryV1[];
};

type RegistryEntryV2 = RegistryEntryV1 & {
  archived_at: string | null;
  last_commit: string | null;
};

type RegistryV2 = {
  registry_version: 2;
  updated_at: string;
  metadata: { trust_mode: "registry-first" | "disk-discovery" };
  entries: RegistryEntryV2[];
};

export async function migrateRegistryToV2(registryPath: string, nowIso: string): Promise<void> {
  const raw = await readFile(registryPath, "utf8");
  const parsed = JSON.parse(raw) as RegistryV1 | RegistryV2;

  if (parsed.registry_version === 2) {
    return;
  }

  if (parsed.registry_version !== 1) {
    throw new Error("Registry requires strap version X.Y+, please upgrade");
  }

  const backupPath = path.join(path.dirname(registryPath), "registry.v1.backup.json");
  await copyFile(registryPath, backupPath);

  const upgraded: RegistryV2 = {
    registry_version: 2,
    updated_at: nowIso,
    metadata: { trust_mode: "registry-first" },
    entries: parsed.entries.map((entry) => ({
      ...entry,
      archived_at: null,
      last_commit: null,
    })),
  };

  await writeFile(registryPath, JSON.stringify(upgraded, null, 2), "utf8");
}
