import { readFile, writeFile } from "node:fs/promises";

export type AuditIndex = {
  built_at: string;
  registry_updated_at: string;
  repo_count: number;
  repos: Record<string, { references: string[] }>;
};

type LoadOrBuildInput = {
  indexPath: string;
  rebuildIndex: boolean;
  registryUpdatedAt: string;
  repoPaths: string[];
  scanRepo: (repoPath: string) => Promise<{ references: string[] }>;
};

function nowIso(): string {
  return new Date().toISOString();
}

async function tryReadIndex(indexPath: string): Promise<AuditIndex | null> {
  try {
    return JSON.parse(await readFile(indexPath, "utf8")) as AuditIndex;
  } catch {
    return null;
  }
}

function isFresh(index: AuditIndex, registryUpdatedAt: string, repoPaths: string[]): boolean {
  return index.registry_updated_at === registryUpdatedAt && index.repo_count === repoPaths.length;
}

export async function loadOrBuildAuditIndex(input: LoadOrBuildInput): Promise<AuditIndex> {
  const existing = await tryReadIndex(input.indexPath);

  if (existing && !input.rebuildIndex && isFresh(existing, input.registryUpdatedAt, input.repoPaths)) {
    return existing;
  }

  const repos: AuditIndex["repos"] = {};
  for (const repoPath of input.repoPaths) {
    repos[repoPath] = await input.scanRepo(repoPath);
  }

  const built: AuditIndex = {
    built_at: nowIso(),
    registry_updated_at: input.registryUpdatedAt,
    repo_count: input.repoPaths.length,
    repos,
  };

  await writeFile(input.indexPath, JSON.stringify(built, null, 2), "utf8");
  return built;
}
