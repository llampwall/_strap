import { resolveDoctorPathConflict } from "./conflictResolution";

type Entry = {
  id: string;
  name: string;
  registryPath: string;
  registryRemote?: string;
};

type DiscoveredRepo = {
  path: string;
  remote?: string;
};

type RunInput = {
  yes: boolean;
  entries: Entry[];
  discovered: DiscoveredRepo[];
  pathExists: (target: string) => boolean;
};

type RunHandlers = {
  updateRegistryPath: (id: string, nextPath: string) => Promise<void>;
  confirm: (message: string) => Promise<boolean>;
};

export async function runDoctorFixPaths(
  input: RunInput,
  handlers: RunHandlers,
): Promise<{ updated: Array<{ name: string; from: string; to: string }>; unresolved: Array<{ name: string; reason: string }> }> {
  const updated: Array<{ name: string; from: string; to: string }> = [];
  const unresolved: Array<{ name: string; reason: string }> = [];

  for (const entry of input.entries) {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: entry.name,
        registryPath: entry.registryPath,
        registryRemote: entry.registryRemote,
      },
      diskCandidates: input.discovered,
      pathExists: input.pathExists(entry.registryPath),
    });

    if (decision.kind === "remap") {
      const shouldApply = input.yes
        ? true
        : await handlers.confirm(`Update registry path for ${entry.name}: ${entry.registryPath} -> ${decision.toPath}?`);

      if (!shouldApply) {
        unresolved.push({ name: entry.name, reason: "user declined registry path update" });
        continue;
      }

      await handlers.updateRegistryPath(entry.id, decision.toPath);
      updated.push({ name: entry.name, from: entry.registryPath, to: decision.toPath });
      continue;
    }

    if (decision.kind === "manual-select" || decision.kind === "orphan" || decision.kind === "fail") {
      unresolved.push({ name: entry.name, reason: decision.reason });
    }
  }

  return { updated, unresolved };
}
