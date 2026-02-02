import { describe, expect, it } from "vitest";
import { parseConfig } from "../../src/config/schema";

describe("parseConfig", () => {
  it("accepts config with archive root and archive threshold", () => {
    const parsed = parseConfig({
      roots: {
        software: "P:\\software",
        tools: "P:\\software\\_scripts",
        shims: "P:\\software\\_scripts\\_bin",
        archive: "P:\\software\\_archive",
      },
      registry: "P:\\software\\_strap\\build\\registry.json",
      archive_threshold_days: 180,
    });

    expect(parsed.roots.archive).toBe("P:\\software\\_archive");
    expect(parsed.archive_threshold_days).toBe(180);
  });

  it("rejects missing archive root", () => {
    expect(() =>
      parseConfig({
        roots: {
          software: "P:\\software",
          tools: "P:\\software\\_scripts",
          shims: "P:\\software\\_scripts\\_bin",
        },
        registry: "P:\\software\\_strap\\build\\registry.json",
        archive_threshold_days: 180,
      }),
    ).toThrow("config.roots.archive is required");
  });

  it("rejects non-positive archive threshold", () => {
    expect(() =>
      parseConfig({
        roots: {
          software: "P:\\software",
          tools: "P:\\software\\_scripts",
          shims: "P:\\software\\_scripts\\_bin",
          archive: "P:\\software\\_archive",
        },
        registry: "P:\\software\\_strap\\build\\registry.json",
        archive_threshold_days: 0,
      }),
    ).toThrow("config.archive_threshold_days must be a positive integer");
  });
});
