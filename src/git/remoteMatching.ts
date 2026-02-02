type GitRemote = {
  name: string;
  url: string;
};

export function normalizeRemoteForMatch(remote?: string): string | undefined {
  if (!remote) {
    return undefined;
  }

  const trimmed = remote.trim();
  if (!trimmed) {
    return undefined;
  }

  const sshMatch = /^git@([^:]+):(.+)$/i.exec(trimmed);
  const asHttps = sshMatch ? `https://${sshMatch[1]}/${sshMatch[2]}` : trimmed;

  const slashNormalized = asHttps.replace(/\\/g, "/");
  const withoutTrailingSlash = slashNormalized.replace(/\/+$/, "");
  const withoutGitSuffix = withoutTrailingSlash.replace(/\.git$/i, "");

  try {
    const parsed = new URL(withoutGitSuffix);
    const host = parsed.host.toLowerCase();
    const pathname = parsed.pathname.replace(/\/+$/, "");
    return `${parsed.protocol}//${host}${pathname}`;
  } catch {
    return withoutGitSuffix;
  }
}

export function pickComparisonRemote(remotes: GitRemote[]): string | undefined {
  if (remotes.length === 0) {
    return undefined;
  }

  const preferred = remotes.find((remote) => remote.name.toLowerCase() === "origin") ?? remotes[0];
  return normalizeRemoteForMatch(preferred.url);
}
