import { describe, expect, it, vi } from "vitest";
import { applyAdoptionPlan, buildAdoptionPlan } from "../../../src/commands/adopt/confirmAndApply";

describe("adopt confirm/apply", () => {
  it("prompts per item when --yes is not provided", async () => {
    const ask = vi.fn(async () => "archive");

    const plan = await buildAdoptionPlan(
      [
        { path: "C:\\Code\\old-repo", kind: "git", suggestedScope: "software", alreadyRegistered: false },
      ],
      { yes: false, allowAutoArchive: false, scopeOverride: undefined },
      ask,
    );

    expect(ask).toHaveBeenCalledTimes(1);
    expect(plan[0].finalScope).toBe("archive");
  });

  it("keeps archive suggestions safe in --yes mode unless --allow-auto-archive is set", async () => {
    const plan = await buildAdoptionPlan(
      [
        { path: "C:\\Code\\very-old", kind: "git", suggestedScope: "archive", alreadyRegistered: false },
      ],
      { yes: true, allowAutoArchive: false, scopeOverride: undefined },
      async () => "archive",
    );

    expect(plan[0].finalScope).toBe("software");
  });

  it("dry-run does not write to registry", async () => {
    const writeEntry = vi.fn(async () => undefined);

    const result = await applyAdoptionPlan(
      [
        { path: "C:\\Code\\toolbox", finalScope: "tool", skip: false },
        { path: "C:\\Code\\readme.txt", finalScope: "tool", skip: true },
      ],
      { dryRun: true },
      writeEntry,
    );

    expect(writeEntry).not.toHaveBeenCalled();
    expect(result.adoptedCount).toBe(1);
    expect(result.dryRun).toBe(true);
  });
});
