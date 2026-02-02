import { describe, expect, it, vi } from "vitest";
import { runConsolidate } from "../../../src/commands/consolidate/runConsolidate";

describe("runConsolidate integration", () => {
  it("runs wizard steps 1-4 only in dry-run mode", async () => {
    const calls: string[] = [];

    const result = await runConsolidate(
      {
        from: "C:\\Code",
        dryRun: true,
        yes: true,
        stopPm2: false,
        ackScheduledTasks: true,
      },
      {
        snapshot: async () => {
          calls.push("snapshot");
          return { path: "build/consolidate-snapshot.json" };
        },
        discovery: async () => {
          calls.push("discovery");
          return { adopted: [] };
        },
        audit: async () => {
          calls.push("audit");
          return { warnings: [] };
        },
        preflight: async () => {
          calls.push("preflight");
          return { pm2Affected: [], scheduledTaskWarnings: [] };
        },
        promptIdeClosure: async () => {
          calls.push("prompt-ide");
        },
        executeMoves: async () => {
          calls.push("execute");
        },
        runDoctorVerify: async () => {
          calls.push("doctor");
          return { issues: [] };
        },
      },
    );

    expect(calls).toEqual(["snapshot", "discovery", "audit", "preflight"]);
    expect(result.executed).toBe(false);
  });

  it("runs full flow and step-6 doctor verification in execute mode", async () => {
    const calls: string[] = [];

    const result = await runConsolidate(
      {
        from: "C:\\Code",
        dryRun: false,
        yes: false,
        stopPm2: true,
        ackScheduledTasks: true,
      },
      {
        snapshot: async () => {
          calls.push("snapshot");
          return { path: "build/consolidate-snapshot.json" };
        },
        discovery: async () => {
          calls.push("discovery");
          return { adopted: [{ id: "random-thing" }] };
        },
        audit: async () => {
          calls.push("audit");
          return { warnings: ["$PROFILE:12"] };
        },
        preflight: async () => {
          calls.push("preflight");
          return { pm2Affected: ["chinvex-gateway"], scheduledTaskWarnings: [] };
        },
        promptIdeClosure: async () => {
          calls.push("prompt-ide");
        },
        executeMoves: async () => {
          calls.push("execute");
          return { rollbackLogPath: "build/consolidate-rollback-20260201.json" };
        },
        runDoctorVerify: async () => {
          calls.push("doctor");
          return { issues: ["Update scheduled task MorningBrief path"] };
        },
      },
    );

    expect(calls).toEqual(["snapshot", "discovery", "audit", "preflight", "prompt-ide", "execute", "doctor"]);
    expect(result.executed).toBe(true);
    expect(result.manualFixes).toEqual(["Update scheduled task MorningBrief path"]);
  });

  it("blocks when scheduled-task warnings exist without acknowledgement", async () => {
    await expect(
      runConsolidate(
        {
          from: "C:\\Code",
          dryRun: false,
          yes: true,
          stopPm2: false,
          ackScheduledTasks: false,
        },
        {
          snapshot: async () => ({ path: "build/snapshot.json" }),
          discovery: async () => ({ adopted: [] }),
          audit: async () => ({ warnings: [] }),
          preflight: async () => ({ pm2Affected: [], scheduledTaskWarnings: ["MorningBrief"] }),
          promptIdeClosure: async () => undefined,
          executeMoves: async () => ({ rollbackLogPath: "build/rollback.json" }),
          runDoctorVerify: async () => ({ issues: [] }),
        },
      ),
    ).rejects.toThrow("Scheduled task references detected. Re-run with --ack-scheduled-tasks to continue.");
  });
});
