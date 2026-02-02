import { describe, expect, it, vi } from "vitest";
import { runEdgeCaseGuards } from "../../../src/commands/consolidate/edgeCaseGuards";

describe("runEdgeCaseGuards", () => {
  it("fails fast on adoption ID collisions in --yes mode", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: true,
          proposedAdoptions: [
            { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
            { sourcePath: "C:\\Code\\repo", proposedId: "repo" },
          ],
          destinationPaths: [],
          existingLock: null,
        },
        {
          isPidRunning: async () => false,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Adoption ID collision detected for 'repo' in --yes mode.");
  });

  it("fails on case-insensitive destination collisions", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: false,
          proposedAdoptions: [],
          destinationPaths: ["P:\\software\\Repo", "P:\\software\\repo"],
          existingLock: null,
        },
        {
          isPidRunning: async () => false,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Destination path collision detected: P:\\software\\Repo <-> P:\\software\\repo");
  });

  it("fails when lock file belongs to a running process", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: false,
          proposedAdoptions: [],
          destinationPaths: [],
          existingLock: { pid: 4242, path: "build/.consolidate.lock" },
        },
        {
          isPidRunning: async () => true,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Another consolidation in progress (PID 4242)");
  });

  it("removes stale lock and resolves collision interactively", async () => {
    const removeStaleLock = vi.fn(async () => undefined);

    const result = await runEdgeCaseGuards(
      {
        yes: false,
        proposedAdoptions: [
          { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
          { sourcePath: "C:\\Code\\repo", proposedId: "repo" },
        ],
        destinationPaths: [],
        existingLock: { pid: 7777, path: "build/.consolidate.lock" },
      },
      {
        isPidRunning: async () => false,
        removeStaleLock,
        resolveCollisionInteractively: async () => "repo-2",
      },
    );

    expect(removeStaleLock).toHaveBeenCalledWith("build/.consolidate.lock");
    expect(result.resolvedAdoptions).toEqual([
      { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
      { sourcePath: "C:\\Code\\repo", proposedId: "repo-2" },
    ]);
  });
});
