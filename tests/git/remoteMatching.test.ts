import { describe, expect, it } from "vitest";
import { normalizeRemoteForMatch, pickComparisonRemote } from "../../src/git/remoteMatching";

describe("remote matching normalization", () => {
  it("normalizes ssh and https remotes into the same comparison URL", () => {
    expect(normalizeRemoteForMatch("git@GitHub.com:Team/Repo.git")).toBe("https://github.com/Team/Repo");
    expect(normalizeRemoteForMatch("https://github.com/Team/Repo")).toBe("https://github.com/Team/Repo");
  });

  it("strips trailing .git and normalizes repo path separators", () => {
    expect(normalizeRemoteForMatch("https://github.com/team\\repo.git")).toBe("https://github.com/team/repo");
    expect(normalizeRemoteForMatch("https://github.com/team/repo.git/")).toBe("https://github.com/team/repo");
  });

  it("prefers origin remote and falls back to first remote when origin is absent", () => {
    expect(
      pickComparisonRemote([
        { name: "upstream", url: "https://github.com/acme/strap.git" },
        { name: "origin", url: "git@github.com:acme/strap.git" },
      ]),
    ).toBe("https://github.com/acme/strap");

    expect(
      pickComparisonRemote([
        { name: "upstream", url: "https://github.com/acme/strap.git" },
        { name: "backup", url: "https://github.com/acme/strap" },
      ]),
    ).toBe("https://github.com/acme/strap");
  });

  it("returns undefined when no usable remotes exist", () => {
    expect(pickComparisonRemote([])).toBeUndefined();
    expect(pickComparisonRemote([{ name: "origin", url: "   " }])).toBeUndefined();
  });
});
