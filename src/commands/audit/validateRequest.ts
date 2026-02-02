export type AuditArgs = {
  target?: string;
  all: boolean;
  json: boolean;
  rebuildIndex: boolean;
  trustMode: "registry-first";
};

export function parseAuditArgs(argv: string[]): AuditArgs {
  let target: string | undefined;
  let all = false;
  let json = false;
  let rebuildIndex = false;

  for (const token of argv) {
    if (token === "--all") {
      all = true;
      continue;
    }
    if (token === "--json") {
      json = true;
      continue;
    }
    if (token === "--rebuild-index") {
      rebuildIndex = true;
      continue;
    }
    if (!token.startsWith("-") && !target) {
      target = token;
    }
  }

  return { target, all, json, rebuildIndex, trustMode: "registry-first" };
}

export function validateAuditRequest(args: AuditArgs, registryNames: string[]): { targets: string[]; json: boolean; rebuildIndex: boolean } {
  if (!args.target && !args.all) {
    throw new Error("Provide a target name or --all");
  }

  if (args.target && args.all) {
    throw new Error("Cannot combine a target name with --all");
  }

  if (args.target && !registryNames.includes(args.target)) {
    throw new Error(`Registry entry '${args.target}' not found`);
  }

  return {
    targets: args.all ? [...registryNames] : [args.target as string],
    json: args.json,
    rebuildIndex: args.rebuildIndex,
  };
}
