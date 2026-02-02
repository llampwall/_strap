import { describe, expect, it, vi } from "vitest";
import { runDoctorFixPaths } from "../../../src/commands/doctor/fixPaths";

describe("runDoctorFixPaths", () => {
  it("updates registry path when exactly one remote match exists and confirmation is granted", async () => {
    const updateRegistryPath = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixPaths(
      {
        yes: false,
        entries: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: "C:\\Code\\chinvex",
            registryRemote: "git@github.com:team/chinvex.git",
          },
        ],
        discovered: [
          {
            path: "P:\\software\\chinvex",
            remote: "https://github.com/team/chinvex",
          },
        ],
        pathExists: (target) => target.toLowerCase() === "p:\\software\\chinvex",
      },
      { updateRegistryPath, confirm },
    );

    expect(confirm).toHaveBeenCalledTimes(1);
    expect(updateRegistryPath).toHaveBeenCalledWith("chinvex", "P:\\software\\chinvex");
    expect(result.updated).toEqual([{ name: "chinvex", from: "C:\\Code\\chinvex", to: "P:\\software\\chinvex" }]);
    expect(result.unresolved).toEqual([]);
  });

  it("reports unresolved when multiple candidates match and does not auto-update in --yes", async () => {
    const updateRegistryPath = vi.fn(async () => undefined);

    const result = await runDoctorFixPaths(
      {
        yes: true,
        entries: [
          {
            id: "streamside",
            name: "streamside",
            registryPath: "C:\\Code\\streamside",
            registryRemote: "https://github.com/team/streamside",
          },
        ],
        discovered: [
          { path: "P:\\software\\streamside", remote: "git@github.com:team/streamside.git" },
          { path: "D:\\repos\\streamside", remote: "https://github.com/team/streamside.git" },
        ],
        pathExists: () => false,
      },
      {
        updateRegistryPath,
        confirm: async () => true,
      },
    );

    expect(updateRegistryPath).not.toHaveBeenCalled();
    expect(result.unresolved).toEqual([
      {
        name: "streamside",
        reason: "multiple disk repos match normalized remote; user selection required",
      },
    ]);
  });
});
