import { mkdtemp, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { planArchiveMove } from "../../../src/commands/archive/safety";

describe("planArchiveMove", () => {
  it("returns a valid archive move plan for an existing registry entry", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-safety-"));
    const sourcePath = path.join(root, "old-experiment");
    const archiveRoot = path.join(root, "_archive");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(archiveRoot, { recursive: true });

    const plan = await planArchiveMove(
      {
        name: "old-experiment",
        trustMode: "registry-first",
      },
      {
        entries: [
          {
            id: "old-experiment",
            name: "old-experiment",
            scope: "software",
            path: sourcePath,
          },
        ],
      },
      {
        archiveRoot,
      },
    );

    expect(plan).toMatchObject({
      name: "old-experiment",
      fromPath: sourcePath,
      toPath: path.join(archiveRoot, "old-experiment"),
      nextScope: "archive",
    });
  });

  it("fails on registry-disk drift and suggests doctor --fix-paths", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-drift-"));
    const archiveRoot = path.join(root, "_archive");
    await mkdir(archiveRoot, { recursive: true });

    await expect(
      planArchiveMove(
        { name: "old-experiment", trustMode: "registry-first" },
        {
          entries: [
            {
              id: "old-experiment",
              name: "old-experiment",
              scope: "software",
              path: path.join(root, "missing-old-experiment"),
            },
          ],
        },
        { archiveRoot },
      ),
    ).rejects.toThrow("Registry path drift detected for 'old-experiment'. Run 'strap doctor --fix-paths'.");
  });

  it("fails fast when destination path already exists", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-collision-"));
    const sourcePath = path.join(root, "old-experiment");
    const archiveRoot = path.join(root, "_archive");
    const destinationPath = path.join(archiveRoot, "old-experiment");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(destinationPath, { recursive: true });

    await expect(
      planArchiveMove(
        { name: "old-experiment", trustMode: "registry-first" },
        {
          entries: [
            {
              id: "old-experiment",
              name: "old-experiment",
              scope: "software",
              path: sourcePath,
            },
          ],
        },
        { archiveRoot },
      ),
    ).rejects.toThrow("Destination already exists: " + destinationPath);
  });
});
