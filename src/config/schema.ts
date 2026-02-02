export type StrapConfig = {
  roots: {
    software: string;
    tools: string;
    shims: string;
    archive: string;
  };
  registry: string;
  archive_threshold_days: number;
};

function readString(value: unknown, path: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${path} is required`);
  }
  return value;
}

export function parseConfig(raw: unknown): StrapConfig {
  if (!raw || typeof raw !== "object") {
    throw new Error("config must be an object");
  }

  const obj = raw as Record<string, unknown>;
  const roots = (obj.roots ?? {}) as Record<string, unknown>;

  const archiveThreshold = obj.archive_threshold_days;
  if (!Number.isInteger(archiveThreshold) || (archiveThreshold as number) <= 0) {
    throw new Error("config.archive_threshold_days must be a positive integer");
  }

  return {
    roots: {
      software: readString(roots.software, "config.roots.software"),
      tools: readString(roots.tools, "config.roots.tools"),
      shims: readString(roots.shims, "config.roots.shims"),
      archive: readString(roots.archive, "config.roots.archive"),
    },
    registry: readString(obj.registry, "config.registry"),
    archive_threshold_days: archiveThreshold as number,
  };
}
