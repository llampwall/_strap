type MovePlan = {
  name: string;
  fromPath: string;
  toPath: string;
};

type TransactionHandlers = {
  writeRollbackLogStart: () => Promise<void>;
  executeMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  rollbackMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  writeRollbackLogResult: (payload: { completed: string[]; failed?: string }) => Promise<void>;
  writeRegistryBatch: () => Promise<void>;
  updateChinvexBatch: () => Promise<void>;
  restoreRegistryFromBackup?: () => Promise<void>;
};

export async function runConsolidateTransaction(
  input: { plans: MovePlan[] },
  handlers: TransactionHandlers,
): Promise<void> {
  const completed: MovePlan[] = [];

  await handlers.writeRollbackLogStart();

  try {
    for (const plan of input.plans) {
      await handlers.executeMove(plan.name, plan.fromPath, plan.toPath);
      completed.push(plan);
    }
  } catch (error) {
    for (let i = completed.length - 1; i >= 0; i -= 1) {
      const done = completed[i];
      await handlers.rollbackMove(done.name, done.fromPath, done.toPath);
    }

    const failed = error instanceof Error ? error.message : "unknown consolidate failure";
    await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name), failed });
    throw error;
  }

  await handlers.writeRegistryBatch();

  try {
    await handlers.updateChinvexBatch();
  } catch (error) {
    if (handlers.restoreRegistryFromBackup) {
      await handlers.restoreRegistryFromBackup();
    }

    const failed = error instanceof Error ? error.message : "unknown chinvex update failure";
    await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name), failed });
    throw error;
  }

  await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name) });
}
