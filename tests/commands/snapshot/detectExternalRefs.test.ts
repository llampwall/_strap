import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { detectExternalRefs } from "../../../src/commands/snapshot/detectExternalRefs";

describe("detectExternalRefs", () => {
  it("detects PM2, scheduled tasks, and shim targets that reference known repos", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-refs-"));
    const shimDir = path.join(root, "build", "shims");
    await mkdir(shimDir, { recursive: true });

    await writeFile(
      path.join(shimDir, "chinvex.cmd"),
      '@echo off\nset "TARGET=C:\\Code\\chinvex\\scripts\\cli.ps1"\npowershell -File "%TARGET%"\n',
      "utf8",
    );

    const refs = await detectExternalRefs({
      repoPaths: ["C:\\Code\\chinvex"],
      shimDir,
      runPm2Jlist: async () =>
        JSON.stringify([{ name: "chinvex-gateway", pm2_env: { pm_cwd: "C:\\Code\\chinvex" } }]),
      runScheduledTasksCsv: async () =>
        [
          'TaskName,Execute,Arguments',
          'MorningBrief,powershell.exe,-File C:\\Code\\chinvex\\scripts\\morning_brief.ps1',
        ].join("\n"),
    });

    expect(refs.pm2).toEqual([{ name: "chinvex-gateway", cwd: "C:\\Code\\chinvex" }]);
    expect(refs.scheduled_tasks).toEqual([
      { name: "MorningBrief", path: "C:\\Code\\chinvex\\scripts\\morning_brief.ps1" },
    ]);
    expect(refs.shims).toEqual([{ name: "chinvex", target: "C:\\Code\\chinvex\\scripts\\cli.ps1" }]);
  });
});
