import { describe, expect, it, vi } from "vitest";
import { runConsolidateWizard } from "../../../src/commands/consolidate/dryRun";

describe("runConsolidateWizard dry-run", () => {
  it("executes steps 1-4 and skips execute/verify in dry-run mode", async () => {
    const handlers = {
      snapshot: vi.fn(async () => undefined),
      discovery: vi.fn(async () => undefined),
      audit: vi.fn(async () => undefined),
      preflight: vi.fn(async () => undefined),
      execute: vi.fn(async () => undefined),
      verify: vi.fn(async () => undefined),
    };

    const result = await runConsolidateWizard({ dryRun: true }, handlers);

    expect(handlers.snapshot).toHaveBeenCalledTimes(1);
    expect(handlers.discovery).toHaveBeenCalledTimes(1);
    expect(handlers.audit).toHaveBeenCalledTimes(1);
    expect(handlers.preflight).toHaveBeenCalledTimes(1);
    expect(handlers.execute).not.toHaveBeenCalled();
    expect(handlers.verify).not.toHaveBeenCalled();

    expect(result.executed).toBe(false);
    expect(result.completedSteps).toEqual(["snapshot", "discovery", "audit", "preflight"]);
    expect(result.message).toContain("Dry run complete");
  });
});
