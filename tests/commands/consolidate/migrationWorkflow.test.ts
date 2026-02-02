import { describe, expect, it, vi } from "vitest";
import { runConsolidateMigrationWorkflow } from "../../../src/commands/consolidate/migrationWorkflow";

describe("runConsolidateMigrationWorkflow", () => {
  it("runs config migration + registry upgrade before wizard and finishes with doctor verification", async () => {
    const calls: string[] = [];

    const handlers = {
      migrateConfigIfNeeded: vi.fn(async () => {
        calls.push("config-migrate");
        return { changed: true };
      }),
      readRegistryVersion: vi.fn(async () => {
        calls.push("registry-version");
        return 1;
      }),
      migrateRegistryToV2: vi.fn(async () => {
        calls.push("registry-migrate");
      }),
      runWizardSteps: vi.fn(async () => {
        calls.push("wizard");
      }),
      runDoctor: vi.fn(async () => {
        calls.push("doctor");
        return { ok: true, issues: [] as string[] };
      }),
    };

    const result = await runConsolidateMigrationWorkflow(
      {
        configPath: "P:\\software\\_strap\\config.json",
        registryPath: "P:\\software\\_strap\\build\\registry.json",
        from: "C:\\Code",
        dryRun: false,
      },
      handlers,
    );

    expect(result.registryUpgraded).toBe(true);
    expect(result.doctorIssues).toEqual([]);
    expect(calls).toEqual(["config-migrate", "registry-version", "registry-migrate", "wizard", "doctor"]);
  });

  it("fails fast with upgrade guidance when registry version is newer than supported", async () => {
    await expect(
      runConsolidateMigrationWorkflow(
        {
          configPath: "P:\\software\\_strap\\config.json",
          registryPath: "P:\\software\\_strap\\build\\registry.json",
          from: "C:\\Code",
          dryRun: false,
        },
        {
          migrateConfigIfNeeded: async () => ({ changed: false }),
          readRegistryVersion: async () => 3,
          migrateRegistryToV2: async () => undefined,
          runWizardSteps: async () => undefined,
          runDoctor: async () => ({ ok: true, issues: [] }),
        },
      ),
    ).rejects.toThrow("Registry requires strap version X.Y+, please upgrade");
  });
});
