import { describe, expect, it } from "vitest";
import { determineDoctorTrustMode } from "../../../src/commands/doctor/trustMode";

describe("determineDoctorTrustMode", () => {
  it("uses registry-first by default", () => {
    expect(determineDoctorTrustMode({ fixPaths: false, fixOrphans: false, trustMode: undefined })).toBe("registry-first");
  });

  it("switches to disk-discovery for --fix-paths", () => {
    expect(determineDoctorTrustMode({ fixPaths: true, fixOrphans: false, trustMode: undefined })).toBe("disk-discovery");
  });

  it("rejects mixed trust-mode flags", () => {
    expect(() =>
      determineDoctorTrustMode({ fixPaths: true, fixOrphans: false, trustMode: "registry-first" }),
    ).toThrow("doctor trust-mode conflict: --fix-paths requires disk-discovery and cannot be combined with --trust-mode registry-first");
  });

  it("rejects disk-discovery for non-recovery execution", () => {
    expect(() =>
      determineDoctorTrustMode({ fixPaths: false, fixOrphans: false, trustMode: "disk-discovery" }),
    ).toThrow("doctor disk-discovery mode is only valid with --fix-paths");
  });
});
