type ConsolidateInput = {
  from: string;
  dryRun: boolean;
  yes: boolean;
  stopPm2: boolean;
  ackScheduledTasks: boolean;
};

type ConsolidateHandlers = {
  snapshot: (input: { from: string }) => Promise<{ path: string }>;
  discovery: (input: { from: string; yes: boolean }) => Promise<{ adopted: Array<{ id: string }> }>;
  audit: (input: { from: string }) => Promise<{ warnings: string[] }>;
  preflight: (input: { from: string; stopPm2: boolean }) => Promise<{
    pm2Affected: string[];
    scheduledTaskWarnings: string[];
  }>;
  promptIdeClosure: () => Promise<void>;
  executeMoves: (input: { from: string; stopPm2: boolean }) => Promise<{ rollbackLogPath: string }>;
  runDoctorVerify: () => Promise<{ issues: string[] }>;
};

export async function runConsolidate(
  input: ConsolidateInput,
  handlers: ConsolidateHandlers,
): Promise<{ executed: boolean; manualFixes: string[] }> {
  await handlers.snapshot({ from: input.from });
  await handlers.discovery({ from: input.from, yes: input.yes });
  await handlers.audit({ from: input.from });

  const preflight = await handlers.preflight({ from: input.from, stopPm2: input.stopPm2 });
  if (preflight.scheduledTaskWarnings.length > 0 && !input.ackScheduledTasks) {
    throw new Error("Scheduled task references detected. Re-run with --ack-scheduled-tasks to continue.");
  }

  if (input.dryRun) {
    return { executed: false, manualFixes: [] };
  }

  if (!input.yes) {
    await handlers.promptIdeClosure();
  }

  await handlers.executeMoves({ from: input.from, stopPm2: input.stopPm2 });
  const doctor = await handlers.runDoctorVerify();

  return {
    executed: true,
    manualFixes: doctor.issues,
  };
}
