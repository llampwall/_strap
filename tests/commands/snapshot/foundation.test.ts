import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseSnapshotArgs, scanDirectoriesTopLevel } from "../../../src/commands/snapshot/foundation";

describe("snapshot foundation", () => {
  it("parses --output and repeated --scan flags", () => {
    const parsed = parseSnapshotArgs([
      "--output",
      "build/snap.json",
      "--scan",
      "C:\\Code",
      "--scan",
      "P:\\software",
    ]);

    expect(parsed.outputPath).toBe(path.resolve("build/snap.json"));
    expect(parsed.scanDirs).toEqual([path.resolve("C:\\Code"), path.resolve("P:\\software")]);
    expect(parsed.trustMode).toBe("disk-discovery");
  });

  it("scans top-level entries and classifies files vs directories", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-scan-"));
    const repoDir = path.join(root, "chinvex");
    const plainDir = path.join(root, "notes");
    const filePath = path.join(root, "helper.ps1");

    await mkdir(repoDir, { recursive: true });
    await mkdir(plainDir, { recursive: true });
    await writeFile(filePath, "Write-Host hi", "utf8");

    const entries = await scanDirectoriesTopLevel([root]);
    expect(entries).toEqual([
      { path: repoDir, type: "directory" },
      { path: filePath, type: "file" },
      { path: plainDir, type: "directory" },
    ]);
  });
});
