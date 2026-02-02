type ProposedAdoption = {
  sourcePath: string;
  proposedId: string;
};

type ExistingLock = {
  pid: number;
  path: string;
};

type EdgeGuardInput = {
  yes: boolean;
  proposedAdoptions: ProposedAdoption[];
  destinationPaths: string[];
  existingLock: ExistingLock | null;
};

type EdgeGuardHandlers = {
  isPidRunning: (pid: number) => Promise<boolean>;
  removeStaleLock: (lockPath: string) => Promise<void>;
  resolveCollisionInteractively: (collidingId: string, sourcePath: string) => Promise<string>;
};

function findDestinationCollision(paths: string[]): string | undefined {
  const seen = new Map<string, string>();
  for (const path of paths) {
    const key = path.toLowerCase();
    const existing = seen.get(key);
    if (existing && existing !== path) {
      return `${existing} <-> ${path}`;
    }
    seen.set(key, path);
  }
  return undefined;
}

export async function runEdgeCaseGuards(
  input: EdgeGuardInput,
  handlers: EdgeGuardHandlers,
): Promise<{ resolvedAdoptions: ProposedAdoption[] }> {
  if (input.existingLock) {
    const running = await handlers.isPidRunning(input.existingLock.pid);
    if (running) {
      throw new Error(`Another consolidation in progress (PID ${input.existingLock.pid})`);
    }
    await handlers.removeStaleLock(input.existingLock.path);
  }

  const collision = findDestinationCollision(input.destinationPaths);
  if (collision) {
    throw new Error(`Destination path collision detected: ${collision}`);
  }

  const seenIds = new Set<string>();
  const resolved: ProposedAdoption[] = [];

  for (const item of input.proposedAdoptions) {
    const key = item.proposedId.toLowerCase();
    if (!seenIds.has(key)) {
      seenIds.add(key);
      resolved.push(item);
      continue;
    }

    if (input.yes) {
      throw new Error(`Adoption ID collision detected for '${item.proposedId}' in --yes mode.`);
    }

    const nextId = await handlers.resolveCollisionInteractively(item.proposedId, item.sourcePath);
    seenIds.add(nextId.toLowerCase());
    resolved.push({ ...item, proposedId: nextId });
  }

  return { resolvedAdoptions: resolved };
}
