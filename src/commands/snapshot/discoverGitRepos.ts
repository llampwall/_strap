import { stat } from "node:fs/promises";
import path from "node:path";

type DiscoverOptions = {
  registryByPath: Map<string, string>;
  execGit: (repoPath: string, args: string[]) => Promise<string>;
};

export type DiscoveredGitRepo = {
  path: string;
  name: string;
  type: "git";
  in_registry: boolean;
  remote_url: string | null;
  last_commit: string | null;
};

function normalizeRemote(url: string): string {
  const sshMatch = url.trim().match(/^git@([^:]+):(.+)$/);
  let normalized = sshMatch ? `https://${sshMatch[1]}/${sshMatch[2]}` : url.trim();
  normalized = normalized.replace(/\.git$/i, "");
  const parsed = new URL(normalized);
  parsed.hostname = parsed.hostname.toLowerCase();
  parsed.pathname = parsed.pathname.replace(/\\/g, "/").toLowerCase();
  return parsed.toString().replace(/\/$/, "");
}

export async function discoverGitRepos(paths: string[], options: DiscoverOptions): Promise<DiscoveredGitRepo[]> {
  const output: DiscoveredGitRepo[] = [];

  for (const candidate of paths) {
    const gitDir = path.join(candidate, ".git");
    const gitStat = await stat(gitDir).catch(() => null);
    if (!gitStat?.isDirectory()) continue;

    const remoteRaw = await options.execGit(candidate, ["remote", "get-url", "origin"]).catch(() => "");
    const lastCommit = await options.execGit(candidate, ["log", "-1", "--format=%cI"]).catch(() => "");

    output.push({
      path: candidate,
      name: path.basename(candidate),
      type: "git",
      in_registry: options.registryByPath.has(candidate.toLowerCase()),
      remote_url: remoteRaw ? normalizeRemote(remoteRaw) : null,
      last_commit: lastCommit || null,
    });
  }

  return output.sort((a, b) => a.path.localeCompare(b.path));
}
