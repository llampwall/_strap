import { describe, expect, it } from "vitest";
import { parseAuditArgs, validateAuditRequest } from "../../../src/commands/audit/validateRequest";

describe("audit request validation", () => {
  it("parses --all, --json and --rebuild-index flags", () => {
    const parsed = parseAuditArgs(["--all", "--json", "--rebuild-index"]);
    expect(parsed).toEqual({ target: undefined, all: true, json: true, rebuildIndex: true, trustMode: "registry-first" });
  });

  it("fails when neither name nor --all is provided", () => {
    expect(() => validateAuditRequest(parseAuditArgs([]), ["chinvex"]))
      .toThrow("Provide a target name or --all");
  });

  it("fails when both name and --all are provided", () => {
    expect(() => validateAuditRequest(parseAuditArgs(["chinvex", "--all"]), ["chinvex"]))
      .toThrow("Cannot combine a target name with --all");
  });

  it("fails when target is missing from registry", () => {
    expect(() => validateAuditRequest(parseAuditArgs(["unknown"]), ["chinvex"]))
      .toThrow("Registry entry 'unknown' not found");
  });
});
