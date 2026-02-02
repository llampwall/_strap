type WorkflowInput = {
  configPath: string;
  registryPath: string;
  from: string;
  dryRun: boolean;
};

type WorkflowHandlers = {
  migrateConfigIfNeeded: (configPath: string) => Promise<{ changed: boolean }>;
  readRegistryVersion: (registryPath: string) => Promise<number>;
  migrateRegistryToV2: (registryPath: string, nowIso: string) => Promise<void>;
  runWizardSteps: (input: { from: string; dryRun: boolean }) => Promise<void>;
  runDoctor: (input: { fixPaths: boolean; fixOrphans: boolean }) => Promise<{ ok: boolean; issues: string[] }>;
};

export async function runConsolidateMigrationWorkflow(
  input: WorkflowInput,
  handlers: WorkflowHandlers,
): Promise<{ registryUpgraded: boolean; doctorIssues: string[] }> {
  await handlers.migrateConfigIfNeeded(input.configPath);

  const version = await handlers.readRegistryVersion(input.registryPath);
  let registryUpgraded = false;

  if (version > 2) {
    throw new Error("Registry requires strap version X.Y+, please upgrade");
  }

  if (version === 1) {
    await handlers.migrateRegistryToV2(input.registryPath, new Date().toISOString());
    registryUpgraded = true;
  }

  await handlers.runWizardSteps({ from: input.from, dryRun: input.dryRun });

  if (input.dryRun) {
    return { registryUpgraded, doctorIssues: [] };
  }

  const doctor = await handlers.runDoctor({ fixPaths: false, fixOrphans: false });
  return { registryUpgraded, doctorIssues: doctor.issues };
}
