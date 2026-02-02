import { describe, expect, it, vi } from "vitest";
import { runArchiveCommand } from "../../../src/commands/archive/dryRun";

describe("runArchiveCommand dry-run", () => {
  it("prints equivalent move and registry update plan without mutating state", async () => {
    const executeMove = vi.fn(async () => undefined);
    const updateRegistry = vi.fn(async () => undefined);
    const updateChinvex = vi.fn(async () => undefined);

    const result = await runArchiveCommand(
      {
        plan: {
          name: "old-experiment",
          fromPath: "C:\\Code\\old-experiment",
          toPath: "P:\\software\\_archive\\old-experiment",
          nextScope: "archive",
        },
        dryRun: true,
        yes: true,
      },
      { executeMove, updateRegistry, updateChinvex },
    );

    expect(executeMove).not.toHaveBeenCalled();
    expect(updateRegistry).not.toHaveBeenCalled();
    expect(updateChinvex).not.toHaveBeenCalled();
    expect(result.executed).toBe(false);
    expect(result.preview).toContain("strap move old-experiment --dest P:\\software\\_archive\\ --yes");
    expect(result.preview).toContain("registry scope: software -> archive");
  });
});
