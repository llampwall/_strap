import { describe, expect, it } from "vitest";
import { normalizeRemoteUrl, resolveDoctorPathConflict } from "../../../src/commands/doctor/conflictResolution";

describe("doctor conflict resolution", () => {
  it("normalizes SSH and HTTPS remotes to the same comparison key", () => {
    expect(normalizeRemoteUrl("git@GitHub.com:Team/Repo.git")).toBe("https://github.com/team/repo");
    expect(normalizeRemoteUrl("https://github.com/team/repo")).toBe("https://github.com/team/repo");
  });

  it("proposes remap when exactly one disk repo matches by normalized remote", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "chinvex",
        registryPath: "C:\\Code\\chinvex",
        registryRemote: "git@github.com:team/chinvex.git",
      },
      diskCandidates: [
        {
          path: "P:\\software\\chinvex",
          remote: "https://github.com/team/chinvex",
        },
      ],
      pathExists: false,
    });

    expect(decision).toEqual({
      kind: "remap",
      toPath: "P:\\software\\chinvex",
      reason: "registry path missing; matched by normalized origin remote",
    });
  });

  it("requires manual selection when multiple matches exist", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "streamside",
        registryPath: "C:\\Code\\streamside",
        registryRemote: "https://github.com/team/streamside.git",
      },
      diskCandidates: [
        { path: "P:\\software\\streamside", remote: "git@github.com:team/streamside.git" },
        { path: "D:\\repos\\streamside", remote: "https://github.com/team/streamside" },
      ],
      pathExists: false,
    });

    expect(decision).toEqual({
      kind: "manual-select",
      reason: "multiple disk repos match normalized remote; user selection required",
    });
  });
});
