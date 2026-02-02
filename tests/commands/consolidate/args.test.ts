import { describe, expect, it } from "vitest";
import { parseConsolidateArgs, validateConsolidateArgs } from "../../../src/commands/consolidate/args";

describe("consolidate args", () => {
  it("parses required and optional flags with registry-first trust mode", () => {
    const parsed = parseConsolidateArgs([
      "--from",
      "C:\\Code",
      "--to",
      "P:\\software",
      "--dry-run",
      "--yes",
      "--stop-pm2",
      "--ack-scheduled-tasks",
      "--allow-dirty",
      "--allow-auto-archive",
    ]);

    expect(parsed).toMatchObject({
      from: "C:\\Code",
      to: "P:\\software",
      dryRun: true,
      yes: true,
      stopPm2: true,
      ackScheduledTasks: true,
      allowDirty: true,
      allowAutoArchive: true,
      trustMode: "registry-first",
    });
  });

  it("fails when --from is missing", () => {
    expect(() => validateConsolidateArgs(parseConsolidateArgs(["--dry-run"]))).toThrow(
      "--from is required",
    );
  });

  it("fails when disk-discovery trust mode is requested", () => {
    expect(() =>
      validateConsolidateArgs(parseConsolidateArgs(["--from", "C:\\Code", "--trust-mode", "disk-discovery"])),
    ).toThrow("strap consolidate is registry-first; run 'strap doctor --fix-paths' first for disk-discovery recovery");
  });
});
