import { mkdtemp, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { validateConsolidateRegistryDisk } from "../../../src/commands/consolidate/registryDiskValidation";

describe("validateConsolidateRegistryDisk", () => {
  it("fails on registry-first drift when registry path is missing", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-drift-"));

    await expect(
      validateConsolidateRegistryDisk({
        trustMode: "registry-first",
        registeredMoves: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: path.join(root, "missing-chinvex"),
            destinationPath: path.join(root, "dest", "chinvex"),
          },
        ],
        discoveredCandidates: [],
      }),
    ).rejects.toThrow("Registry path drift detected for 'chinvex'. Run 'strap doctor --fix-paths'.");
  });

  it("fails fast when destination already exists for a registered move", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-target-exists-"));
    const sourcePath = path.join(root, "source", "chinvex");
    const destinationPath = path.join(root, "dest", "chinvex");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(destinationPath, { recursive: true });

    await expect(
      validateConsolidateRegistryDisk({
        trustMode: "registry-first",
        registeredMoves: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: sourcePath,
            destinationPath,
          },
        ],
        discoveredCandidates: [],
      }),
    ).rejects.toThrow("Conflict: destination already exists for 'chinvex': " + destinationPath + ". Resolve manually before consolidate.");
  });

  it("warns when discovered repo name collides with registry name at different path", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-name-collision-"));
    const registeredPath = path.join(root, "registered", "streamside");

    await mkdir(registeredPath, { recursive: true });

    const result = await validateConsolidateRegistryDisk({
      trustMode: "registry-first",
      registeredMoves: [
        {
          id: "streamside",
          name: "streamside",
          registryPath: registeredPath,
          destinationPath: path.join(root, "dest", "streamside"),
        },
      ],
      discoveredCandidates: [
        {
          name: "streamside",
          sourcePath: path.join(root, "new-source", "streamside"),
        },
      ],
    });

    expect(result.warnings).toEqual([
      "Name collision: discovered repo 'streamside' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion.",
    ]);
  });
});
