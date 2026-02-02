import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { migrateRegistryToV2 } from "../../src/registry/migrateToV2";

describe("migrateRegistryToV2", () => {
  it("backs up v1 registry and upgrades to v2 with trust_mode metadata", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-registry-"));
    const buildDir = path.join(root, "build");
    const registryPath = path.join(buildDir, "registry.json");

    await mkdir(buildDir, { recursive: true });
    await writeFile(
      registryPath,
      JSON.stringify(
        {
          registry_version: 1,
          updated_at: "2026-02-01T00:00:00.000Z",
          entries: [{ id: "chinvex", name: "chinvex", scope: "software", path: "C:\\Code\\chinvex" }],
        },
        null,
        2,
      ),
      "utf8",
    );

    await migrateRegistryToV2(registryPath, "2026-02-02T01:00:00.000Z");

    const upgraded = JSON.parse(await readFile(registryPath, "utf8"));
    expect(upgraded.registry_version).toBe(2);
    expect(upgraded.updated_at).toBe("2026-02-02T01:00:00.000Z");
    expect(upgraded.metadata).toEqual({ trust_mode: "registry-first" });
    expect(upgraded.entries[0]).toMatchObject({
      scope: "software",
      archived_at: null,
      last_commit: null,
    });

    const backupPath = path.join(buildDir, "registry.v1.backup.json");
    const backup = JSON.parse(await readFile(backupPath, "utf8"));
    expect(backup.registry_version).toBe(1);
    expect(backup.entries).toHaveLength(1);
  });
});
