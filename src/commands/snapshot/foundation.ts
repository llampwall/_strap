import { readdir } from "node:fs/promises";
import path from "node:path";

export type SnapshotTrustMode = "disk-discovery";

export type SnapshotArgs = {
  outputPath: string;
  scanDirs: string[];
  trustMode: SnapshotTrustMode;
};

export type ScannedEntry = {
  path: string;
  type: "directory" | "file";
};

const DEFAULT_SCAN_DIRS = ["C:\\Code", "P:\\software", "C:\\Users\\Jordan\\Documents\\Code"];

export function parseSnapshotArgs(argv: string[]): SnapshotArgs {
  let output = "build/snapshot.json";
  const scans: string[] = [];

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--output" && argv[i + 1]) {
      output = argv[i + 1];
      i += 1;
      continue;
    }
    if (argv[i] === "--scan" && argv[i + 1]) {
      scans.push(argv[i + 1]);
      i += 1;
    }
  }

  const scanDirs = (scans.length > 0 ? scans : DEFAULT_SCAN_DIRS).map((dir) => path.resolve(dir));

  return {
    outputPath: path.resolve(output),
    scanDirs,
    trustMode: "disk-discovery",
  };
}

export async function scanDirectoriesTopLevel(scanDirs: string[]): Promise<ScannedEntry[]> {
  const found: ScannedEntry[] = [];

  for (const dir of scanDirs) {
    const children = await readdir(dir, { withFileTypes: true });
    for (const child of children) {
      found.push({
        path: path.join(dir, child.name),
        type: child.isDirectory() ? "directory" : "file",
      });
    }
  }

  return found.sort((a, b) => a.path.localeCompare(b.path));
}
