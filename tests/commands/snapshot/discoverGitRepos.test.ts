import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { discoverGitRepos } from "../../../src/commands/snapshot/discoverGitRepos";

describe("discoverGitRepos", () => {
  it("discovers git repos and collects remote + commit metadata", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-discover-"));
    const repoPath = path.join(root, "chinvex");
    const dirPath = path.join(root, "misc-scripts");

    await mkdir(path.join(repoPath, ".git"), { recursive: true });
    await mkdir(dirPath, { recursive: true });
    await writeFile(path.join(dirPath, "script.ps1"), "Write-Host x", "utf8");

    const registryByPath = new Map<string, string>([[repoPath.toLowerCase(), "chinvex"]]);

    const repos = await discoverGitRepos([repoPath, dirPath], {
      registryByPath,
      execGit: async (repo, args) => {
        if (args.join(" ") === "remote get-url origin") return "git@github.com:Chinvex/strap.git";
        if (args.join(" ") === "log -1 --format=%cI") return "2026-01-31T12:34:56+00:00";
        throw new Error(`unexpected git args for ${repo}: ${args.join(" ")}`);
      },
    });

    expect(repos).toEqual([
      {
        path: repoPath,
        name: "chinvex",
        type: "git",
        in_registry: true,
        remote_url: "https://github.com/chinvex/strap",
        last_commit: "2026-01-31T12:34:56+00:00",
      },
    ]);
  });
});
