import { describe, expect, it } from "vitest";
import { buildSnapshotManifest } from "../../../src/commands/snapshot/buildSnapshotManifest";

describe("buildSnapshotManifest", () => {
  it("builds the snapshot JSON payload with disk_usage in GB", async () => {
    const manifest = await buildSnapshotManifest({
      nowIso: "2026-02-02T02:00:00.000Z",
      registry: {
        registry_version: 2,
        entries: [{ id: "chinvex", name: "chinvex", scope: "software", path: "C:\\Code\\chinvex" }],
      },
      discovered: [{ path: "C:\\Code\\chinvex", in_registry: true, name: "chinvex", type: "git" }],
      externalRefs: {
        pm2: [{ name: "chinvex-gateway", cwd: "C:\\Code\\chinvex" }],
        scheduled_tasks: [],
        shims: [],
        path_entries: [],
        profile_refs: [],
      },
      getDiskInfo: async () => ({
        "C:": { totalBytes: 500 * 1024 ** 3, freeBytes: 50 * 1024 ** 3 },
        "P:": { totalBytes: 2_000 * 1024 ** 3, freeBytes: 1_200 * 1024 ** 3 },
      }),
    });

    expect(manifest.timestamp).toBe("2026-02-02T02:00:00.000Z");
    expect(manifest.disk_usage).toEqual({
      "C:": { total_gb: 500, free_gb: 50 },
      "P:": { total_gb: 2000, free_gb: 1200 },
    });
    expect(manifest.external_refs.pm2[0].name).toBe("chinvex-gateway");
  });
});
