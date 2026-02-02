type WorkflowInput = {
  source: string;
  destinationRoot: string;
};

type WorkflowHandlers = {
  runConsolidate: (args: {
    from: string;
    to: string;
    dryRun: boolean;
    yes: boolean;
    stopPm2: boolean;
    ackScheduledTasks: boolean;
  }) => Promise<{ executed: boolean; manualFixes: string[] }>;
  verifySourceEmpty: (source: string) => Promise<boolean>;
  verifyRegistryPathsUnderDestination: (destinationRoot: string) => Promise<boolean>;
  verifyDoctorClean: () => Promise<{ ok: boolean; issues: string[] }>;
};

export async function validateMigrationWorkflow(
  input: WorkflowInput,
  handlers: WorkflowHandlers,
): Promise<{ ok: boolean; manualFixes: string[] }> {
  await handlers.runConsolidate({
    from: input.source,
    to: input.destinationRoot,
    dryRun: true,
    yes: true,
    stopPm2: false,
    ackScheduledTasks: true,
  });

  const executed = await handlers.runConsolidate({
    from: input.source,
    to: input.destinationRoot,
    dryRun: false,
    yes: true,
    stopPm2: true,
    ackScheduledTasks: true,
  });

  const sourceEmpty = await handlers.verifySourceEmpty(input.source);
  if (!sourceEmpty) {
    throw new Error(`End-to-end validation failed: source directory not empty (${input.source})`);
  }

  const registryOk = await handlers.verifyRegistryPathsUnderDestination(input.destinationRoot);
  if (!registryOk) {
    throw new Error(`End-to-end validation failed: registry paths not rooted at ${input.destinationRoot}`);
  }

  const doctor = await handlers.verifyDoctorClean();
  if (!doctor.ok) {
    throw new Error(`End-to-end validation failed: ${doctor.issues[0] ?? "unknown doctor issue"}`);
  }

  return {
    ok: true,
    manualFixes: executed.manualFixes,
  };
}
