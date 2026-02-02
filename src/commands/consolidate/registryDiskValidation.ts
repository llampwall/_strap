import { access } from "node:fs/promises";

type RegisteredMove = {
  id: string;
  name: string;
  registryPath: string;
  destinationPath: string;
};

type DiscoveredCandidate = {
  name: string;
  sourcePath: string;
};

type ValidateInput = {
  trustMode: "registry-first";
  registeredMoves: RegisteredMove[];
  discoveredCandidates: DiscoveredCandidate[];
};

async function exists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

function normalize(p: string): string {
  return p.replaceAll("/", "\\").replace(/\\+$/, "").toLowerCase();
}

export async function validateConsolidateRegistryDisk(input: ValidateInput): Promise<{ warnings: string[] }> {
  const warnings: string[] = [];

  for (const move of input.registeredMoves) {
    if (!(await exists(move.registryPath))) {
      throw new Error(`Registry path drift detected for '${move.name}'. Run 'strap doctor --fix-paths'.`);
    }

    if (await exists(move.destinationPath)) {
      throw new Error(
        `Conflict: destination already exists for '${move.name}': ${move.destinationPath}. Resolve manually before consolidate.`,
      );
    }
  }

  for (const candidate of input.discoveredCandidates) {
    const matching = input.registeredMoves.find((move) => move.name.toLowerCase() === candidate.name.toLowerCase());
    if (!matching) {
      continue;
    }

    if (normalize(matching.registryPath) !== normalize(candidate.sourcePath)) {
      warnings.push(
        `Name collision: discovered repo '${candidate.name}' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion.`,
      );
    }
  }

  return { warnings };
}
