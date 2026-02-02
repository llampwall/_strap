export type ArchiveExecutionPlan = {
  name: string;
  fromPath: string;
  toPath: string;
  nextScope: "archive";
};

type RunArchiveInput = {
  plan: ArchiveExecutionPlan;
  dryRun: boolean;
  yes: boolean;
};

type ArchiveHandlers = {
  executeMove: (fromPath: string, toPath: string) => Promise<void>;
  updateRegistry: (name: string, nextScope: "archive", nextPath: string) => Promise<void>;
  updateChinvex: (name: string, nextScope: "archive") => Promise<void>;
};

export async function runArchiveCommand(input: RunArchiveInput, handlers: ArchiveHandlers): Promise<{ executed: boolean; preview: string }> {
  const preview = [
    `strap move ${input.plan.name} --dest P:\\software\\_archive\\ --yes`,
    `move: ${input.plan.fromPath} -> ${input.plan.toPath}`,
    "registry scope: software -> archive",
  ].join("\n");

  if (input.dryRun) {
    return { executed: false, preview };
  }

  await handlers.executeMove(input.plan.fromPath, input.plan.toPath);
  await handlers.updateRegistry(input.plan.name, input.plan.nextScope, input.plan.toPath);
  await handlers.updateChinvex(input.plan.name, input.plan.nextScope);

  return { executed: true, preview };
}
