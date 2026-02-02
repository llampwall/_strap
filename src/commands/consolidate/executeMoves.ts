export type ConsolidateMovePlan = {
  name: string;
  fromPath: string;
  toPath: string;
  scope: "software" | "tool" | "archive";
};

type ExecuteInput = {
  plans: ConsolidateMovePlan[];
};

type ExecuteHandlers = {
  executeMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  updateRegistryPath: (name: string, nextPath: string) => Promise<void>;
  updateChinvexScope: (name: string, nextScope: "software" | "tool" | "archive") => Promise<void>;
  updateManagedExternalRefs: (repoName: string, fromPath: string, toPath: string) => Promise<string[]>;
  collectManualExternalFixes: (repoName: string, fromPath: string, toPath: string) => Promise<string[]>;
};

export async function executeConsolidateMoves(
  input: ExecuteInput,
  handlers: ExecuteHandlers,
): Promise<{ moved: string[]; managedUpdates: string[]; manualFixes: string[] }> {
  const moved: string[] = [];
  const managedUpdates: string[] = [];
  const manualFixes: string[] = [];

  for (const plan of input.plans) {
    await handlers.executeMove(plan.name, plan.fromPath, plan.toPath);
    await handlers.updateRegistryPath(plan.name, plan.toPath);
    await handlers.updateChinvexScope(plan.name, plan.scope);

    managedUpdates.push(...(await handlers.updateManagedExternalRefs(plan.name, plan.fromPath, plan.toPath)));
    manualFixes.push(...(await handlers.collectManualExternalFixes(plan.name, plan.fromPath, plan.toPath)));

    moved.push(plan.name);
  }

  return { moved, managedUpdates, manualFixes };
}
