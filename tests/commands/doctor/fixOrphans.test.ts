import { describe, expect, it, vi } from "vitest";
import { runDoctorFixOrphans } from "../../../src/commands/doctor/fixOrphans";

describe("runDoctorFixOrphans", () => {
  it("removes only missing-path entries when confirmed", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixOrphans(
      {
        yes: false,
        entries: [
          { id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex" },
          { id: "old-experiment", name: "old-experiment", registryPath: "C:\\Code\\old-experiment" },
        ],
        pathExists: (target) => target.toLowerCase() === "c:\\code\\chinvex",
      },
      { removeRegistryEntry, confirm },
    );

    expect(confirm).toHaveBeenCalledTimes(1);
    expect(removeRegistryEntry).toHaveBeenCalledWith("old-experiment");
    expect(result.removed).toEqual([{ name: "old-experiment", path: "C:\\Code\\old-experiment" }]);
    expect(result.skipped).toEqual([]);
  });

  it("auto-removes missing entries with --yes and does not prompt", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixOrphans(
      {
        yes: true,
        entries: [{ id: "notes", name: "notes", registryPath: "C:\\Code\\notes" }],
        pathExists: () => false,
      },
      { removeRegistryEntry, confirm },
    );

    expect(confirm).not.toHaveBeenCalled();
    expect(removeRegistryEntry).toHaveBeenCalledWith("notes");
    expect(result.removed).toEqual([{ name: "notes", path: "C:\\Code\\notes" }]);
  });

  it("reports skipped entries when user declines removal", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);

    const result = await runDoctorFixOrphans(
      {
        yes: false,
        entries: [{ id: "legacy", name: "legacy", registryPath: "C:\\Code\\legacy" }],
        pathExists: () => false,
      },
      {
        removeRegistryEntry,
        confirm: async () => false,
      },
    );

    expect(removeRegistryEntry).not.toHaveBeenCalled();
    expect(result.removed).toEqual([]);
    expect(result.skipped).toEqual([
      {
        name: "legacy",
        reason: "user declined orphan removal",
      },
    ]);
  });
});
