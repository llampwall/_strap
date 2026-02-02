type WizardHandlers = {
  snapshot: () => Promise<void>;
  discovery: () => Promise<void>;
  audit: () => Promise<void>;
  preflight: () => Promise<void>;
  execute: () => Promise<void>;
  verify: () => Promise<void>;
};

export async function runConsolidateWizard(
  input: { dryRun: boolean },
  handlers: WizardHandlers,
): Promise<{ executed: boolean; completedSteps: string[]; message: string }> {
  const completedSteps: string[] = [];

  await handlers.snapshot();
  completedSteps.push("snapshot");

  await handlers.discovery();
  completedSteps.push("discovery");

  await handlers.audit();
  completedSteps.push("audit");

  await handlers.preflight();
  completedSteps.push("preflight");

  if (input.dryRun) {
    return {
      executed: false,
      completedSteps,
      message: "Dry run complete. Steps 1-4 executed; no moves or registry changes were made.",
    };
  }

  await handlers.execute();
  completedSteps.push("execute");

  await handlers.verify();
  completedSteps.push("verify");

  return {
    executed: true,
    completedSteps,
    message: "Consolidation complete.",
  };
}
