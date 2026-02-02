type Entry = {
  name: string;
  registryPath: string;
  registryRemote?: string;
};

type DiskCandidate = {
  path: string;
  remote?: string;
};

type ConflictInput = {
  entry: Entry;
  diskCandidates: DiskCandidate[];
  pathExists: boolean;
};

type Decision =
  | { kind: "remap"; toPath: string; reason: string }
  | { kind: "manual-select"; reason: string }
  | { kind: "orphan"; reason: string }
  | { kind: "fail"; reason: string };

export function normalizeRemoteUrl(url: string): string {
  // Handle SSH format: git@github.com:user/repo.git
  if (url.startsWith("git@")) {
    const match = url.match(/git@([^:]+):(.+?)(\.git)?$/);
    if (match) {
      const [, host, path] = match;
      return `https://${host.toLowerCase()}/${path.toLowerCase().replace(/\.git$/, "")}`;
    }
  }

  // Handle HTTPS format: https://github.com/user/repo or https://github.com/user/repo.git
  const httpsMatch = url.match(/^https?:\/\/([^\/]+)\/(.+?)(\.git)?$/);
  if (httpsMatch) {
    const [, host, path] = httpsMatch;
    return `https://${host.toLowerCase()}/${path.toLowerCase().replace(/\.git$/, "")}`;
  }

  return url.toLowerCase();
}

export function resolveDoctorPathConflict(input: ConflictInput): Decision {
  if (!input.pathExists && input.entry.registryRemote) {
    const normalizedRegistryRemote = normalizeRemoteUrl(input.entry.registryRemote);

    const matches = input.diskCandidates.filter((candidate) => {
      if (!candidate.remote) return false;
      return normalizeRemoteUrl(candidate.remote) === normalizedRegistryRemote;
    });

    if (matches.length === 1) {
      return {
        kind: "remap",
        toPath: matches[0].path,
        reason: "registry path missing; matched by normalized origin remote",
      };
    }

    if (matches.length > 1) {
      return {
        kind: "manual-select",
        reason: "multiple disk repos match normalized remote; user selection required",
      };
    }
  }

  return {
    kind: "fail",
    reason: "no matching disk repos found",
  };
}
