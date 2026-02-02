type DiskRecord = Record<string, { totalBytes: number; freeBytes: number }>;

type BuildSnapshotManifestInput = {
  nowIso: string;
  registry: { registry_version: number; entries: unknown[] };
  discovered: unknown[];
  externalRefs: {
    pm2: unknown[];
    scheduled_tasks: unknown[];
    shims: unknown[];
    path_entries: unknown[];
    profile_refs: unknown[];
  };
  getDiskInfo: () => Promise<DiskRecord>;
};

function bytesToGb(value: number): number {
  return Math.round((value / 1024 ** 3) * 100) / 100;
}

export async function buildSnapshotManifest(input: BuildSnapshotManifestInput) {
  const disk = await input.getDiskInfo();

  const disk_usage = Object.fromEntries(
    Object.entries(disk).map(([drive, stats]) => [
      drive,
      {
        total_gb: bytesToGb(stats.totalBytes),
        free_gb: bytesToGb(stats.freeBytes),
      },
    ]),
  );

  return {
    timestamp: input.nowIso,
    registry: {
      version: input.registry.registry_version,
      entries: input.registry.entries,
    },
    discovered: input.discovered,
    external_refs: input.externalRefs,
    disk_usage,
  };
}
