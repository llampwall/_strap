type CommandName = "consolidate" | "move" | "rename" | "archive" | "doctor" | "adopt";

type ValidateInput = {
  command: CommandName;
  flags: {
    fixPaths?: boolean;
    scan?: boolean;
    forceRegistryFirst?: boolean;
  };
  diskState: {
    hasPathDrift: boolean;
    driftedEntries?: string[];
  };
};

type ValidateOutput = {
  mode: "registry-first" | "disk-discovery";
  warnings: string[];
};

function isDiskDiscoveryCommand(input: ValidateInput): boolean {
  if (input.command === "doctor" && input.flags.fixPaths) {
    return true;
  }
  if (input.command === "adopt" && input.flags.scan) {
    return true;
  }
  return false;
}

export function validateTrustMode(input: ValidateInput): ValidateOutput {
  const diskDiscovery = isDiskDiscoveryCommand(input);

  if (diskDiscovery && input.flags.forceRegistryFirst) {
    throw new Error("Mixed trust mode is not allowed. Use exactly one trust mode per command.");
  }

  const mode = diskDiscovery ? "disk-discovery" : "registry-first";

  if (mode === "registry-first" && input.diskState.hasPathDrift) {
    const drifted = input.diskState.driftedEntries?.join(", ") ?? "one or more registry entries";
    throw new Error(
      `Registry path drift detected for ${drifted}. Run 'strap doctor --fix-paths' before retrying.`,
    );
  }

  return { mode, warnings: [] };
}
