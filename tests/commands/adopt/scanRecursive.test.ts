import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { scanAdoptCandidates } from "../../../src/commands/adopt/scanRecursive";

describe("scanAdoptCandidates", () => {
  it("top-level mode only returns immediate children", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-scan-"));
    const app = path.join(root, "app");
    const nested = path.join(app, "nested");

    await mkdir(path.join(app, ".git"), { recursive: true });
    await mkdir(nested, { recursive: true });

    const found = await scanAdoptCandidates(root, false);

    expect(found.map((f) => f.path)).toEqual([app]);
    expect(found[0].kind).toBe("git");
  });

  it("recursive mode traverses nested directories and surfaces files as skipped", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-rec-"));
    const scripts = path.join(root, "scripts");
    const nestedRepo = path.join(scripts, "toolbox");
    const note = path.join(scripts, "todo.txt");

    await mkdir(path.join(nestedRepo, ".git"), { recursive: true });
    await writeFile(note, "remember me", "utf8");

    const found = await scanAdoptCandidates(root, true);

    expect(found).toEqual([
      { path: scripts, kind: "directory" },
      { path: note, kind: "file" },
      { path: nestedRepo, kind: "git" },
    ]);
  });

  it("skips node_modules, venv, and .git internals while recursing", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-skip-"));
    const repo = path.join(root, "repo");
    const ignoredNodeModules = path.join(repo, "node_modules", "left-pad");

    await mkdir(path.join(repo, ".git"), { recursive: true });
    await mkdir(ignoredNodeModules, { recursive: true });

    const found = await scanAdoptCandidates(root, true);

    expect(found.some((entry) => entry.path.includes("node_modules"))).toBe(false);
  });
});
