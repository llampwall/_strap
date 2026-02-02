import { readdir, stat } from "node:fs/promises";
import path from "node:path";

export type Candidate = {
  path: string;
  kind: "git" | "directory" | "file";
};

const SKIP_DIRS = new Set([".git", "node_modules", "venv"]);

async function classify(fullPath: string): Promise<Candidate["kind"]> {
  const info = await stat(fullPath);
  if (info.isFile()) return "file";

  const gitDir = path.join(fullPath, ".git");
  try {
    const gitInfo = await stat(gitDir);
    if (gitInfo.isDirectory()) {
      return "git";
    }
  } catch {
    // no-op
  }

  return "directory";
}

export async function scanAdoptCandidates(root: string, recursive: boolean): Promise<Candidate[]> {
  const output: Candidate[] = [];

  async function walk(dir: string, depth: number): Promise<void> {
    const dirents = await readdir(dir, { withFileTypes: true });

    for (const d of dirents) {
      if (d.isDirectory() && SKIP_DIRS.has(d.name)) {
        continue;
      }

      const full = path.join(dir, d.name);
      const kind = await classify(full);
      output.push({ path: full, kind });

      if (recursive && kind === "directory") {
        await walk(full, depth + 1);
      }

      if (!recursive && depth === 0) {
        continue;
      }
    }
  }

  await walk(path.resolve(root), 0);
  return output.sort((a, b) => a.path.localeCompare(b.path));
}
