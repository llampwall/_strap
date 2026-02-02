import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseAdoptArgs, scanAdoptTopLevel } from "../../../src/commands/adopt/foundation";

describe("adopt foundation", () => {
  it("parses scan-mode flags and defaults to disk-discovery trust mode", () => {
    const parsed = parseAdoptArgs([
      "--scan",
      "C:\\Code",
      "--recursive",
      "--dry-run",
      "--yes",
      "--scope",
      "tool",
    ]);

    expect(parsed.scanDir).toBe(path.resolve("C:\\Code"));
    expect(parsed.recursive).toBe(true);
    expect(parsed.dryRun).toBe(true);
    expect(parsed.yes).toBe(true);
    expect(parsed.scope).toBe("tool");
    expect(parsed.trustMode).toBe("disk-discovery");
  });

  it("errors when --scan is missing", () => {
    expect(() => parseAdoptArgs(["--yes"])).toThrow("adopt requires --scan <dir>");
  });

  it("scans top-level items and marks already-registered directories", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-top-"));
    const existingRepo = path.join(root, "chinvex");
    const newDir = path.join(root, "notes");
    const helper = path.join(root, "helper.ps1");

    await mkdir(path.join(existingRepo, ".git"), { recursive: true });
    await mkdir(newDir, { recursive: true });
    await writeFile(helper, "Write-Host hi", "utf8");

    const items = await scanAdoptTopLevel(root, new Set([existingRepo.toLowerCase()]));

    expect(items).toEqual([
      { path: existingRepo, kind: "git", alreadyRegistered: true },
      { path: helper, kind: "file", alreadyRegistered: false },
      { path: newDir, kind: "directory", alreadyRegistered: false },
    ]);
  });
});
