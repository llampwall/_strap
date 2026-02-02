import { describe, expect, it, vi } from "vitest";
import { executeConsolidateMoves } from "../../../src/commands/consolidate/executeMoves";

describe("executeConsolidateMoves", () => {
  it("moves repos, updates registry/chinvex, updates managed refs, and returns manual fixes", async () => {
    const calls: string[] = [];
    const handlers = {
      executeMove: vi.fn(async (name: string) => {
        calls.push(`move:${name}`);
      }),
      updateRegistryPath: vi.fn(async (name: string, nextPath: string) => {
        calls.push(`registry:${name}:${nextPath}`);
      }),
      updateChinvexScope: vi.fn(async (name: string, nextScope: "software" | "tool" | "archive") => {
        calls.push(`chinvex:${name}:${nextScope}`);
      }),
      updateManagedExternalRefs: vi.fn(async (repoName: string, fromPath: string, toPath: string) => {
        calls.push(`managed:${repoName}`);
        return [
          `Updated shim '${repoName}' to ${toPath}`,
          `Updated PATH entry for ${repoName}`,
        ];
      }),
      collectManualExternalFixes: vi.fn(async (repoName: string, fromPath: string, toPath: string) => {
        calls.push(`manual:${repoName}`);
        return [
          `$PROFILE alias still points to ${fromPath}`,
          `Scheduled task for ${repoName} still points to ${fromPath}`,
        ];
      }),
    };

    const result = await executeConsolidateMoves(
      {
        plans: [
          {
            name: "chinvex",
            fromPath: "C:\\Code\\chinvex",
            toPath: "P:\\software\\chinvex",
            scope: "software",
          },
          {
            name: "misc-scripts",
            fromPath: "C:\\Code\\misc-scripts",
            toPath: "P:\\software\\_scripts\\misc-scripts",
            scope: "tool",
          },
        ],
      },
      handlers,
    );

    expect(result.moved).toEqual(["chinvex", "misc-scripts"]);
    expect(result.managedUpdates).toEqual([
      "Updated shim 'chinvex' to P:\\software\\chinvex",
      "Updated PATH entry for chinvex",
      "Updated shim 'misc-scripts' to P:\\software\\_scripts\\misc-scripts",
      "Updated PATH entry for misc-scripts",
    ]);
    expect(result.manualFixes).toEqual([
      "$PROFILE alias still points to C:\\Code\\chinvex",
      "Scheduled task for chinvex still points to C:\\Code\\chinvex",
      "$PROFILE alias still points to C:\\Code\\misc-scripts",
      "Scheduled task for misc-scripts still points to C:\\Code\\misc-scripts",
    ]);

    expect(calls).toEqual([
      "move:chinvex",
      "registry:chinvex:P:\\software\\chinvex",
      "chinvex:chinvex:software",
      "managed:chinvex",
      "manual:chinvex",
      "move:misc-scripts",
      "registry:misc-scripts:P:\\software\\_scripts\\misc-scripts",
      "chinvex:misc-scripts:tool",
      "managed:misc-scripts",
      "manual:misc-scripts",
    ]);
  });
});
