import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { migrateConfigIfNeeded } from "../../src/config/migrateConfig";

describe("migrateConfigIfNeeded", () => {
  it("adds roots.archive and archive_threshold_days to legacy config and writes backup", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-config-"));
    const configPath = path.join(root, "config.json");

    await writeFile(
      configPath,
      JSON.stringify(
        {
          roots: {
            software: "P:\\software",
            tools: "P:\\software\\_scripts",
            shims: "P:\\software\\_scripts\\_bin",
          },
          registry: "P:\\software\\_strap\\build\\registry.json",
        },
        null,
        2,
      ),
      "utf8",
    );

    const result = await migrateConfigIfNeeded(configPath);

    expect(result.changed).toBe(true);

    const migrated = JSON.parse(await readFile(configPath, "utf8"));
    expect(migrated.roots.archive).toBe("P:\\software\\_archive");
    expect(migrated.archive_threshold_days).toBe(180);

    const backupPath = path.join(root, "config.pre-archive-migration.backup.json");
    const backup = JSON.parse(await readFile(backupPath, "utf8"));
    expect(backup.archive_threshold_days).toBeUndefined();
  });

  it("is a no-op when config already has required fields", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-config-"));
    const configPath = path.join(root, "config.json");

    await writeFile(
      configPath,
      JSON.stringify(
        {
          roots: {
            software: "P:\\software",
            tools: "P:\\software\\_scripts",
            shims: "P:\\software\\_scripts\\_bin",
            archive: "P:\\software\\_archive",
          },
          registry: "P:\\software\\_strap\\build\\registry.json",
          archive_threshold_days: 180,
        },
        null,
        2,
      ),
      "utf8",
    );

    const result = await migrateConfigIfNeeded(configPath);
    expect(result.changed).toBe(false);
  });
});
