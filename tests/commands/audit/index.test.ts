import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { loadOrBuildAuditIndex } from "../../../src/commands/audit/index";

describe("loadOrBuildAuditIndex", () => {
  it("builds index on first run and writes build/audit-index.json", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-"));
    const indexPath = path.join(root, "audit-index.json");

    const scanRepo = vi.fn(async (repoPath: string) => ({ references: [repoPath + "\\scripts\\x.ps1"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: false,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).toHaveBeenCalledTimes(1);
    expect(index.repos["C:\\Code\\chinvex"].references).toHaveLength(1);

    const onDisk = JSON.parse(await readFile(indexPath, "utf8"));
    expect(onDisk.registry_updated_at).toBe("2026-02-02T10:00:00.000Z");
  });

  it("reuses existing index when metadata is fresh and --rebuild-index is not set", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-fresh-"));
    const indexPath = path.join(root, "audit-index.json");

    await writeFile(
      indexPath,
      JSON.stringify(
        {
          built_at: "2026-02-02T10:00:00.000Z",
          registry_updated_at: "2026-02-02T10:00:00.000Z",
          repo_count: 1,
          repos: { "C:\\Code\\chinvex": { references: ["x"] } },
        },
        null,
        2,
      ),
      "utf8",
    );

    const scanRepo = vi.fn(async () => ({ references: ["new"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: false,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).not.toHaveBeenCalled();
    expect(index.repos["C:\\Code\\chinvex"].references).toEqual(["x"]);
  });

  it("forces rebuild when --rebuild-index is set", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-rebuild-"));
    const indexPath = path.join(root, "audit-index.json");

    await writeFile(
      indexPath,
      JSON.stringify(
        {
          built_at: "2026-02-01T00:00:00.000Z",
          registry_updated_at: "2026-02-01T00:00:00.000Z",
          repo_count: 1,
          repos: { "C:\\Code\\chinvex": { references: ["stale"] } },
        },
        null,
        2,
      ),
      "utf8",
    );

    const scanRepo = vi.fn(async () => ({ references: ["fresh"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: true,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).toHaveBeenCalledTimes(1);
    expect(index.repos["C:\\Code\\chinvex"].references).toEqual(["fresh"]);
  });
});
