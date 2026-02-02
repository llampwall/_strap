type DriftedEntry = {
  id: string;
  name: string;
  registryPath: string;
  diskPath: string;
};

type OrphanEntry = {
  id: string;
  name: string;
  registryPath: string;
};

type DoctorInput = {
  fixPaths: boolean;
  fixOrphans: boolean;
};

type DoctorHandlers = {
  scanRegistryVsDisk: () => Promise<{
    drifted: DriftedEntry[];
    orphans: OrphanEntry[];
  }>;
  updateRegistryPath: (id: string, nextPath: string) => Promise<void>;
  removeRegistryEntry: (id: string) => Promise<void>;
};

export async function runDoctorCommand(
  input: DoctorInput,
  handlers: DoctorHandlers,
): Promise<{ issues: string[]; fixesApplied: string[] }> {
  const fixesApplied: string[] = [];
  const issues: string[] = [];

  const findings = await handlers.scanRegistryVsDisk();

  for (const drift of findings.drifted) {
    issues.push(`Path drift: ${drift.name} registry=${drift.registryPath} disk=${drift.diskPath}`);
    if (input.fixPaths) {
      await handlers.updateRegistryPath(drift.id, drift.diskPath);
      fixesApplied.push(`path:${drift.id}`);
    }
  }

  for (const orphan of findings.orphans) {
    issues.push(`Orphaned entry: ${orphan.name} at ${orphan.registryPath}`);
    if (input.fixOrphans) {
      await handlers.removeRegistryEntry(orphan.id);
      fixesApplied.push(`orphan:${orphan.id}`);
    }
  }

  return { issues, fixesApplied };
}
