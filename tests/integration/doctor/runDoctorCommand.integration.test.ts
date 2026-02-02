import { describe, expect, it, vi } from "vitest";
import { runDoctorCommand } from "../../../src/commands/doctor/runDoctorCommand";

describe("runDoctorCommand integration", () => {
  it("reports drift by default without mutating registry", async () => {
    const updatePath = vi.fn(async () => undefined);
    const removeEntry = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: false,
        fixOrphans: false,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [{ id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex", diskPath: "P:\\software\\chinvex" }],
          orphans: [{ id: "old", name: "old", registryPath: "C:\\Code\\old" }],
        }),
        updateRegistryPath: updatePath,
        removeRegistryEntry: removeEntry,
      },
    );

    expect(result.issues).toHaveLength(2);
    expect(updatePath).not.toHaveBeenCalled();
    expect(removeEntry).not.toHaveBeenCalled();
  });

  it("applies --fix-paths updates for remote-matched drifted entries", async () => {
    const updatePath = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: true,
        fixOrphans: false,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [{ id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex", diskPath: "P:\\software\\chinvex" }],
          orphans: [],
        }),
        updateRegistryPath: updatePath,
        removeRegistryEntry: async () => undefined,
      },
    );

    expect(updatePath).toHaveBeenCalledWith("chinvex", "P:\\software\\chinvex");
    expect(result.fixesApplied).toEqual(["path:chinvex"]);
  });

  it("applies --fix-orphans removals for missing registry entries", async () => {
    const removeEntry = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: false,
        fixOrphans: true,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [],
          orphans: [{ id: "old", name: "old", registryPath: "C:\\Code\\old" }],
        }),
        updateRegistryPath: async () => undefined,
        removeRegistryEntry: removeEntry,
      },
    );

    expect(removeEntry).toHaveBeenCalledWith("old");
    expect(result.fixesApplied).toEqual(["orphan:old"]);
  });
});
