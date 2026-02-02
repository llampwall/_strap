import { describe, expect, it } from "vitest";
import { validateMigrationWorkflow } from "../../src/e2e/validateMigrationWorkflow";

describe("validateMigrationWorkflow", () => {
  it("validates dry-run then execute workflow with post-move doctor checks", async () => {
    const events: string[] = [];

    const result = await validateMigrationWorkflow(
      {
        source: "C:\\Code",
        destinationRoot: "P:\\software",
      },
      {
        runConsolidate: async (args) => {
          events.push(args.dryRun ? "consolidate:dry-run" : "consolidate:execute");
          if (args.dryRun) {
            return { executed: false, manualFixes: [] };
          }
          return {
            executed: true,
            manualFixes: ["Update $PROFILE alias path", "Update scheduled task MorningBrief"],
          };
        },
        verifySourceEmpty: async () => {
          events.push("verify:source-empty");
          return true;
        },
        verifyRegistryPathsUnderDestination: async () => {
          events.push("verify:registry-destination");
          return true;
        },
        verifyDoctorClean: async () => {
          events.push("verify:doctor");
          return { ok: true, issues: [] };
        },
      },
    );

    expect(events).toEqual([
      "consolidate:dry-run",
      "consolidate:execute",
      "verify:source-empty",
      "verify:registry-destination",
      "verify:doctor",
    ]);
    expect(result.ok).toBe(true);
    expect(result.manualFixes).toEqual([
      "Update $PROFILE alias path",
      "Update scheduled task MorningBrief",
    ]);
  });

  it("fails when post-move doctor still reports blocking issues", async () => {
    await expect(
      validateMigrationWorkflow(
        {
          source: "C:\\Code",
          destinationRoot: "P:\\software",
        },
        {
          runConsolidate: async ({ dryRun }) => ({ executed: !dryRun, manualFixes: [] }),
          verifySourceEmpty: async () => true,
          verifyRegistryPathsUnderDestination: async () => true,
          verifyDoctorClean: async () => ({ ok: false, issues: ["Registry entry missing path for streamside"] }),
        },
      ),
    ).rejects.toThrow("End-to-end validation failed: Registry entry missing path for streamside");
  });
});
