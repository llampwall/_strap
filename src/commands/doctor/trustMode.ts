export type DoctorTrustMode = "registry-first" | "disk-discovery";

type TrustModeInput = {
  fixPaths: boolean;
  fixOrphans: boolean;
  trustMode?: DoctorTrustMode;
};

export function determineDoctorTrustMode(input: TrustModeInput): DoctorTrustMode {
  if (input.fixPaths) {
    if (input.trustMode === "registry-first") {
      throw new Error(
        "doctor trust-mode conflict: --fix-paths requires disk-discovery and cannot be combined with --trust-mode registry-first",
      );
    }
    return "disk-discovery";
  }

  if (input.trustMode === "disk-discovery") {
    throw new Error("doctor disk-discovery mode is only valid with --fix-paths");
  }

  return input.trustMode ?? "registry-first";
}
