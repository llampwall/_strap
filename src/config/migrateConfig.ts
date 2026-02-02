import { copyFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

type LegacyConfig = {
  roots?: {
    software?: string;
    tools?: string;
    shims?: string;
    archive?: string;
  };
  registry?: string;
  archive_threshold_days?: number;
};

export async function migrateConfigIfNeeded(configPath: string): Promise<{ changed: boolean }> {
  const raw = await readFile(configPath, "utf8");
  const parsed = JSON.parse(raw) as LegacyConfig;

  const hasArchiveRoot = Boolean(parsed.roots?.archive);
  const hasThreshold = Number.isInteger(parsed.archive_threshold_days) && (parsed.archive_threshold_days as number) > 0;

  if (hasArchiveRoot && hasThreshold) {
    return { changed: false };
  }

  const backupPath = path.join(path.dirname(configPath), "config.pre-archive-migration.backup.json");
  await copyFile(configPath, backupPath);

  const softwareRoot = parsed.roots?.software ?? "P:\\software";

  const migrated = {
    ...parsed,
    roots: {
      ...(parsed.roots ?? {}),
      archive: parsed.roots?.archive ?? `${softwareRoot}\\_archive`,
    },
    archive_threshold_days:
      Number.isInteger(parsed.archive_threshold_days) && (parsed.archive_threshold_days as number) > 0
        ? parsed.archive_threshold_days
        : 180,
  };

  await writeFile(configPath, JSON.stringify(migrated, null, 2), "utf8");
  return { changed: true };
}
