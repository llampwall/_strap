import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

type DetectExternalRefsOptions = {
  repoPaths: string[];
  shimDir: string;
  runPm2Jlist: () => Promise<string>;
  runScheduledTasksCsv: () => Promise<string>;
};

type ExternalRefs = {
  pm2: Array<{ name: string; cwd: string }>;
  scheduled_tasks: Array<{ name: string; path: string }>;
  shims: Array<{ name: string; target: string }>;
};

function norm(input: string): string {
  return input.replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase();
}

function matchesRepoPath(candidate: string, repos: string[]): boolean {
  const c = norm(candidate);
  return repos.some((repo) => c.startsWith(norm(repo)));
}

export async function detectExternalRefs(options: DetectExternalRefsOptions): Promise<ExternalRefs> {
  const pm2Raw = await options.runPm2Jlist().catch(() => "[]");
  const pm2Data = JSON.parse(pm2Raw) as Array<{ name?: string; pm2_env?: { pm_cwd?: string } }>;
  const pm2 = pm2Data
    .map((p) => ({ name: p.name ?? "", cwd: p.pm2_env?.pm_cwd ?? "" }))
    .filter((p) => p.name && p.cwd && matchesRepoPath(p.cwd, options.repoPaths));

  const csv = await options.runScheduledTasksCsv().catch(() => "");
  const scheduled_tasks = csv
    .split(/\r?\n/)
    .slice(1)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [name, execute, args] = line.split(",");
      const match = `${execute} ${args}`.match(/[A-Za-z]:\\[^\s]+/);
      return { name, path: match?.[0] ?? "" };
    })
    .filter((task) => task.name && task.path && matchesRepoPath(task.path, options.repoPaths));

  const shimFiles = await readdir(options.shimDir).catch(() => []);
  const shims: Array<{ name: string; target: string }> = [];

  for (const file of shimFiles.filter((f) => f.endsWith(".cmd"))) {
    const fullPath = path.join(options.shimDir, file);
    const body = await readFile(fullPath, "utf8");
    const match = body.match(/[A-Za-z]:\\[^\r\n\"]+/);
    if (!match) continue;
    if (!matchesRepoPath(match[0], options.repoPaths)) continue;

    shims.push({
      name: path.basename(file, ".cmd"),
      target: match[0],
    });
  }

  return { pm2, scheduled_tasks, shims };
}
