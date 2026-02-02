export type ConsolidateArgs = {
  from?: string;
  to?: string;
  dryRun: boolean;
  yes: boolean;
  stopPm2: boolean;
  ackScheduledTasks: boolean;
  allowDirty: boolean;
  allowAutoArchive: boolean;
  trustMode: "registry-first" | "disk-discovery";
};

export function parseConsolidateArgs(argv: string[]): ConsolidateArgs {
  const args: ConsolidateArgs = {
    dryRun: false,
    yes: false,
    stopPm2: false,
    ackScheduledTasks: false,
    allowDirty: false,
    allowAutoArchive: false,
    trustMode: "registry-first",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];

    if (token === "--from" && argv[i + 1]) {
      args.from = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === "--to" && argv[i + 1]) {
      args.to = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === "--trust-mode" && argv[i + 1]) {
      args.trustMode = argv[i + 1] as ConsolidateArgs["trustMode"];
      i += 1;
      continue;
    }

    if (token === "--dry-run") args.dryRun = true;
    if (token === "--yes") args.yes = true;
    if (token === "--stop-pm2") args.stopPm2 = true;
    if (token === "--ack-scheduled-tasks") args.ackScheduledTasks = true;
    if (token === "--allow-dirty") args.allowDirty = true;
    if (token === "--allow-auto-archive") args.allowAutoArchive = true;
  }

  return args;
}

export function validateConsolidateArgs(args: ConsolidateArgs): ConsolidateArgs {
  if (!args.from) {
    throw new Error("--from is required");
  }

  if (args.trustMode !== "registry-first") {
    throw new Error("strap consolidate is registry-first; run 'strap doctor --fix-paths' first for disk-discovery recovery");
  }

  return args;
}
