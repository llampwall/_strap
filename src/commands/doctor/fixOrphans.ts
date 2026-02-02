type Entry = {
  id: string;
  name: string;
  registryPath: string;
};

type RunInput = {
  yes: boolean;
  entries: Entry[];
  pathExists: (target: string) => boolean;
};

type RunHandlers = {
  removeRegistryEntry: (id: string) => Promise<void>;
  confirm: (message: string) => Promise<boolean>;
};

export async function runDoctorFixOrphans(
  input: RunInput,
  handlers: RunHandlers,
): Promise<{
  removed: Array<{ name: string; path: string }>;
  skipped: Array<{ name: string; reason: string }>;
}> {
  const removed: Array<{ name: string; path: string }> = [];
  const skipped: Array<{ name: string; reason: string }> = [];

  for (const entry of input.entries) {
    if (input.pathExists(entry.registryPath)) {
      continue;
    }

    const shouldRemove = input.yes
      ? true
      : await handlers.confirm(`Remove orphaned registry entry '${entry.name}' (${entry.registryPath})?`);

    if (!shouldRemove) {
      skipped.push({ name: entry.name, reason: "user declined orphan removal" });
      continue;
    }

    await handlers.removeRegistryEntry(entry.id);
    removed.push({ name: entry.name, path: entry.registryPath });
  }

  return { removed, skipped };
}
