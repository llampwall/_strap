export type SuggestedScope = "tool" | "software" | "archive";

export type DiscoveryItem = {
  path: string;
  kind: "git" | "directory" | "file";
  suggestedScope: SuggestedScope;
  alreadyRegistered: boolean;
};

export type PlannedItem = {
  path: string;
  finalScope: SuggestedScope;
  skip: boolean;
};

export async function buildAdoptionPlan(
  discovered: DiscoveryItem[],
  opts: { yes: boolean; allowAutoArchive: boolean; scopeOverride?: SuggestedScope },
  ask: (item: DiscoveryItem) => Promise<SuggestedScope | "skip">,
): Promise<PlannedItem[]> {
  const plan: PlannedItem[] = [];

  for (const item of discovered) {
    if (item.kind === "file" || item.alreadyRegistered) {
      plan.push({ path: item.path, finalScope: item.suggestedScope, skip: true });
      continue;
    }

    if (opts.scopeOverride) {
      plan.push({ path: item.path, finalScope: opts.scopeOverride, skip: false });
      continue;
    }

    if (opts.yes) {
      const safeScope = item.suggestedScope === "archive" && !opts.allowAutoArchive ? "software" : item.suggestedScope;
      plan.push({ path: item.path, finalScope: safeScope, skip: false });
      continue;
    }

    const answer = await ask(item);
    if (answer === "skip") {
      plan.push({ path: item.path, finalScope: item.suggestedScope, skip: true });
      continue;
    }

    plan.push({ path: item.path, finalScope: answer, skip: false });
  }

  return plan;
}

export async function applyAdoptionPlan(
  plan: PlannedItem[],
  opts: { dryRun: boolean },
  writeEntry: (item: PlannedItem) => Promise<void>,
): Promise<{ adoptedCount: number; dryRun: boolean }> {
  const actionable = plan.filter((item) => !item.skip);

  if (!opts.dryRun) {
    for (const item of actionable) {
      await writeEntry(item);
    }
  }

  return {
    adoptedCount: actionable.length,
    dryRun: opts.dryRun,
  };
}
