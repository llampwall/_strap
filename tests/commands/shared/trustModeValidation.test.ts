import { describe, expect, it } from "vitest";
import { validateTrustMode } from "../../../src/commands/shared/trustModeValidation";

describe("validateTrustMode", () => {
  it("defaults registry-first commands to registry-first mode", () => {
    const result = validateTrustMode({
      command: "consolidate",
      flags: {},
      diskState: { hasPathDrift: false },
    });

    expect(result.mode).toBe("registry-first");
    expect(result.warnings).toEqual([]);
  });

  it("fails registry-first commands when disk path drift is detected", () => {
    expect(() =>
      validateTrustMode({
        command: "archive",
        flags: {},
        diskState: { hasPathDrift: true, driftedEntries: ["chinvex"] },
      }),
    ).toThrow("Registry path drift detected for chinvex. Run 'strap doctor --fix-paths' before retrying.");
  });

  it("allows disk-discovery mode only for doctor --fix-paths and adopt --scan", () => {
    const doctor = validateTrustMode({
      command: "doctor",
      flags: { fixPaths: true },
      diskState: { hasPathDrift: true },
    });
    const adopt = validateTrustMode({
      command: "adopt",
      flags: { scan: true },
      diskState: { hasPathDrift: true },
    });

    expect(doctor.mode).toBe("disk-discovery");
    expect(adopt.mode).toBe("disk-discovery");
  });

  it("rejects mixed trust mode flags", () => {
    expect(() =>
      validateTrustMode({
        command: "doctor",
        flags: { fixPaths: true, forceRegistryFirst: true },
        diskState: { hasPathDrift: true },
      }),
    ).toThrow("Mixed trust mode is not allowed. Use exactly one trust mode per command.");
  });
});
