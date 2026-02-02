# Dev Environment Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use batch-exec to execute this plan.

**Goal:** Consolidate scattered development projects across multiple locations into a single organized structure at P:\software\ with comprehensive registry tracking, trust-mode validation, and safe migration workflows.

**Architecture:** Extends strap registry with trust modes (registry-first vs disk-discovery), adds commands for snapshot, adopt, audit, archive, and consolidate operations, implements external reference detection (PM2, scheduled tasks, shims, PATH), and provides doctor command for registry-disk consistency management.

**Tech Stack:** TypeScript, Node.js, Git, PowerShell (Windows-native), PM2, registry schema v2

---

<!-- Tasks will be appended by batch-plan subagents -->
### Task 1: Registry Schema V2 Migration + Trust Mode Metadata

**Files:**
- Create: src/registry/migrateToV2.ts
- Test: tests/registry/migrateToV2.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { migrateRegistryToV2 } from "../../../src/registry/migrateToV2";

describe("migrateRegistryToV2", () => {
  it("backs up v1 registry and upgrades to v2 with trust_mode metadata", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-registry-"));
    const buildDir = path.join(root, "build");
    const registryPath = path.join(buildDir, "registry.json");

    await mkdir(buildDir, { recursive: true });
    await writeFile(
      registryPath,
      JSON.stringify(
        {
          registry_version: 1,
          updated_at: "2026-02-01T00:00:00.000Z",
          entries: [{ id: "chinvex", name: "chinvex", scope: "software", path: "C:\\Code\\chinvex" }],
        },
        null,
        2,
      ),
      "utf8",
    );

    await migrateRegistryToV2(registryPath, "2026-02-02T01:00:00.000Z");

    const upgraded = JSON.parse(await readFile(registryPath, "utf8"));
    expect(upgraded.registry_version).toBe(2);
    expect(upgraded.updated_at).toBe("2026-02-02T01:00:00.000Z");
    expect(upgraded.metadata).toEqual({ trust_mode: "registry-first" });
    expect(upgraded.entries[0]).toMatchObject({
      scope: "software",
      archived_at: null,
      last_commit: null,
    });

    const backupPath = path.join(buildDir, "registry.v1.backup.json");
    const backup = JSON.parse(await readFile(backupPath, "utf8"));
    expect(backup.registry_version).toBe(1);
    expect(backup.entries).toHaveLength(1);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/registry/migrateToV2.test.ts`
Expected: FAIL with `Expected 1 to be 2`

**Step 3: Write minimal implementation**
```typescript
import { copyFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

type RegistryEntryV1 = {
  id: string;
  name: string;
  scope: "tool" | "software";
  path: string;
};

type RegistryV1 = {
  registry_version: 1;
  updated_at: string;
  entries: RegistryEntryV1[];
};

type RegistryEntryV2 = RegistryEntryV1 & {
  archived_at: string | null;
  last_commit: string | null;
};

type RegistryV2 = {
  registry_version: 2;
  updated_at: string;
  metadata: { trust_mode: "registry-first" | "disk-discovery" };
  entries: RegistryEntryV2[];
};

export async function migrateRegistryToV2(registryPath: string, nowIso: string): Promise<void> {
  const raw = await readFile(registryPath, "utf8");
  const parsed = JSON.parse(raw) as RegistryV1 | RegistryV2;

  if (parsed.registry_version === 2) {
    return;
  }

  if (parsed.registry_version !== 1) {
    throw new Error("Registry requires strap version X.Y+, please upgrade");
  }

  const backupPath = path.join(path.dirname(registryPath), "registry.v1.backup.json");
  await copyFile(registryPath, backupPath);

  const upgraded: RegistryV2 = {
    registry_version: 2,
    updated_at: nowIso,
    metadata: { trust_mode: "registry-first" },
    entries: parsed.entries.map((entry) => ({
      ...entry,
      archived_at: null,
      last_commit: null,
    })),
  };

  await writeFile(registryPath, JSON.stringify(upgraded, null, 2), "utf8");
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/registry/migrateToV2.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/registry/migrateToV2.ts tests/registry/migrateToV2.test.ts
git commit -m 'feat: migrate registry v1 to v2 with trust mode metadata'
```

### Task 2: Snapshot Command Foundation (CLI Parse + Directory Scan)

**Files:**
- Create: src/commands/snapshot/foundation.ts
- Test: tests/commands/snapshot/foundation.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseSnapshotArgs, scanDirectoriesTopLevel } from "../../../../src/commands/snapshot/foundation";

describe("snapshot foundation", () => {
  it("parses --output and repeated --scan flags", () => {
    const parsed = parseSnapshotArgs([
      "--output",
      "build/snap.json",
      "--scan",
      "C:\\Code",
      "--scan",
      "P:\\software",
    ]);

    expect(parsed.outputPath).toBe(path.resolve("build/snap.json"));
    expect(parsed.scanDirs).toEqual([path.resolve("C:\\Code"), path.resolve("P:\\software")]);
    expect(parsed.trustMode).toBe("disk-discovery");
  });

  it("scans top-level entries and classifies files vs directories", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-scan-"));
    const repoDir = path.join(root, "chinvex");
    const plainDir = path.join(root, "notes");
    const filePath = path.join(root, "helper.ps1");

    await mkdir(repoDir, { recursive: true });
    await mkdir(plainDir, { recursive: true });
    await writeFile(filePath, "Write-Host hi", "utf8");

    const entries = await scanDirectoriesTopLevel([root]);
    expect(entries).toEqual([
      { path: repoDir, type: "directory" },
      { path: plainDir, type: "directory" },
      { path: filePath, type: "file" },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/snapshot/foundation.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/snapshot/foundation'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/snapshot/foundation.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/snapshot/foundation.ts tests/commands/snapshot/foundation.test.ts
git commit -m 'feat: add snapshot argument parsing and top-level scan foundation'
```

### Task 3: Git Repository Discovery + Metadata Collection

**Files:**
- Create: src/commands/snapshot/discoverGitRepos.ts
- Test: tests/commands/snapshot/discoverGitRepos.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { discoverGitRepos } from "../../../../src/commands/snapshot/discoverGitRepos";

describe("discoverGitRepos", () => {
  it("discovers git repos and collects remote + commit metadata", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-discover-"));
    const repoPath = path.join(root, "chinvex");
    const dirPath = path.join(root, "misc-scripts");

    await mkdir(path.join(repoPath, ".git"), { recursive: true });
    await mkdir(dirPath, { recursive: true });
    await writeFile(path.join(dirPath, "script.ps1"), "Write-Host x", "utf8");

    const registryByPath = new Map<string, string>([[repoPath.toLowerCase(), "chinvex"]]);

    const repos = await discoverGitRepos([repoPath, dirPath], {
      registryByPath,
      execGit: async (repo, args) => {
        if (args.join(" ") === "remote get-url origin") return "git@github.com:Chinvex/strap.git";
        if (args.join(" ") === "log -1 --format=%cI") return "2026-01-31T12:34:56+00:00";
        throw new Error(`unexpected git args for ${repo}: ${args.join(" ")}`);
      },
    });

    expect(repos).toEqual([
      {
        path: repoPath,
        name: "chinvex",
        type: "git",
        in_registry: true,
        remote_url: "https://github.com/chinvex/strap",
        last_commit: "2026-01-31T12:34:56+00:00",
      },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/snapshot/discoverGitRepos.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/snapshot/discoverGitRepos'`

**Step 3: Write minimal implementation**
```typescript
import { stat } from "node:fs/promises";
import path from "node:path";

type DiscoverOptions = {
  registryByPath: Map<string, string>;
  execGit: (repoPath: string, args: string[]) => Promise<string>;
};

export type DiscoveredGitRepo = {
  path: string;
  name: string;
  type: "git";
  in_registry: boolean;
  remote_url: string | null;
  last_commit: string | null;
};

function normalizeRemote(url: string): string {
  const sshMatch = url.trim().match(/^git@([^:]+):(.+)$/);
  let normalized = sshMatch ? `https://${sshMatch[1]}/${sshMatch[2]}` : url.trim();
  normalized = normalized.replace(/\.git$/i, "");
  const parsed = new URL(normalized);
  parsed.hostname = parsed.hostname.toLowerCase();
  parsed.pathname = parsed.pathname.replace(/\\/g, "/").toLowerCase();
  return parsed.toString().replace(/\/$/, "");
}

export async function discoverGitRepos(paths: string[], options: DiscoverOptions): Promise<DiscoveredGitRepo[]> {
  const output: DiscoveredGitRepo[] = [];

  for (const candidate of paths) {
    const gitDir = path.join(candidate, ".git");
    const gitStat = await stat(gitDir).catch(() => null);
    if (!gitStat?.isDirectory()) continue;

    const remoteRaw = await options.execGit(candidate, ["remote", "get-url", "origin"]).catch(() => "");
    const lastCommit = await options.execGit(candidate, ["log", "-1", "--format=%cI"]).catch(() => "");

    output.push({
      path: candidate,
      name: path.basename(candidate),
      type: "git",
      in_registry: options.registryByPath.has(candidate.toLowerCase()),
      remote_url: remoteRaw ? normalizeRemote(remoteRaw) : null,
      last_commit: lastCommit || null,
    });
  }

  return output.sort((a, b) => a.path.localeCompare(b.path));
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/snapshot/discoverGitRepos.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/snapshot/discoverGitRepos.ts tests/commands/snapshot/discoverGitRepos.test.ts
git commit -m 'feat: discover git repos with normalized remote and last commit metadata'
```

### Task 4: External Reference Detection (PM2, Scheduled Tasks, Shims)

**Files:**
- Create: src/commands/snapshot/detectExternalRefs.ts
- Test: tests/commands/snapshot/detectExternalRefs.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { detectExternalRefs } from "../../../../src/commands/snapshot/detectExternalRefs";

describe("detectExternalRefs", () => {
  it("detects PM2, scheduled tasks, and shim targets that reference known repos", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-refs-"));
    const shimDir = path.join(root, "build", "shims");
    await mkdir(shimDir, { recursive: true });

    await writeFile(
      path.join(shimDir, "chinvex.cmd"),
      '@echo off\nset "TARGET=C:\\Code\\chinvex\\scripts\\cli.ps1"\npowershell -File "%TARGET%"\n',
      "utf8",
    );

    const refs = await detectExternalRefs({
      repoPaths: ["C:\\Code\\chinvex"],
      shimDir,
      runPm2Jlist: async () =>
        JSON.stringify([{ name: "chinvex-gateway", pm2_env: { pm_cwd: "C:\\Code\\chinvex" } }]),
      runScheduledTasksCsv: async () =>
        [
          'TaskName,Execute,Arguments',
          'MorningBrief,powershell.exe,-File C:\\Code\\chinvex\\scripts\\morning_brief.ps1',
        ].join("\n"),
    });

    expect(refs.pm2).toEqual([{ name: "chinvex-gateway", cwd: "C:\\Code\\chinvex" }]);
    expect(refs.scheduled_tasks).toEqual([
      { name: "MorningBrief", path: "C:\\Code\\chinvex\\scripts\\morning_brief.ps1" },
    ]);
    expect(refs.shims).toEqual([{ name: "chinvex", target: "C:\\Code\\chinvex\\scripts\\cli.ps1" }]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/snapshot/detectExternalRefs.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/snapshot/detectExternalRefs'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/snapshot/detectExternalRefs.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/snapshot/detectExternalRefs.ts tests/commands/snapshot/detectExternalRefs.test.ts
git commit -m 'feat: detect pm2 scheduled task and shim external references'
```

### Task 5: Snapshot JSON Manifest Output + Disk Usage

**Files:**
- Create: src/commands/snapshot/buildSnapshotManifest.ts
- Test: tests/commands/snapshot/buildSnapshotManifest.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { buildSnapshotManifest } from "../../../../src/commands/snapshot/buildSnapshotManifest";

describe("buildSnapshotManifest", () => {
  it("builds the snapshot JSON payload with disk_usage in GB", async () => {
    const manifest = await buildSnapshotManifest({
      nowIso: "2026-02-02T02:00:00.000Z",
      registry: {
        registry_version: 2,
        entries: [{ id: "chinvex", name: "chinvex", scope: "software", path: "C:\\Code\\chinvex" }],
      },
      discovered: [{ path: "C:\\Code\\chinvex", in_registry: true, name: "chinvex", type: "git" }],
      externalRefs: {
        pm2: [{ name: "chinvex-gateway", cwd: "C:\\Code\\chinvex" }],
        scheduled_tasks: [],
        shims: [],
        path_entries: [],
        profile_refs: [],
      },
      getDiskInfo: async () => ({
        "C:": { totalBytes: 500 * 1024 ** 3, freeBytes: 50 * 1024 ** 3 },
        "P:": { totalBytes: 2_000 * 1024 ** 3, freeBytes: 1_200 * 1024 ** 3 },
      }),
    });

    expect(manifest.timestamp).toBe("2026-02-02T02:00:00.000Z");
    expect(manifest.disk_usage).toEqual({
      "C:": { total_gb: 500, free_gb: 50 },
      "P:": { total_gb: 2000, free_gb: 1200 },
    });
    expect(manifest.external_refs.pm2[0].name).toBe("chinvex-gateway");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/snapshot/buildSnapshotManifest.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/snapshot/buildSnapshotManifest'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/snapshot/buildSnapshotManifest.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/snapshot/buildSnapshotManifest.ts tests/commands/snapshot/buildSnapshotManifest.test.ts
git commit -m 'feat: output snapshot manifest json with disk usage summary'
```
### Task 6: Adopt Command Foundation (CLI Parsing + Top-Level Scan Mode)

**Files:**
- Create: src/commands/adopt/foundation.ts
- Test: tests/commands/adopt/foundation.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseAdoptArgs, scanAdoptTopLevel } from "../../../../src/commands/adopt/foundation";

describe("adopt foundation", () => {
  it("parses scan-mode flags and defaults to disk-discovery trust mode", () => {
    const parsed = parseAdoptArgs([
      "--scan",
      "C:\\Code",
      "--recursive",
      "--dry-run",
      "--yes",
      "--scope",
      "tool",
    ]);

    expect(parsed.scanDir).toBe(path.resolve("C:\\Code"));
    expect(parsed.recursive).toBe(true);
    expect(parsed.dryRun).toBe(true);
    expect(parsed.yes).toBe(true);
    expect(parsed.scope).toBe("tool");
    expect(parsed.trustMode).toBe("disk-discovery");
  });

  it("errors when --scan is missing", () => {
    expect(() => parseAdoptArgs(["--yes"])).toThrow("adopt requires --scan <dir>");
  });

  it("scans top-level items and marks already-registered directories", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-top-"));
    const existingRepo = path.join(root, "chinvex");
    const newDir = path.join(root, "notes");
    const helper = path.join(root, "helper.ps1");

    await mkdir(path.join(existingRepo, ".git"), { recursive: true });
    await mkdir(newDir, { recursive: true });
    await writeFile(helper, "Write-Host hi", "utf8");

    const items = await scanAdoptTopLevel(root, new Set([existingRepo.toLowerCase()]));

    expect(items).toEqual([
      { path: existingRepo, kind: "git", alreadyRegistered: true },
      { path: helper, kind: "file", alreadyRegistered: false },
      { path: newDir, kind: "directory", alreadyRegistered: false },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/adopt/foundation.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/adopt/foundation'`

**Step 3: Write minimal implementation**
```typescript
import { readdir, stat } from "node:fs/promises";
import path from "node:path";

export type AdoptArgs = {
  scanDir: string;
  recursive: boolean;
  dryRun: boolean;
  yes: boolean;
  allowAutoArchive: boolean;
  scope?: "tool" | "software" | "archive";
  trustMode: "disk-discovery";
};

export type AdoptScanItem = {
  path: string;
  kind: "git" | "directory" | "file";
  alreadyRegistered: boolean;
};

export function parseAdoptArgs(argv: string[]): AdoptArgs {
  let scanDir: string | undefined;
  let recursive = false;
  let dryRun = false;
  let yes = false;
  let allowAutoArchive = false;
  let scope: AdoptArgs["scope"];

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--scan" && argv[i + 1]) {
      scanDir = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === "--recursive") recursive = true;
    if (token === "--dry-run") dryRun = true;
    if (token === "--yes") yes = true;
    if (token === "--allow-auto-archive") allowAutoArchive = true;
    if (token === "--scope" && argv[i + 1]) {
      const next = argv[i + 1] as AdoptArgs["scope"];
      if (!["tool", "software", "archive"].includes(next)) {
        throw new Error("--scope must be tool|software|archive");
      }
      scope = next;
      i += 1;
    }
  }

  if (!scanDir) {
    throw new Error("adopt requires --scan <dir>");
  }

  return {
    scanDir: path.resolve(scanDir),
    recursive,
    dryRun,
    yes,
    allowAutoArchive,
    scope,
    trustMode: "disk-discovery",
  };
}

export async function scanAdoptTopLevel(scanDir: string, registryPathsLower: Set<string>): Promise<AdoptScanItem[]> {
  const dirents = await readdir(scanDir, { withFileTypes: true });
  const out: AdoptScanItem[] = [];

  for (const dirent of dirents) {
    const full = path.join(scanDir, dirent.name);
    const alreadyRegistered = registryPathsLower.has(full.toLowerCase());

    if (dirent.isFile()) {
      out.push({ path: full, kind: "file", alreadyRegistered: false });
      continue;
    }

    if (dirent.isDirectory()) {
      const gitDir = path.join(full, ".git");
      let kind: AdoptScanItem["kind"] = "directory";
      try {
        const s = await stat(gitDir);
        if (s.isDirectory()) kind = "git";
      } catch {
        kind = "directory";
      }

      out.push({ path: full, kind, alreadyRegistered });
    }
  }

  return out.sort((a, b) => a.path.localeCompare(b.path));
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/adopt/foundation.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/adopt/foundation.ts tests/commands/adopt/foundation.test.ts
git commit -m 'feat: add adopt command parse and top-level scan foundation'
```

### Task 7: Adopt Recursive Directory Scanning

**Files:**
- Create: src/commands/adopt/scanRecursive.ts
- Test: tests/commands/adopt/scanRecursive.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { scanAdoptCandidates } from "../../../../src/commands/adopt/scanRecursive";

describe("scanAdoptCandidates", () => {
  it("top-level mode only returns immediate children", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-scan-"));
    const app = path.join(root, "app");
    const nested = path.join(app, "nested");

    await mkdir(path.join(app, ".git"), { recursive: true });
    await mkdir(nested, { recursive: true });

    const found = await scanAdoptCandidates(root, false);

    expect(found.map((f) => f.path)).toEqual([app]);
    expect(found[0].kind).toBe("git");
  });

  it("recursive mode traverses nested directories and surfaces files as skipped", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-rec-"));
    const scripts = path.join(root, "scripts");
    const nestedRepo = path.join(scripts, "toolbox");
    const note = path.join(scripts, "todo.txt");

    await mkdir(path.join(nestedRepo, ".git"), { recursive: true });
    await writeFile(note, "remember me", "utf8");

    const found = await scanAdoptCandidates(root, true);

    expect(found).toEqual([
      { path: scripts, kind: "directory" },
      { path: note, kind: "file" },
      { path: nestedRepo, kind: "git" },
    ]);
  });

  it("skips node_modules, venv, and .git internals while recursing", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-adopt-skip-"));
    const repo = path.join(root, "repo");
    const ignoredNodeModules = path.join(repo, "node_modules", "left-pad");

    await mkdir(path.join(repo, ".git"), { recursive: true });
    await mkdir(ignoredNodeModules, { recursive: true });

    const found = await scanAdoptCandidates(root, true);

    expect(found.some((entry) => entry.path.includes("node_modules"))).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/adopt/scanRecursive.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/adopt/scanRecursive'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/adopt/scanRecursive.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/adopt/scanRecursive.ts tests/commands/adopt/scanRecursive.test.ts
git commit -m 'feat: add recursive adopt scanner with skip rules'
```

### Task 8: Adopt Dry-Run Mode with Confirmation Flow

**Files:**
- Create: src/commands/adopt/confirmAndApply.ts
- Test: tests/commands/adopt/confirmAndApply.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { applyAdoptionPlan, buildAdoptionPlan } from "../../../../src/commands/adopt/confirmAndApply";

describe("adopt confirm/apply", () => {
  it("prompts per item when --yes is not provided", async () => {
    const ask = vi.fn(async () => "archive");

    const plan = await buildAdoptionPlan(
      [
        { path: "C:\\Code\\old-repo", kind: "git", suggestedScope: "software", alreadyRegistered: false },
      ],
      { yes: false, allowAutoArchive: false, scopeOverride: undefined },
      ask,
    );

    expect(ask).toHaveBeenCalledTimes(1);
    expect(plan[0].finalScope).toBe("archive");
  });

  it("keeps archive suggestions safe in --yes mode unless --allow-auto-archive is set", async () => {
    const plan = await buildAdoptionPlan(
      [
        { path: "C:\\Code\\very-old", kind: "git", suggestedScope: "archive", alreadyRegistered: false },
      ],
      { yes: true, allowAutoArchive: false, scopeOverride: undefined },
      async () => "archive",
    );

    expect(plan[0].finalScope).toBe("software");
  });

  it("dry-run does not write to registry", async () => {
    const writeEntry = vi.fn(async () => undefined);

    const result = await applyAdoptionPlan(
      [
        { path: "C:\\Code\\toolbox", finalScope: "tool", skip: false },
        { path: "C:\\Code\\readme.txt", finalScope: "tool", skip: true },
      ],
      { dryRun: true },
      writeEntry,
    );

    expect(writeEntry).not.toHaveBeenCalled();
    expect(result.adoptedCount).toBe(1);
    expect(result.dryRun).toBe(true);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/adopt/confirmAndApply.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/adopt/confirmAndApply'`

**Step 3: Write minimal implementation**
```typescript
export type SuggestedScope = "tool" | "software" | "archive";

export type DiscoveryItem = {
  path: string;
  kind: "git" | "directory" | "file";
  suggestedScope: SuggestedScope;
  alreadyRegistered: boolean;
};

export type PlannedItem = {
  path: string;
  finalScope: SuggestedScope;
  skip: boolean;
};

export async function buildAdoptionPlan(
  discovered: DiscoveryItem[],
  opts: { yes: boolean; allowAutoArchive: boolean; scopeOverride?: SuggestedScope },
  ask: (item: DiscoveryItem) => Promise<SuggestedScope | "skip">,
): Promise<PlannedItem[]> {
  const plan: PlannedItem[] = [];

  for (const item of discovered) {
    if (item.kind === "file" || item.alreadyRegistered) {
      plan.push({ path: item.path, finalScope: item.suggestedScope, skip: true });
      continue;
    }

    if (opts.scopeOverride) {
      plan.push({ path: item.path, finalScope: opts.scopeOverride, skip: false });
      continue;
    }

    if (opts.yes) {
      const safeScope = item.suggestedScope === "archive" && !opts.allowAutoArchive ? "software" : item.suggestedScope;
      plan.push({ path: item.path, finalScope: safeScope, skip: false });
      continue;
    }

    const answer = await ask(item);
    if (answer === "skip") {
      plan.push({ path: item.path, finalScope: item.suggestedScope, skip: true });
      continue;
    }

    plan.push({ path: item.path, finalScope: answer, skip: false });
  }

  return plan;
}

export async function applyAdoptionPlan(
  plan: PlannedItem[],
  opts: { dryRun: boolean },
  writeEntry: (item: PlannedItem) => Promise<void>,
): Promise<{ adoptedCount: number; dryRun: boolean }> {
  const actionable = plan.filter((item) => !item.skip);

  if (!opts.dryRun) {
    for (const item of actionable) {
      await writeEntry(item);
    }
  }

  return {
    adoptedCount: actionable.length,
    dryRun: opts.dryRun,
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/adopt/confirmAndApply.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/adopt/confirmAndApply.ts tests/commands/adopt/confirmAndApply.test.ts
git commit -m 'feat: implement adopt confirmation flow and dry-run behavior'
```

### Task 9: Audit Command Validation Checks

**Files:**
- Create: src/commands/audit/validateRequest.ts
- Test: tests/commands/audit/validateRequest.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { parseAuditArgs, validateAuditRequest } from "../../../../src/commands/audit/validateRequest";

describe("audit request validation", () => {
  it("parses --all, --json and --rebuild-index flags", () => {
    const parsed = parseAuditArgs(["--all", "--json", "--rebuild-index"]);
    expect(parsed).toEqual({ target: undefined, all: true, json: true, rebuildIndex: true, trustMode: "registry-first" });
  });

  it("fails when neither name nor --all is provided", () => {
    expect(() => validateAuditRequest(parseAuditArgs([]), ["chinvex"]))
      .toThrow("Provide a target name or --all");
  });

  it("fails when both name and --all are provided", () => {
    expect(() => validateAuditRequest(parseAuditArgs(["chinvex", "--all"]), ["chinvex"]))
      .toThrow("Cannot combine a target name with --all");
  });

  it("fails when target is missing from registry", () => {
    expect(() => validateAuditRequest(parseAuditArgs(["unknown"]), ["chinvex"]))
      .toThrow("Registry entry 'unknown' not found");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/audit/validateRequest.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/audit/validateRequest'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/audit/validateRequest.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/audit/validateRequest.ts tests/commands/audit/validateRequest.test.ts
git commit -m 'feat: validate audit command input and trust mode behavior'
```

### Task 10: Audit Index Rebuild Functionality

**Files:**
- Create: src/commands/audit/index.ts
- Test: tests/commands/audit/index.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { loadOrBuildAuditIndex } from "../../../../src/commands/audit/index";

describe("loadOrBuildAuditIndex", () => {
  it("builds index on first run and writes build/audit-index.json", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-"));
    const indexPath = path.join(root, "audit-index.json");

    const scanRepo = vi.fn(async (repoPath: string) => ({ references: [repoPath + "\\scripts\\x.ps1"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: false,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).toHaveBeenCalledTimes(1);
    expect(index.repos["C:\\Code\\chinvex"].references).toHaveLength(1);

    const onDisk = JSON.parse(await readFile(indexPath, "utf8"));
    expect(onDisk.registry_updated_at).toBe("2026-02-02T10:00:00.000Z");
  });

  it("reuses existing index when metadata is fresh and --rebuild-index is not set", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-fresh-"));
    const indexPath = path.join(root, "audit-index.json");

    await writeFile(
      indexPath,
      JSON.stringify(
        {
          built_at: "2026-02-02T10:00:00.000Z",
          registry_updated_at: "2026-02-02T10:00:00.000Z",
          repo_count: 1,
          repos: { "C:\\Code\\chinvex": { references: ["x"] } },
        },
        null,
        2,
      ),
      "utf8",
    );

    const scanRepo = vi.fn(async () => ({ references: ["new"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: false,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).not.toHaveBeenCalled();
    expect(index.repos["C:\\Code\\chinvex"].references).toEqual(["x"]);
  });

  it("forces rebuild when --rebuild-index is set", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-audit-index-rebuild-"));
    const indexPath = path.join(root, "audit-index.json");

    await writeFile(
      indexPath,
      JSON.stringify(
        {
          built_at: "2026-02-01T00:00:00.000Z",
          registry_updated_at: "2026-02-01T00:00:00.000Z",
          repo_count: 1,
          repos: { "C:\\Code\\chinvex": { references: ["stale"] } },
        },
        null,
        2,
      ),
      "utf8",
    );

    const scanRepo = vi.fn(async () => ({ references: ["fresh"] }));

    const index = await loadOrBuildAuditIndex({
      indexPath,
      rebuildIndex: true,
      registryUpdatedAt: "2026-02-02T10:00:00.000Z",
      repoPaths: ["C:\\Code\\chinvex"],
      scanRepo,
    });

    expect(scanRepo).toHaveBeenCalledTimes(1);
    expect(index.repos["C:\\Code\\chinvex"].references).toEqual(["fresh"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/audit/index.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/audit/index'`

**Step 3: Write minimal implementation**
```typescript
import { readFile, writeFile } from "node:fs/promises";

export type AuditIndex = {
  built_at: string;
  registry_updated_at: string;
  repo_count: number;
  repos: Record<string, { references: string[] }>;
};

type LoadOrBuildInput = {
  indexPath: string;
  rebuildIndex: boolean;
  registryUpdatedAt: string;
  repoPaths: string[];
  scanRepo: (repoPath: string) => Promise<{ references: string[] }>;
};

function nowIso(): string {
  return new Date().toISOString();
}

async function tryReadIndex(indexPath: string): Promise<AuditIndex | null> {
  try {
    return JSON.parse(await readFile(indexPath, "utf8")) as AuditIndex;
  } catch {
    return null;
  }
}

function isFresh(index: AuditIndex, registryUpdatedAt: string, repoPaths: string[]): boolean {
  return index.registry_updated_at === registryUpdatedAt && index.repo_count === repoPaths.length;
}

export async function loadOrBuildAuditIndex(input: LoadOrBuildInput): Promise<AuditIndex> {
  const existing = await tryReadIndex(input.indexPath);

  if (existing && !input.rebuildIndex && isFresh(existing, input.registryUpdatedAt, input.repoPaths)) {
    return existing;
  }

  const repos: AuditIndex["repos"] = {};
  for (const repoPath of input.repoPaths) {
    repos[repoPath] = await input.scanRepo(repoPath);
  }

  const built: AuditIndex = {
    built_at: nowIso(),
    registry_updated_at: input.registryUpdatedAt,
    repo_count: input.repoPaths.length,
    repos,
  };

  await writeFile(input.indexPath, JSON.stringify(built, null, 2), "utf8");
  return built;
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/audit/index.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/audit/index.ts tests/commands/audit/index.test.ts
git commit -m 'feat: add audit index cache and rebuild flow'
```


### Task 11: Archive Command Safety Checks (Registry-First)

**Files:**
- Create: src/commands/archive/safety.ts
- Test: tests/commands/archive/safety.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { planArchiveMove } from "../../../../src/commands/archive/safety";

describe("planArchiveMove", () => {
  it("returns a valid archive move plan for an existing registry entry", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-safety-"));
    const sourcePath = path.join(root, "old-experiment");
    const archiveRoot = path.join(root, "_archive");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(archiveRoot, { recursive: true });

    const plan = await planArchiveMove(
      {
        name: "old-experiment",
        trustMode: "registry-first",
      },
      {
        entries: [
          {
            id: "old-experiment",
            name: "old-experiment",
            scope: "software",
            path: sourcePath,
          },
        ],
      },
      {
        archiveRoot,
      },
    );

    expect(plan).toMatchObject({
      name: "old-experiment",
      fromPath: sourcePath,
      toPath: path.join(archiveRoot, "old-experiment"),
      nextScope: "archive",
    });
  });

  it("fails on registry-disk drift and suggests doctor --fix-paths", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-drift-"));
    const archiveRoot = path.join(root, "_archive");
    await mkdir(archiveRoot, { recursive: true });

    await expect(
      planArchiveMove(
        { name: "old-experiment", trustMode: "registry-first" },
        {
          entries: [
            {
              id: "old-experiment",
              name: "old-experiment",
              scope: "software",
              path: path.join(root, "missing-old-experiment"),
            },
          ],
        },
        { archiveRoot },
      ),
    ).rejects.toThrow("Registry path drift detected for 'old-experiment'. Run 'strap doctor --fix-paths'.");
  });

  it("fails fast when destination path already exists", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-archive-collision-"));
    const sourcePath = path.join(root, "old-experiment");
    const archiveRoot = path.join(root, "_archive");
    const destinationPath = path.join(archiveRoot, "old-experiment");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(destinationPath, { recursive: true });

    await expect(
      planArchiveMove(
        { name: "old-experiment", trustMode: "registry-first" },
        {
          entries: [
            {
              id: "old-experiment",
              name: "old-experiment",
              scope: "software",
              path: sourcePath,
            },
          ],
        },
        { archiveRoot },
      ),
    ).rejects.toThrow("Destination already exists: " + destinationPath);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/archive/safety.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/archive/safety'`

**Step 3: Write minimal implementation**
```typescript
import { access } from "node:fs/promises";
import path from "node:path";

export type ArchiveTrustMode = "registry-first";

export type ArchiveEntry = {
  id: string;
  name: string;
  scope: "tool" | "software" | "archive";
  path: string;
};

export type ArchiveRegistry = {
  entries: ArchiveEntry[];
};

export type ArchivePlan = {
  name: string;
  fromPath: string;
  toPath: string;
  nextScope: "archive";
};

async function exists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function planArchiveMove(
  args: { name: string; trustMode: ArchiveTrustMode },
  registry: ArchiveRegistry,
  roots: { archiveRoot: string },
): Promise<ArchivePlan> {
  if (args.trustMode !== "registry-first") {
    throw new Error("strap archive supports registry-first trust mode only");
  }

  const entry = registry.entries.find((item) => item.name === args.name || item.id === args.name);
  if (!entry) {
    throw new Error(`Registry entry '${args.name}' not found`);
  }

  if (!(await exists(entry.path))) {
    throw new Error(`Registry path drift detected for '${entry.name}'. Run 'strap doctor --fix-paths'.`);
  }

  const toPath = path.join(roots.archiveRoot, path.basename(entry.path));
  if (await exists(toPath)) {
    throw new Error(`Destination already exists: ${toPath}`);
  }

  return {
    name: entry.name,
    fromPath: entry.path,
    toPath,
    nextScope: "archive",
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/archive/safety.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/archive/safety.ts tests/commands/archive/safety.test.ts
git commit -m 'feat: add archive safety checks for drift and collisions'
```

### Task 12: Archive Dry-Run Mode

**Files:**
- Create: src/commands/archive/dryRun.ts
- Test: tests/commands/archive/dryRun.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runArchiveCommand } from "../../../../src/commands/archive/dryRun";

describe("runArchiveCommand dry-run", () => {
  it("prints equivalent move and registry update plan without mutating state", async () => {
    const executeMove = vi.fn(async () => undefined);
    const updateRegistry = vi.fn(async () => undefined);
    const updateChinvex = vi.fn(async () => undefined);

    const result = await runArchiveCommand(
      {
        plan: {
          name: "old-experiment",
          fromPath: "C:\\Code\\old-experiment",
          toPath: "P:\\software\\_archive\\old-experiment",
          nextScope: "archive",
        },
        dryRun: true,
        yes: true,
      },
      { executeMove, updateRegistry, updateChinvex },
    );

    expect(executeMove).not.toHaveBeenCalled();
    expect(updateRegistry).not.toHaveBeenCalled();
    expect(updateChinvex).not.toHaveBeenCalled();
    expect(result.executed).toBe(false);
    expect(result.preview).toContain("strap move old-experiment --dest P:\\software\\_archive\\ --yes");
    expect(result.preview).toContain("registry scope: software -> archive");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/archive/dryRun.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/archive/dryRun'`

**Step 3: Write minimal implementation**
```typescript
export type ArchiveExecutionPlan = {
  name: string;
  fromPath: string;
  toPath: string;
  nextScope: "archive";
};

type RunArchiveInput = {
  plan: ArchiveExecutionPlan;
  dryRun: boolean;
  yes: boolean;
};

type ArchiveHandlers = {
  executeMove: (fromPath: string, toPath: string) => Promise<void>;
  updateRegistry: (name: string, nextScope: "archive", nextPath: string) => Promise<void>;
  updateChinvex: (name: string, nextScope: "archive") => Promise<void>;
};

export async function runArchiveCommand(input: RunArchiveInput, handlers: ArchiveHandlers): Promise<{ executed: boolean; preview: string }> {
  const preview = [
    `strap move ${input.plan.name} --dest P:\\software\\_archive\\ --yes`,
    `move: ${input.plan.fromPath} -> ${input.plan.toPath}`,
    "registry scope: software -> archive",
  ].join("\n");

  if (input.dryRun) {
    return { executed: false, preview };
  }

  await handlers.executeMove(input.plan.fromPath, input.plan.toPath);
  await handlers.updateRegistry(input.plan.name, input.plan.nextScope, input.plan.toPath);
  await handlers.updateChinvex(input.plan.name, input.plan.nextScope);

  return { executed: true, preview };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/archive/dryRun.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/archive/dryRun.ts tests/commands/archive/dryRun.test.ts
git commit -m 'feat: add archive dry-run preview mode'
```

### Task 13: Consolidate Command Structure and Trust-Mode Validation

**Files:**
- Create: src/commands/consolidate/args.ts
- Test: tests/commands/consolidate/args.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { parseConsolidateArgs, validateConsolidateArgs } from "../../../../src/commands/consolidate/args";

describe("consolidate args", () => {
  it("parses required and optional flags with registry-first trust mode", () => {
    const parsed = parseConsolidateArgs([
      "--from",
      "C:\\Code",
      "--to",
      "P:\\software",
      "--dry-run",
      "--yes",
      "--stop-pm2",
      "--ack-scheduled-tasks",
      "--allow-dirty",
      "--allow-auto-archive",
    ]);

    expect(parsed).toMatchObject({
      from: "C:\\Code",
      to: "P:\\software",
      dryRun: true,
      yes: true,
      stopPm2: true,
      ackScheduledTasks: true,
      allowDirty: true,
      allowAutoArchive: true,
      trustMode: "registry-first",
    });
  });

  it("fails when --from is missing", () => {
    expect(() => validateConsolidateArgs(parseConsolidateArgs(["--dry-run"]))).toThrow(
      "--from is required",
    );
  });

  it("fails when disk-discovery trust mode is requested", () => {
    expect(() =>
      validateConsolidateArgs(parseConsolidateArgs(["--from", "C:\\Code", "--trust-mode", "disk-discovery"])),
    ).toThrow("strap consolidate is registry-first; run 'strap doctor --fix-paths' first for disk-discovery recovery");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/args.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/args'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/args.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/args.ts tests/commands/consolidate/args.test.ts
git commit -m 'feat: add consolidate arg parsing and trust mode validation'
```

### Task 14: Consolidate Registry + Disk Validation and Conflict Resolution

**Files:**
- Create: src/commands/consolidate/registryDiskValidation.ts
- Test: tests/commands/consolidate/registryDiskValidation.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { validateConsolidateRegistryDisk } from "../../../../src/commands/consolidate/registryDiskValidation";

describe("validateConsolidateRegistryDisk", () => {
  it("fails on registry-first drift when registry path is missing", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-drift-"));

    await expect(
      validateConsolidateRegistryDisk({
        trustMode: "registry-first",
        registeredMoves: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: path.join(root, "missing-chinvex"),
            destinationPath: path.join(root, "dest", "chinvex"),
          },
        ],
        discoveredCandidates: [],
      }),
    ).rejects.toThrow("Registry path drift detected for 'chinvex'. Run 'strap doctor --fix-paths'.");
  });

  it("fails fast when destination already exists for a registered move", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-target-exists-"));
    const sourcePath = path.join(root, "source", "chinvex");
    const destinationPath = path.join(root, "dest", "chinvex");

    await mkdir(sourcePath, { recursive: true });
    await mkdir(destinationPath, { recursive: true });

    await expect(
      validateConsolidateRegistryDisk({
        trustMode: "registry-first",
        registeredMoves: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: sourcePath,
            destinationPath,
          },
        ],
        discoveredCandidates: [],
      }),
    ).rejects.toThrow("Conflict: destination already exists for 'chinvex': " + destinationPath + ". Resolve manually before consolidate.");
  });

  it("warns when discovered repo name collides with registry name at different path", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-consolidate-name-collision-"));
    const registeredPath = path.join(root, "registered", "streamside");

    await mkdir(registeredPath, { recursive: true });

    const result = await validateConsolidateRegistryDisk({
      trustMode: "registry-first",
      registeredMoves: [
        {
          id: "streamside",
          name: "streamside",
          registryPath: registeredPath,
          destinationPath: path.join(root, "dest", "streamside"),
        },
      ],
      discoveredCandidates: [
        {
          name: "streamside",
          sourcePath: path.join(root, "new-source", "streamside"),
        },
      ],
    });

    expect(result.warnings).toEqual([
      "Name collision: discovered repo 'streamside' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion.",
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/registryDiskValidation.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/registryDiskValidation'`

**Step 3: Write minimal implementation**
```typescript
import { access } from "node:fs/promises";

type RegisteredMove = {
  id: string;
  name: string;
  registryPath: string;
  destinationPath: string;
};

type DiscoveredCandidate = {
  name: string;
  sourcePath: string;
};

type ValidateInput = {
  trustMode: "registry-first";
  registeredMoves: RegisteredMove[];
  discoveredCandidates: DiscoveredCandidate[];
};

async function exists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

function normalize(p: string): string {
  return p.replaceAll("/", "\\").replace(/\\+$/, "").toLowerCase();
}

export async function validateConsolidateRegistryDisk(input: ValidateInput): Promise<{ warnings: string[] }> {
  const warnings: string[] = [];

  for (const move of input.registeredMoves) {
    if (!(await exists(move.registryPath))) {
      throw new Error(`Registry path drift detected for '${move.name}'. Run 'strap doctor --fix-paths'.`);
    }

    if (await exists(move.destinationPath)) {
      throw new Error(
        `Conflict: destination already exists for '${move.name}': ${move.destinationPath}. Resolve manually before consolidate.`,
      );
    }
  }

  for (const candidate of input.discoveredCandidates) {
    const matching = input.registeredMoves.find((move) => move.name.toLowerCase() === candidate.name.toLowerCase());
    if (!matching) {
      continue;
    }

    if (normalize(matching.registryPath) !== normalize(candidate.sourcePath)) {
      warnings.push(
        `Name collision: discovered repo '${candidate.name}' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion.`,
      );
    }
  }

  return { warnings };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/registryDiskValidation.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/registryDiskValidation.ts tests/commands/consolidate/registryDiskValidation.test.ts
git commit -m 'feat: validate consolidate registry-disk drift and conflicts'
```

### Task 15: Consolidate Dry-Run Wizard Mode (Steps 1-4 Only)

**Files:**
- Create: src/commands/consolidate/dryRun.ts
- Test: tests/commands/consolidate/dryRun.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runConsolidateWizard } from "../../../../src/commands/consolidate/dryRun";

describe("runConsolidateWizard dry-run", () => {
  it("executes steps 1-4 and skips execute/verify in dry-run mode", async () => {
    const handlers = {
      snapshot: vi.fn(async () => undefined),
      discovery: vi.fn(async () => undefined),
      audit: vi.fn(async () => undefined),
      preflight: vi.fn(async () => undefined),
      execute: vi.fn(async () => undefined),
      verify: vi.fn(async () => undefined),
    };

    const result = await runConsolidateWizard({ dryRun: true }, handlers);

    expect(handlers.snapshot).toHaveBeenCalledTimes(1);
    expect(handlers.discovery).toHaveBeenCalledTimes(1);
    expect(handlers.audit).toHaveBeenCalledTimes(1);
    expect(handlers.preflight).toHaveBeenCalledTimes(1);
    expect(handlers.execute).not.toHaveBeenCalled();
    expect(handlers.verify).not.toHaveBeenCalled();

    expect(result.executed).toBe(false);
    expect(result.completedSteps).toEqual(["snapshot", "discovery", "audit", "preflight"]);
    expect(result.message).toContain("Dry run complete");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/dryRun.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/dryRun'`

**Step 3: Write minimal implementation**
```typescript
type WizardHandlers = {
  snapshot: () => Promise<void>;
  discovery: () => Promise<void>;
  audit: () => Promise<void>;
  preflight: () => Promise<void>;
  execute: () => Promise<void>;
  verify: () => Promise<void>;
};

export async function runConsolidateWizard(
  input: { dryRun: boolean },
  handlers: WizardHandlers,
): Promise<{ executed: boolean; completedSteps: string[]; message: string }> {
  const completedSteps: string[] = [];

  await handlers.snapshot();
  completedSteps.push("snapshot");

  await handlers.discovery();
  completedSteps.push("discovery");

  await handlers.audit();
  completedSteps.push("audit");

  await handlers.preflight();
  completedSteps.push("preflight");

  if (input.dryRun) {
    return {
      executed: false,
      completedSteps,
      message: "Dry run complete. Steps 1-4 executed; no moves or registry changes were made.",
    };
  }

  await handlers.execute();
  completedSteps.push("execute");

  await handlers.verify();
  completedSteps.push("verify");

  return {
    executed: true,
    completedSteps,
    message: "Consolidation complete.",
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/dryRun.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/dryRun.ts tests/commands/consolidate/dryRun.test.ts
git commit -m 'feat: add consolidate dry-run wizard behavior'
```

### Task 16: Consolidate Move Execution with Managed External Reference Updates

**Files:**
- Create: src/commands/consolidate/executeMoves.ts
- Test: tests/commands/consolidate/executeMoves.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { executeConsolidateMoves } from "../../../../src/commands/consolidate/executeMoves";

describe("executeConsolidateMoves", () => {
  it("moves repos, updates registry/chinvex, updates managed refs, and returns manual fixes", async () => {
    const calls: string[] = [];
    const handlers = {
      executeMove: vi.fn(async (name: string) => {
        calls.push(`move:${name}`);
      }),
      updateRegistryPath: vi.fn(async (name: string, nextPath: string) => {
        calls.push(`registry:${name}:${nextPath}`);
      }),
      updateChinvexScope: vi.fn(async (name: string, nextScope: "software" | "tool" | "archive") => {
        calls.push(`chinvex:${name}:${nextScope}`);
      }),
      updateManagedExternalRefs: vi.fn(async (repoName: string, fromPath: string, toPath: string) => {
        calls.push(`managed:${repoName}`);
        return [
          `Updated shim '${repoName}' to ${toPath}`,
          `Updated PATH entry for ${repoName}`,
        ];
      }),
      collectManualExternalFixes: vi.fn(async (repoName: string, fromPath: string, toPath: string) => {
        calls.push(`manual:${repoName}`);
        return [
          `$PROFILE alias still points to ${fromPath}`,
          `Scheduled task for ${repoName} still points to ${fromPath}`,
        ];
      }),
    };

    const result = await executeConsolidateMoves(
      {
        plans: [
          {
            name: "chinvex",
            fromPath: "C:\\Code\\chinvex",
            toPath: "P:\\software\\chinvex",
            scope: "software",
          },
          {
            name: "misc-scripts",
            fromPath: "C:\\Code\\misc-scripts",
            toPath: "P:\\software\\_scripts\\misc-scripts",
            scope: "tool",
          },
        ],
      },
      handlers,
    );

    expect(result.moved).toEqual(["chinvex", "misc-scripts"]);
    expect(result.managedUpdates).toEqual([
      "Updated shim 'chinvex' to P:\\software\\chinvex",
      "Updated PATH entry for chinvex",
      "Updated shim 'misc-scripts' to P:\\software\\_scripts\\misc-scripts",
      "Updated PATH entry for misc-scripts",
    ]);
    expect(result.manualFixes).toEqual([
      "$PROFILE alias still points to C:\\Code\\chinvex",
      "Scheduled task for chinvex still points to C:\\Code\\chinvex",
      "$PROFILE alias still points to C:\\Code\\misc-scripts",
      "Scheduled task for misc-scripts still points to C:\\Code\\misc-scripts",
    ]);

    expect(calls).toEqual([
      "move:chinvex",
      "registry:chinvex:P:\\software\\chinvex",
      "chinvex:chinvex:software",
      "managed:chinvex",
      "manual:chinvex",
      "move:misc-scripts",
      "registry:misc-scripts:P:\\software\\_scripts\\misc-scripts",
      "chinvex:misc-scripts:tool",
      "managed:misc-scripts",
      "manual:misc-scripts",
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/executeMoves.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/executeMoves'`

**Step 3: Write minimal implementation**
```typescript
export type ConsolidateMovePlan = {
  name: string;
  fromPath: string;
  toPath: string;
  scope: "software" | "tool" | "archive";
};

type ExecuteInput = {
  plans: ConsolidateMovePlan[];
};

type ExecuteHandlers = {
  executeMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  updateRegistryPath: (name: string, nextPath: string) => Promise<void>;
  updateChinvexScope: (name: string, nextScope: "software" | "tool" | "archive") => Promise<void>;
  updateManagedExternalRefs: (repoName: string, fromPath: string, toPath: string) => Promise<string[]>;
  collectManualExternalFixes: (repoName: string, fromPath: string, toPath: string) => Promise<string[]>;
};

export async function executeConsolidateMoves(
  input: ExecuteInput,
  handlers: ExecuteHandlers,
): Promise<{ moved: string[]; managedUpdates: string[]; manualFixes: string[] }> {
  const moved: string[] = [];
  const managedUpdates: string[] = [];
  const manualFixes: string[] = [];

  for (const plan of input.plans) {
    await handlers.executeMove(plan.name, plan.fromPath, plan.toPath);
    await handlers.updateRegistryPath(plan.name, plan.toPath);
    await handlers.updateChinvexScope(plan.name, plan.scope);

    managedUpdates.push(...(await handlers.updateManagedExternalRefs(plan.name, plan.fromPath, plan.toPath)));
    manualFixes.push(...(await handlers.collectManualExternalFixes(plan.name, plan.fromPath, plan.toPath)));

    moved.push(plan.name);
  }

  return { moved, managedUpdates, manualFixes };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/executeMoves.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/executeMoves.ts tests/commands/consolidate/executeMoves.test.ts
git commit -m 'feat: execute consolidate moves with managed external reference updates'
```

### Task 17: Consolidate Rollback on Failure

**Files:**
- Create: src/commands/consolidate/transaction.ts
- Test: tests/commands/consolidate/transaction.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runConsolidateTransaction } from "../../../../src/commands/consolidate/transaction";

describe("runConsolidateTransaction", () => {
  it("rolls back completed moves in reverse order and skips registry write when move fails", async () => {
    const events: string[] = [];
    const handlers = {
      writeRollbackLogStart: vi.fn(async () => {
        events.push("rollback-log:start");
      }),
      executeMove: vi.fn(async (name: string) => {
        events.push(`move:${name}`);
        if (name === "streamside") {
          throw new Error("copy verification failed for streamside");
        }
      }),
      rollbackMove: vi.fn(async (name: string) => {
        events.push(`rollback:${name}`);
      }),
      writeRollbackLogResult: vi.fn(async (payload: { completed: string[]; failed?: string }) => {
        events.push(`rollback-log:result:${payload.completed.join(",")}:${payload.failed ?? ""}`);
      }),
      writeRegistryBatch: vi.fn(async () => {
        events.push("registry:write");
      }),
      updateChinvexBatch: vi.fn(async () => {
        events.push("chinvex:write");
      }),
    };

    await expect(
      runConsolidateTransaction(
        {
          plans: [
            { name: "chinvex", fromPath: "C:\\Code\\chinvex", toPath: "P:\\software\\chinvex" },
            { name: "streamside", fromPath: "C:\\Code\\streamside", toPath: "P:\\software\\streamside" },
          ],
        },
        handlers,
      ),
    ).rejects.toThrow("copy verification failed for streamside");

    expect(handlers.writeRegistryBatch).not.toHaveBeenCalled();
    expect(handlers.updateChinvexBatch).not.toHaveBeenCalled();
    expect(events).toEqual([
      "rollback-log:start",
      "move:chinvex",
      "move:streamside",
      "rollback:chinvex",
      "rollback-log:result:chinvex:copy verification failed for streamside",
    ]);
  });

  it("rolls back registry if chinvex batch update fails after moves", async () => {
    const handlers = {
      writeRollbackLogStart: vi.fn(async () => undefined),
      executeMove: vi.fn(async () => undefined),
      rollbackMove: vi.fn(async () => undefined),
      writeRollbackLogResult: vi.fn(async () => undefined),
      writeRegistryBatch: vi.fn(async () => undefined),
      restoreRegistryFromBackup: vi.fn(async () => undefined),
      updateChinvexBatch: vi.fn(async () => {
        throw new Error("chinvex context update failed");
      }),
    };

    await expect(
      runConsolidateTransaction(
        {
          plans: [{ name: "chinvex", fromPath: "C:\\Code\\chinvex", toPath: "P:\\software\\chinvex" }],
        },
        handlers,
      ),
    ).rejects.toThrow("chinvex context update failed");

    expect(handlers.writeRegistryBatch).toHaveBeenCalledTimes(1);
    expect(handlers.restoreRegistryFromBackup).toHaveBeenCalledTimes(1);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/transaction.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/transaction'`

**Step 3: Write minimal implementation**
```typescript
type MovePlan = {
  name: string;
  fromPath: string;
  toPath: string;
};

type TransactionHandlers = {
  writeRollbackLogStart: () => Promise<void>;
  executeMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  rollbackMove: (name: string, fromPath: string, toPath: string) => Promise<void>;
  writeRollbackLogResult: (payload: { completed: string[]; failed?: string }) => Promise<void>;
  writeRegistryBatch: () => Promise<void>;
  updateChinvexBatch: () => Promise<void>;
  restoreRegistryFromBackup?: () => Promise<void>;
};

export async function runConsolidateTransaction(
  input: { plans: MovePlan[] },
  handlers: TransactionHandlers,
): Promise<void> {
  const completed: MovePlan[] = [];

  await handlers.writeRollbackLogStart();

  try {
    for (const plan of input.plans) {
      await handlers.executeMove(plan.name, plan.fromPath, plan.toPath);
      completed.push(plan);
    }
  } catch (error) {
    for (let i = completed.length - 1; i >= 0; i -= 1) {
      const done = completed[i];
      await handlers.rollbackMove(done.name, done.fromPath, done.toPath);
    }

    const failed = error instanceof Error ? error.message : "unknown consolidate failure";
    await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name), failed });
    throw error;
  }

  await handlers.writeRegistryBatch();

  try {
    await handlers.updateChinvexBatch();
  } catch (error) {
    if (handlers.restoreRegistryFromBackup) {
      await handlers.restoreRegistryFromBackup();
    }

    const failed = error instanceof Error ? error.message : "unknown chinvex update failure";
    await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name), failed });
    throw error;
  }

  await handlers.writeRollbackLogResult({ completed: completed.map((p) => p.name) });
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/transaction.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/transaction.ts tests/commands/consolidate/transaction.test.ts
git commit -m 'feat: add consolidate transaction rollback on failure'
```

### Task 18: Doctor Trust Modes (Registry-First vs Disk-Discovery)

**Files:**
- Create: src/commands/doctor/trustMode.ts
- Test: tests/commands/doctor/trustMode.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { determineDoctorTrustMode } from "../../../../src/commands/doctor/trustMode";

describe("determineDoctorTrustMode", () => {
  it("uses registry-first by default", () => {
    expect(determineDoctorTrustMode({ fixPaths: false, fixOrphans: false, trustMode: undefined })).toBe("registry-first");
  });

  it("switches to disk-discovery for --fix-paths", () => {
    expect(determineDoctorTrustMode({ fixPaths: true, fixOrphans: false, trustMode: undefined })).toBe("disk-discovery");
  });

  it("rejects mixed trust-mode flags", () => {
    expect(() =>
      determineDoctorTrustMode({ fixPaths: true, fixOrphans: false, trustMode: "registry-first" }),
    ).toThrow("doctor trust-mode conflict: --fix-paths requires disk-discovery and cannot be combined with --trust-mode registry-first");
  });

  it("rejects disk-discovery for non-recovery execution", () => {
    expect(() =>
      determineDoctorTrustMode({ fixPaths: false, fixOrphans: false, trustMode: "disk-discovery" }),
    ).toThrow("doctor disk-discovery mode is only valid with --fix-paths");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/doctor/trustMode.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/doctor/trustMode'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/doctor/trustMode.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/doctor/trustMode.ts tests/commands/doctor/trustMode.test.ts
git commit -m 'feat: enforce doctor trust-mode boundaries'
```

### Task 19: Doctor Conflict Resolution (Comprehensive)

**Files:**
- Create: src/commands/doctor/conflictResolution.ts
- Test: tests/commands/doctor/conflictResolution.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { normalizeRemoteUrl, resolveDoctorPathConflict } from "../../../../src/commands/doctor/conflictResolution";

describe("doctor conflict resolution", () => {
  it("normalizes SSH and HTTPS remotes to the same comparison key", () => {
    expect(normalizeRemoteUrl("git@GitHub.com:Team/Repo.git")).toBe("https://github.com/team/repo");
    expect(normalizeRemoteUrl("https://github.com/team/repo")).toBe("https://github.com/team/repo");
  });

  it("proposes remap when exactly one disk repo matches by normalized remote", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "chinvex",
        registryPath: "C:\\Code\\chinvex",
        registryRemote: "git@github.com:team/chinvex.git",
      },
      diskCandidates: [
        {
          path: "P:\\software\\chinvex",
          remote: "https://github.com/team/chinvex",
        },
      ],
      pathExists: false,
    });

    expect(decision).toEqual({
      kind: "remap",
      toPath: "P:\\software\\chinvex",
      reason: "registry path missing; matched by normalized origin remote",
    });
  });

  it("requires manual selection when multiple matches exist", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "streamside",
        registryPath: "C:\\Code\\streamside",
        registryRemote: "https://github.com/team/streamside.git",
      },
      diskCandidates: [
        { path: "P:\\software\\streamside", remote: "git@github.com:team/streamside.git" },
        { path: "D:\\repos\\streamside", remote: "https://github.com/team/streamside" },
      ],
      pathExists: false,
    });

    expect(decision.kind).toBe("manual-select");
    expect(decision.options).toEqual(["P:\\software\\streamside", "D:\\repos\\streamside"]);
  });

  it("fails when registry path exists but points to a different remote", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "godex",
        registryPath: "C:\\Code\\godex",
        registryRemote: "https://github.com/team/godex",
      },
      diskCandidates: [{ path: "C:\\Code\\godex", remote: "https://github.com/other/fork" }],
      pathExists: true,
    });

    expect(decision).toEqual({
      kind: "fail",
      reason: "registry path occupied by different repo remote; manual resolution required",
    });
  });

  it("does not remap no-remote repos by URL", () => {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: "notes",
        registryPath: "C:\\Code\\notes",
        registryRemote: undefined,
      },
      diskCandidates: [{ path: "P:\\software\\notes", remote: undefined }],
      pathExists: false,
    });

    expect(decision).toEqual({ kind: "orphan", reason: "no registry remote for matching; path-only mode cannot remap" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/doctor/conflictResolution.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/doctor/conflictResolution'`

**Step 3: Write minimal implementation**
```typescript
type RegistryEntry = {
  name: string;
  registryPath: string;
  registryRemote?: string;
};

type DiskCandidate = {
  path: string;
  remote?: string;
};

type ResolveInput = {
  entry: RegistryEntry;
  diskCandidates: DiskCandidate[];
  pathExists: boolean;
};

type ResolveResult =
  | { kind: "healthy" }
  | { kind: "orphan"; reason: string }
  | { kind: "remap"; toPath: string; reason: string }
  | { kind: "manual-select"; options: string[]; reason: string }
  | { kind: "fail"; reason: string };

export function normalizeRemoteUrl(value?: string): string | undefined {
  if (!value) {
    return undefined;
  }

  const trimmed = value.trim();

  const sshMatch = /^git@([^:]+):(.+)$/i.exec(trimmed);
  const asHttps = sshMatch ? `https://${sshMatch[1]}/${sshMatch[2]}` : trimmed;

  const withoutGit = asHttps.replace(/\.git$/i, "");
  const normalizedSlashes = withoutGit.replaceAll("\\", "/");

  try {
    const url = new URL(normalizedSlashes);
    const host = url.host.toLowerCase();
    const pathname = url.pathname.replace(/\/+$/, "").toLowerCase();
    return `${url.protocol}//${host}${pathname}`;
  } catch {
    return normalizedSlashes.toLowerCase();
  }
}

export function resolveDoctorPathConflict(input: ResolveInput): ResolveResult {
  const entryRemote = normalizeRemoteUrl(input.entry.registryRemote);

  if (input.pathExists) {
    const atPath = input.diskCandidates.find((candidate) => candidate.path.toLowerCase() === input.entry.registryPath.toLowerCase());
    if (!atPath) {
      return { kind: "healthy" };
    }

    const diskRemote = normalizeRemoteUrl(atPath.remote);
    if (entryRemote && diskRemote && entryRemote !== diskRemote) {
      return {
        kind: "fail",
        reason: "registry path occupied by different repo remote; manual resolution required",
      };
    }

    return { kind: "healthy" };
  }

  if (!entryRemote) {
    return { kind: "orphan", reason: "no registry remote for matching; path-only mode cannot remap" };
  }

  const matches = input.diskCandidates.filter((candidate) => normalizeRemoteUrl(candidate.remote) === entryRemote);

  if (matches.length === 0) {
    return { kind: "orphan", reason: "registry path missing and no matching remote found on disk" };
  }

  if (matches.length > 1) {
    return {
      kind: "manual-select",
      options: matches.map((candidate) => candidate.path),
      reason: "multiple disk repos match normalized remote; user selection required",
    };
  }

  return {
    kind: "remap",
    toPath: matches[0].path,
    reason: "registry path missing; matched by normalized origin remote",
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/doctor/conflictResolution.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/doctor/conflictResolution.ts tests/commands/doctor/conflictResolution.test.ts
git commit -m 'feat: add comprehensive doctor conflict resolution rules'
```

### Task 20: Doctor --fix-paths Mode

**Files:**
- Create: src/commands/doctor/fixPaths.ts
- Test: tests/commands/doctor/fixPaths.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runDoctorFixPaths } from "../../../../src/commands/doctor/fixPaths";

describe("runDoctorFixPaths", () => {
  it("updates registry path when exactly one remote match exists and confirmation is granted", async () => {
    const updateRegistryPath = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixPaths(
      {
        yes: false,
        entries: [
          {
            id: "chinvex",
            name: "chinvex",
            registryPath: "C:\\Code\\chinvex",
            registryRemote: "git@github.com:team/chinvex.git",
          },
        ],
        discovered: [
          {
            path: "P:\\software\\chinvex",
            remote: "https://github.com/team/chinvex",
          },
        ],
        pathExists: (target) => target.toLowerCase() === "p:\\software\\chinvex",
      },
      { updateRegistryPath, confirm },
    );

    expect(confirm).toHaveBeenCalledTimes(1);
    expect(updateRegistryPath).toHaveBeenCalledWith("chinvex", "P:\\software\\chinvex");
    expect(result.updated).toEqual([{ name: "chinvex", from: "C:\\Code\\chinvex", to: "P:\\software\\chinvex" }]);
    expect(result.unresolved).toEqual([]);
  });

  it("reports unresolved when multiple candidates match and does not auto-update in --yes", async () => {
    const updateRegistryPath = vi.fn(async () => undefined);

    const result = await runDoctorFixPaths(
      {
        yes: true,
        entries: [
          {
            id: "streamside",
            name: "streamside",
            registryPath: "C:\\Code\\streamside",
            registryRemote: "https://github.com/team/streamside",
          },
        ],
        discovered: [
          { path: "P:\\software\\streamside", remote: "git@github.com:team/streamside.git" },
          { path: "D:\\repos\\streamside", remote: "https://github.com/team/streamside.git" },
        ],
        pathExists: () => false,
      },
      {
        updateRegistryPath,
        confirm: async () => true,
      },
    );

    expect(updateRegistryPath).not.toHaveBeenCalled();
    expect(result.unresolved).toEqual([
      {
        name: "streamside",
        reason: "multiple disk repos match normalized remote; user selection required",
      },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/doctor/fixPaths.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/doctor/fixPaths'`

**Step 3: Write minimal implementation**
```typescript
import { resolveDoctorPathConflict } from "./conflictResolution";

type Entry = {
  id: string;
  name: string;
  registryPath: string;
  registryRemote?: string;
};

type DiscoveredRepo = {
  path: string;
  remote?: string;
};

type RunInput = {
  yes: boolean;
  entries: Entry[];
  discovered: DiscoveredRepo[];
  pathExists: (target: string) => boolean;
};

type RunHandlers = {
  updateRegistryPath: (id: string, nextPath: string) => Promise<void>;
  confirm: (message: string) => Promise<boolean>;
};

export async function runDoctorFixPaths(
  input: RunInput,
  handlers: RunHandlers,
): Promise<{ updated: Array<{ name: string; from: string; to: string }>; unresolved: Array<{ name: string; reason: string }> }> {
  const updated: Array<{ name: string; from: string; to: string }> = [];
  const unresolved: Array<{ name: string; reason: string }> = [];

  for (const entry of input.entries) {
    const decision = resolveDoctorPathConflict({
      entry: {
        name: entry.name,
        registryPath: entry.registryPath,
        registryRemote: entry.registryRemote,
      },
      diskCandidates: input.discovered,
      pathExists: input.pathExists(entry.registryPath),
    });

    if (decision.kind === "remap") {
      const shouldApply = input.yes
        ? true
        : await handlers.confirm(`Update registry path for ${entry.name}: ${entry.registryPath} -> ${decision.toPath}?`);

      if (!shouldApply) {
        unresolved.push({ name: entry.name, reason: "user declined registry path update" });
        continue;
      }

      await handlers.updateRegistryPath(entry.id, decision.toPath);
      updated.push({ name: entry.name, from: entry.registryPath, to: decision.toPath });
      continue;
    }

    if (decision.kind === "manual-select" || decision.kind === "orphan" || decision.kind === "fail") {
      unresolved.push({ name: entry.name, reason: decision.reason });
    }
  }

  return { updated, unresolved };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/doctor/fixPaths.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/doctor/fixPaths.ts tests/commands/doctor/fixPaths.test.ts
git commit -m 'feat: add doctor fix-paths recovery mode'
```

### Task 21: Doctor --fix-orphans Mode

**Files:**
- Create: src/commands/doctor/fixOrphans.ts
- Test: tests/commands/doctor/fixOrphans.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runDoctorFixOrphans } from "../../../../src/commands/doctor/fixOrphans";

describe("runDoctorFixOrphans", () => {
  it("removes only missing-path entries when confirmed", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixOrphans(
      {
        yes: false,
        entries: [
          { id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex" },
          { id: "old-experiment", name: "old-experiment", registryPath: "C:\\Code\\old-experiment" },
        ],
        pathExists: (target) => target.toLowerCase() === "c:\\code\\chinvex",
      },
      { removeRegistryEntry, confirm },
    );

    expect(confirm).toHaveBeenCalledTimes(1);
    expect(removeRegistryEntry).toHaveBeenCalledWith("old-experiment");
    expect(result.removed).toEqual([{ name: "old-experiment", path: "C:\\Code\\old-experiment" }]);
    expect(result.skipped).toEqual([]);
  });

  it("auto-removes missing entries with --yes and does not prompt", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);
    const confirm = vi.fn(async () => true);

    const result = await runDoctorFixOrphans(
      {
        yes: true,
        entries: [{ id: "notes", name: "notes", registryPath: "C:\\Code\\notes" }],
        pathExists: () => false,
      },
      { removeRegistryEntry, confirm },
    );

    expect(confirm).not.toHaveBeenCalled();
    expect(removeRegistryEntry).toHaveBeenCalledWith("notes");
    expect(result.removed).toEqual([{ name: "notes", path: "C:\\Code\\notes" }]);
  });

  it("reports skipped entries when user declines removal", async () => {
    const removeRegistryEntry = vi.fn(async () => undefined);

    const result = await runDoctorFixOrphans(
      {
        yes: false,
        entries: [{ id: "legacy", name: "legacy", registryPath: "C:\\Code\\legacy" }],
        pathExists: () => false,
      },
      {
        removeRegistryEntry,
        confirm: async () => false,
      },
    );

    expect(removeRegistryEntry).not.toHaveBeenCalled();
    expect(result.removed).toEqual([]);
    expect(result.skipped).toEqual([
      {
        name: "legacy",
        reason: "user declined orphan removal",
      },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/doctor/fixOrphans.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/doctor/fixOrphans'`

**Step 3: Write minimal implementation**
```typescript
type Entry = {
  id: string;
  name: string;
  registryPath: string;
};

type RunInput = {
  yes: boolean;
  entries: Entry[];
  pathExists: (target: string) => boolean;
};

type RunHandlers = {
  removeRegistryEntry: (id: string) => Promise<void>;
  confirm: (message: string) => Promise<boolean>;
};

export async function runDoctorFixOrphans(
  input: RunInput,
  handlers: RunHandlers,
): Promise<{
  removed: Array<{ name: string; path: string }>;
  skipped: Array<{ name: string; reason: string }>;
}> {
  const removed: Array<{ name: string; path: string }> = [];
  const skipped: Array<{ name: string; reason: string }> = [];

  for (const entry of input.entries) {
    if (input.pathExists(entry.registryPath)) {
      continue;
    }

    const shouldRemove = input.yes
      ? true
      : await handlers.confirm(`Remove orphaned registry entry '${entry.name}' (${entry.registryPath})?`);

    if (!shouldRemove) {
      skipped.push({ name: entry.name, reason: "user declined orphan removal" });
      continue;
    }

    await handlers.removeRegistryEntry(entry.id);
    removed.push({ name: entry.name, path: entry.registryPath });
  }

  return { removed, skipped };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/doctor/fixOrphans.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/doctor/fixOrphans.ts tests/commands/doctor/fixOrphans.test.ts
git commit -m 'feat: add doctor fix-orphans remediation mode'
```

### Task 22: URL Normalization for Remote Matching

**Files:**
- Create: src/git/remoteMatching.ts
- Test: tests/git/remoteMatching.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { normalizeRemoteForMatch, pickComparisonRemote } from "../../../src/git/remoteMatching";

describe("remote matching normalization", () => {
  it("normalizes ssh and https remotes into the same comparison URL", () => {
    expect(normalizeRemoteForMatch("git@GitHub.com:Team/Repo.git")).toBe("https://github.com/Team/Repo");
    expect(normalizeRemoteForMatch("https://github.com/Team/Repo")).toBe("https://github.com/Team/Repo");
  });

  it("strips trailing .git and normalizes repo path separators", () => {
    expect(normalizeRemoteForMatch("https://github.com/team\\repo.git")).toBe("https://github.com/team/repo");
    expect(normalizeRemoteForMatch("https://github.com/team/repo.git/")).toBe("https://github.com/team/repo");
  });

  it("prefers origin remote and falls back to first remote when origin is absent", () => {
    expect(
      pickComparisonRemote([
        { name: "upstream", url: "https://github.com/acme/strap.git" },
        { name: "origin", url: "git@github.com:acme/strap.git" },
      ]),
    ).toBe("https://github.com/acme/strap");

    expect(
      pickComparisonRemote([
        { name: "upstream", url: "https://github.com/acme/strap.git" },
        { name: "backup", url: "https://github.com/acme/strap" },
      ]),
    ).toBe("https://github.com/acme/strap");
  });

  it("returns undefined when no usable remotes exist", () => {
    expect(pickComparisonRemote([])).toBeUndefined();
    expect(pickComparisonRemote([{ name: "origin", url: "   " }])).toBeUndefined();
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/git/remoteMatching.test.ts`
Expected: FAIL with `Cannot find module '../../../src/git/remoteMatching'`

**Step 3: Write minimal implementation**
```typescript
type GitRemote = {
  name: string;
  url: string;
};

export function normalizeRemoteForMatch(remote?: string): string | undefined {
  if (!remote) {
    return undefined;
  }

  const trimmed = remote.trim();
  if (!trimmed) {
    return undefined;
  }

  const sshMatch = /^git@([^:]+):(.+)$/i.exec(trimmed);
  const asHttps = sshMatch ? `https://${sshMatch[1]}/${sshMatch[2]}` : trimmed;

  const slashNormalized = asHttps.replace(/\\/g, "/");
  const withoutTrailingSlash = slashNormalized.replace(/\/+$/, "");
  const withoutGitSuffix = withoutTrailingSlash.replace(/\.git$/i, "");

  try {
    const parsed = new URL(withoutGitSuffix);
    const host = parsed.host.toLowerCase();
    const pathname = parsed.pathname.replace(/\/+$/, "");
    return `${parsed.protocol}//${host}${pathname}`;
  } catch {
    return withoutGitSuffix;
  }
}

export function pickComparisonRemote(remotes: GitRemote[]): string | undefined {
  if (remotes.length === 0) {
    return undefined;
  }

  const preferred = remotes.find((remote) => remote.name.toLowerCase() === "origin") ?? remotes[0];
  return normalizeRemoteForMatch(preferred.url);
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/git/remoteMatching.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/git/remoteMatching.ts tests/git/remoteMatching.test.ts
git commit -m 'feat: normalize git remote URLs for deterministic matching'
```

### Task 23: Configuration Schema Updates

**Files:**
- Create: src/config/schema.ts
- Test: tests/config/schema.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { parseConfig } from "../../../src/config/schema";

describe("parseConfig", () => {
  it("accepts config with archive root and archive threshold", () => {
    const parsed = parseConfig({
      roots: {
        software: "P:\\software",
        tools: "P:\\software\\_scripts",
        shims: "P:\\software\\_scripts\\_bin",
        archive: "P:\\software\\_archive",
      },
      registry: "P:\\software\\_strap\\build\\registry.json",
      archive_threshold_days: 180,
    });

    expect(parsed.roots.archive).toBe("P:\\software\\_archive");
    expect(parsed.archive_threshold_days).toBe(180);
  });

  it("rejects missing archive root", () => {
    expect(() =>
      parseConfig({
        roots: {
          software: "P:\\software",
          tools: "P:\\software\\_scripts",
          shims: "P:\\software\\_scripts\\_bin",
        },
        registry: "P:\\software\\_strap\\build\\registry.json",
        archive_threshold_days: 180,
      }),
    ).toThrow("config.roots.archive is required");
  });

  it("rejects non-positive archive threshold", () => {
    expect(() =>
      parseConfig({
        roots: {
          software: "P:\\software",
          tools: "P:\\software\\_scripts",
          shims: "P:\\software\\_scripts\\_bin",
          archive: "P:\\software\\_archive",
        },
        registry: "P:\\software\\_strap\\build\\registry.json",
        archive_threshold_days: 0,
      }),
    ).toThrow("config.archive_threshold_days must be a positive integer");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/config/schema.test.ts`
Expected: FAIL with `Cannot find module '../../../src/config/schema'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/config/schema.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/config/schema.ts tests/config/schema.test.ts
git commit -m 'feat: enforce config schema with archive root and threshold'
```

### Task 24: Configuration Migration

**Files:**
- Create: src/config/migrateConfig.ts
- Test: tests/config/migrateConfig.test.ts

**Step 1: Write the failing test**
```typescript
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { migrateConfigIfNeeded } from "../../../src/config/migrateConfig";

describe("migrateConfigIfNeeded", () => {
  it("adds roots.archive and archive_threshold_days to legacy config and writes backup", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-config-"));
    const configPath = path.join(root, "config.json");

    await writeFile(
      configPath,
      JSON.stringify(
        {
          roots: {
            software: "P:\\software",
            tools: "P:\\software\\_scripts",
            shims: "P:\\software\\_scripts\\_bin",
          },
          registry: "P:\\software\\_strap\\build\\registry.json",
        },
        null,
        2,
      ),
      "utf8",
    );

    const result = await migrateConfigIfNeeded(configPath);

    expect(result.changed).toBe(true);

    const migrated = JSON.parse(await readFile(configPath, "utf8"));
    expect(migrated.roots.archive).toBe("P:\\software\\_archive");
    expect(migrated.archive_threshold_days).toBe(180);

    const backupPath = path.join(root, "config.pre-archive-migration.backup.json");
    const backup = JSON.parse(await readFile(backupPath, "utf8"));
    expect(backup.archive_threshold_days).toBeUndefined();
  });

  it("is a no-op when config already has required fields", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "strap-config-"));
    const configPath = path.join(root, "config.json");

    await writeFile(
      configPath,
      JSON.stringify(
        {
          roots: {
            software: "P:\\software",
            tools: "P:\\software\\_scripts",
            shims: "P:\\software\\_scripts\\_bin",
            archive: "P:\\software\\_archive",
          },
          registry: "P:\\software\\_strap\\build\\registry.json",
          archive_threshold_days: 180,
        },
        null,
        2,
      ),
      "utf8",
    );

    const result = await migrateConfigIfNeeded(configPath);
    expect(result.changed).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/config/migrateConfig.test.ts`
Expected: FAIL with `Cannot find module '../../../src/config/migrateConfig'`

**Step 3: Write minimal implementation**
```typescript
import { copyFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

type LegacyConfig = {
  roots?: {
    software?: string;
    tools?: string;
    shims?: string;
    archive?: string;
  };
  registry?: string;
  archive_threshold_days?: number;
};

export async function migrateConfigIfNeeded(configPath: string): Promise<{ changed: boolean }> {
  const raw = await readFile(configPath, "utf8");
  const parsed = JSON.parse(raw) as LegacyConfig;

  const hasArchiveRoot = Boolean(parsed.roots?.archive);
  const hasThreshold = Number.isInteger(parsed.archive_threshold_days) && (parsed.archive_threshold_days as number) > 0;

  if (hasArchiveRoot && hasThreshold) {
    return { changed: false };
  }

  const backupPath = path.join(path.dirname(configPath), "config.pre-archive-migration.backup.json");
  await copyFile(configPath, backupPath);

  const softwareRoot = parsed.roots?.software ?? "P:\\software";

  const migrated = {
    ...parsed,
    roots: {
      ...(parsed.roots ?? {}),
      archive: parsed.roots?.archive ?? `${softwareRoot}\\_archive`,
    },
    archive_threshold_days:
      Number.isInteger(parsed.archive_threshold_days) && (parsed.archive_threshold_days as number) > 0
        ? parsed.archive_threshold_days
        : 180,
  };

  await writeFile(configPath, JSON.stringify(migrated, null, 2), "utf8");
  return { changed: true };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/config/migrateConfig.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/config/migrateConfig.ts tests/config/migrateConfig.test.ts
git commit -m 'feat: migrate legacy config with archive root and threshold defaults'
```

### Task 25: Migration Workflow CLI Integration

**Files:**
- Create: src/commands/consolidate/migrationWorkflow.ts
- Test: tests/commands/consolidate/migrationWorkflow.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runConsolidateMigrationWorkflow } from "../../../../src/commands/consolidate/migrationWorkflow";

describe("runConsolidateMigrationWorkflow", () => {
  it("runs config migration + registry upgrade before wizard and finishes with doctor verification", async () => {
    const calls: string[] = [];

    const handlers = {
      migrateConfigIfNeeded: vi.fn(async () => {
        calls.push("config-migrate");
        return { changed: true };
      }),
      readRegistryVersion: vi.fn(async () => {
        calls.push("registry-version");
        return 1;
      }),
      migrateRegistryToV2: vi.fn(async () => {
        calls.push("registry-migrate");
      }),
      runWizardSteps: vi.fn(async () => {
        calls.push("wizard");
      }),
      runDoctor: vi.fn(async () => {
        calls.push("doctor");
        return { ok: true, issues: [] as string[] };
      }),
    };

    const result = await runConsolidateMigrationWorkflow(
      {
        configPath: "P:\\software\\_strap\\config.json",
        registryPath: "P:\\software\\_strap\\build\\registry.json",
        from: "C:\\Code",
        dryRun: false,
      },
      handlers,
    );

    expect(result.registryUpgraded).toBe(true);
    expect(result.doctorIssues).toEqual([]);
    expect(calls).toEqual(["config-migrate", "registry-version", "registry-migrate", "wizard", "doctor"]);
  });

  it("fails fast with upgrade guidance when registry version is newer than supported", async () => {
    await expect(
      runConsolidateMigrationWorkflow(
        {
          configPath: "P:\\software\\_strap\\config.json",
          registryPath: "P:\\software\\_strap\\build\\registry.json",
          from: "C:\\Code",
          dryRun: false,
        },
        {
          migrateConfigIfNeeded: async () => ({ changed: false }),
          readRegistryVersion: async () => 3,
          migrateRegistryToV2: async () => undefined,
          runWizardSteps: async () => undefined,
          runDoctor: async () => ({ ok: true, issues: [] }),
        },
      ),
    ).rejects.toThrow("Registry requires strap version X.Y+, please upgrade");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/consolidate/migrationWorkflow.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/migrationWorkflow'`

**Step 3: Write minimal implementation**
```typescript
type WorkflowInput = {
  configPath: string;
  registryPath: string;
  from: string;
  dryRun: boolean;
};

type WorkflowHandlers = {
  migrateConfigIfNeeded: (configPath: string) => Promise<{ changed: boolean }>;
  readRegistryVersion: (registryPath: string) => Promise<number>;
  migrateRegistryToV2: (registryPath: string, nowIso: string) => Promise<void>;
  runWizardSteps: (input: { from: string; dryRun: boolean }) => Promise<void>;
  runDoctor: (input: { fixPaths: boolean; fixOrphans: boolean }) => Promise<{ ok: boolean; issues: string[] }>;
};

export async function runConsolidateMigrationWorkflow(
  input: WorkflowInput,
  handlers: WorkflowHandlers,
): Promise<{ registryUpgraded: boolean; doctorIssues: string[] }> {
  await handlers.migrateConfigIfNeeded(input.configPath);

  const version = await handlers.readRegistryVersion(input.registryPath);
  let registryUpgraded = false;

  if (version > 2) {
    throw new Error("Registry requires strap version X.Y+, please upgrade");
  }

  if (version === 1) {
    await handlers.migrateRegistryToV2(input.registryPath, new Date().toISOString());
    registryUpgraded = true;
  }

  await handlers.runWizardSteps({ from: input.from, dryRun: input.dryRun });

  if (input.dryRun) {
    return { registryUpgraded, doctorIssues: [] };
  }

  const doctor = await handlers.runDoctor({ fixPaths: false, fixOrphans: false });
  return { registryUpgraded, doctorIssues: doctor.issues };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/consolidate/migrationWorkflow.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/migrationWorkflow.ts tests/commands/consolidate/migrationWorkflow.test.ts
git commit -m 'feat: integrate config and registry migrations into consolidate workflow'
```

### Task 26: Trust Mode Validation Unit Coverage

**Files:**
- Create: src/commands/shared/trustModeValidation.ts
- Test: tests/commands/shared/trustModeValidation.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { validateTrustMode } from "../../../../src/commands/shared/trustModeValidation";

describe("validateTrustMode", () => {
  it("defaults registry-first commands to registry-first mode", () => {
    const result = validateTrustMode({
      command: "consolidate",
      flags: {},
      diskState: { hasPathDrift: false },
    });

    expect(result.mode).toBe("registry-first");
    expect(result.warnings).toEqual([]);
  });

  it("fails registry-first commands when disk path drift is detected", () => {
    expect(() =>
      validateTrustMode({
        command: "archive",
        flags: {},
        diskState: { hasPathDrift: true, driftedEntries: ["chinvex"] },
      }),
    ).toThrow("Registry path drift detected for chinvex. Run 'strap doctor --fix-paths' before retrying.");
  });

  it("allows disk-discovery mode only for doctor --fix-paths and adopt --scan", () => {
    const doctor = validateTrustMode({
      command: "doctor",
      flags: { fixPaths: true },
      diskState: { hasPathDrift: true },
    });
    const adopt = validateTrustMode({
      command: "adopt",
      flags: { scan: true },
      diskState: { hasPathDrift: true },
    });

    expect(doctor.mode).toBe("disk-discovery");
    expect(adopt.mode).toBe("disk-discovery");
  });

  it("rejects mixed trust mode flags", () => {
    expect(() =>
      validateTrustMode({
        command: "doctor",
        flags: { fixPaths: true, forceRegistryFirst: true },
        diskState: { hasPathDrift: true },
      }),
    ).toThrow("Mixed trust mode is not allowed. Use exactly one trust mode per command.");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/commands/shared/trustModeValidation.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/shared/trustModeValidation'`

**Step 3: Write minimal implementation**
```typescript
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
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/commands/shared/trustModeValidation.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/shared/trustModeValidation.ts tests/commands/shared/trustModeValidation.test.ts
git commit -m 'test: add trust mode validation unit coverage'
```

### Task 27: Consolidate Command Integration Tests

**Files:**
- Create: src/commands/consolidate/runConsolidate.ts
- Test: tests/integration/consolidate/runConsolidate.integration.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runConsolidate } from "../../../../src/commands/consolidate/runConsolidate";

describe("runConsolidate integration", () => {
  it("runs wizard steps 1-4 only in dry-run mode", async () => {
    const calls: string[] = [];

    const result = await runConsolidate(
      {
        from: "C:\\Code",
        dryRun: true,
        yes: true,
        stopPm2: false,
        ackScheduledTasks: true,
      },
      {
        snapshot: async () => {
          calls.push("snapshot");
          return { path: "build/consolidate-snapshot.json" };
        },
        discovery: async () => {
          calls.push("discovery");
          return { adopted: [] };
        },
        audit: async () => {
          calls.push("audit");
          return { warnings: [] };
        },
        preflight: async () => {
          calls.push("preflight");
          return { pm2Affected: [], scheduledTaskWarnings: [] };
        },
        promptIdeClosure: async () => {
          calls.push("prompt-ide");
        },
        executeMoves: async () => {
          calls.push("execute");
        },
        runDoctorVerify: async () => {
          calls.push("doctor");
          return { issues: [] };
        },
      },
    );

    expect(calls).toEqual(["snapshot", "discovery", "audit", "preflight"]);
    expect(result.executed).toBe(false);
  });

  it("runs full flow and step-6 doctor verification in execute mode", async () => {
    const calls: string[] = [];

    const result = await runConsolidate(
      {
        from: "C:\\Code",
        dryRun: false,
        yes: false,
        stopPm2: true,
        ackScheduledTasks: true,
      },
      {
        snapshot: async () => {
          calls.push("snapshot");
          return { path: "build/consolidate-snapshot.json" };
        },
        discovery: async () => {
          calls.push("discovery");
          return { adopted: [{ id: "random-thing" }] };
        },
        audit: async () => {
          calls.push("audit");
          return { warnings: ["$PROFILE:12"] };
        },
        preflight: async () => {
          calls.push("preflight");
          return { pm2Affected: ["chinvex-gateway"], scheduledTaskWarnings: [] };
        },
        promptIdeClosure: async () => {
          calls.push("prompt-ide");
        },
        executeMoves: async () => {
          calls.push("execute");
          return { rollbackLogPath: "build/consolidate-rollback-20260201.json" };
        },
        runDoctorVerify: async () => {
          calls.push("doctor");
          return { issues: ["Update scheduled task MorningBrief path"] };
        },
      },
    );

    expect(calls).toEqual(["snapshot", "discovery", "audit", "preflight", "prompt-ide", "execute", "doctor"]);
    expect(result.executed).toBe(true);
    expect(result.manualFixes).toEqual(["Update scheduled task MorningBrief path"]);
  });

  it("blocks when scheduled-task warnings exist without acknowledgement", async () => {
    await expect(
      runConsolidate(
        {
          from: "C:\\Code",
          dryRun: false,
          yes: true,
          stopPm2: false,
          ackScheduledTasks: false,
        },
        {
          snapshot: async () => ({ path: "build/snapshot.json" }),
          discovery: async () => ({ adopted: [] }),
          audit: async () => ({ warnings: [] }),
          preflight: async () => ({ pm2Affected: [], scheduledTaskWarnings: ["MorningBrief"] }),
          promptIdeClosure: async () => undefined,
          executeMoves: async () => ({ rollbackLogPath: "build/rollback.json" }),
          runDoctorVerify: async () => ({ issues: [] }),
        },
      ),
    ).rejects.toThrow("Scheduled task references detected. Re-run with --ack-scheduled-tasks to continue.");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/integration/consolidate/runConsolidate.integration.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/runConsolidate'`

**Step 3: Write minimal implementation**
```typescript
type ConsolidateInput = {
  from: string;
  dryRun: boolean;
  yes: boolean;
  stopPm2: boolean;
  ackScheduledTasks: boolean;
};

type ConsolidateHandlers = {
  snapshot: (input: { from: string }) => Promise<{ path: string }>;
  discovery: (input: { from: string; yes: boolean }) => Promise<{ adopted: Array<{ id: string }> }>;
  audit: (input: { from: string }) => Promise<{ warnings: string[] }>;
  preflight: (input: { from: string; stopPm2: boolean }) => Promise<{
    pm2Affected: string[];
    scheduledTaskWarnings: string[];
  }>;
  promptIdeClosure: () => Promise<void>;
  executeMoves: (input: { from: string; stopPm2: boolean }) => Promise<{ rollbackLogPath: string }>;
  runDoctorVerify: () => Promise<{ issues: string[] }>;
};

export async function runConsolidate(
  input: ConsolidateInput,
  handlers: ConsolidateHandlers,
): Promise<{ executed: boolean; manualFixes: string[] }> {
  await handlers.snapshot({ from: input.from });
  await handlers.discovery({ from: input.from, yes: input.yes });
  await handlers.audit({ from: input.from });

  const preflight = await handlers.preflight({ from: input.from, stopPm2: input.stopPm2 });
  if (preflight.scheduledTaskWarnings.length > 0 && !input.ackScheduledTasks) {
    throw new Error("Scheduled task references detected. Re-run with --ack-scheduled-tasks to continue.");
  }

  if (input.dryRun) {
    return { executed: false, manualFixes: [] };
  }

  if (!input.yes) {
    await handlers.promptIdeClosure();
  }

  await handlers.executeMoves({ from: input.from, stopPm2: input.stopPm2 });
  const doctor = await handlers.runDoctorVerify();

  return {
    executed: true,
    manualFixes: doctor.issues,
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/integration/consolidate/runConsolidate.integration.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/runConsolidate.ts tests/integration/consolidate/runConsolidate.integration.test.ts
git commit -m 'test: cover consolidate integration flow and gating checks'
```

### Task 28: Doctor Command Integration Tests

**Files:**
- Create: src/commands/doctor/runDoctorCommand.ts
- Test: tests/integration/doctor/runDoctorCommand.integration.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runDoctorCommand } from "../../../../src/commands/doctor/runDoctorCommand";

describe("runDoctorCommand integration", () => {
  it("reports drift by default without mutating registry", async () => {
    const updatePath = vi.fn(async () => undefined);
    const removeEntry = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: false,
        fixOrphans: false,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [{ id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex", diskPath: "P:\\software\\chinvex" }],
          orphans: [{ id: "old", name: "old", registryPath: "C:\\Code\\old" }],
        }),
        updateRegistryPath: updatePath,
        removeRegistryEntry: removeEntry,
      },
    );

    expect(result.issues).toHaveLength(2);
    expect(updatePath).not.toHaveBeenCalled();
    expect(removeEntry).not.toHaveBeenCalled();
  });

  it("applies --fix-paths updates for remote-matched drifted entries", async () => {
    const updatePath = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: true,
        fixOrphans: false,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [{ id: "chinvex", name: "chinvex", registryPath: "C:\\Code\\chinvex", diskPath: "P:\\software\\chinvex" }],
          orphans: [],
        }),
        updateRegistryPath: updatePath,
        removeRegistryEntry: async () => undefined,
      },
    );

    expect(updatePath).toHaveBeenCalledWith("chinvex", "P:\\software\\chinvex");
    expect(result.fixesApplied).toEqual(["path:chinvex"]);
  });

  it("applies --fix-orphans removals for missing registry entries", async () => {
    const removeEntry = vi.fn(async () => undefined);

    const result = await runDoctorCommand(
      {
        fixPaths: false,
        fixOrphans: true,
      },
      {
        scanRegistryVsDisk: async () => ({
          drifted: [],
          orphans: [{ id: "old", name: "old", registryPath: "C:\\Code\\old" }],
        }),
        updateRegistryPath: async () => undefined,
        removeRegistryEntry: removeEntry,
      },
    );

    expect(removeEntry).toHaveBeenCalledWith("old");
    expect(result.fixesApplied).toEqual(["orphan:old"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/integration/doctor/runDoctorCommand.integration.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/doctor/runDoctorCommand'`

**Step 3: Write minimal implementation**
```typescript
type DriftedEntry = {
  id: string;
  name: string;
  registryPath: string;
  diskPath: string;
};

type OrphanEntry = {
  id: string;
  name: string;
  registryPath: string;
};

type DoctorInput = {
  fixPaths: boolean;
  fixOrphans: boolean;
};

type DoctorHandlers = {
  scanRegistryVsDisk: () => Promise<{
    drifted: DriftedEntry[];
    orphans: OrphanEntry[];
  }>;
  updateRegistryPath: (id: string, nextPath: string) => Promise<void>;
  removeRegistryEntry: (id: string) => Promise<void>;
};

export async function runDoctorCommand(
  input: DoctorInput,
  handlers: DoctorHandlers,
): Promise<{ issues: string[]; fixesApplied: string[] }> {
  const fixesApplied: string[] = [];
  const issues: string[] = [];

  const findings = await handlers.scanRegistryVsDisk();

  for (const drift of findings.drifted) {
    issues.push(`Path drift: ${drift.name} registry=${drift.registryPath} disk=${drift.diskPath}`);
    if (input.fixPaths) {
      await handlers.updateRegistryPath(drift.id, drift.diskPath);
      fixesApplied.push(`path:${drift.id}`);
    }
  }

  for (const orphan of findings.orphans) {
    issues.push(`Orphaned entry: ${orphan.name} at ${orphan.registryPath}`);
    if (input.fixOrphans) {
      await handlers.removeRegistryEntry(orphan.id);
      fixesApplied.push(`orphan:${orphan.id}`);
    }
  }

  return { issues, fixesApplied };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/integration/doctor/runDoctorCommand.integration.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/doctor/runDoctorCommand.ts tests/integration/doctor/runDoctorCommand.integration.test.ts
git commit -m 'test: add doctor integration coverage for fix paths and orphans'
```

### Task 29: Consolidate Edge Case Guards (Conflicts + Errors)

**Files:**
- Create: src/commands/consolidate/edgeCaseGuards.ts
- Test: tests/integration/consolidate/edgeCaseGuards.integration.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it, vi } from "vitest";
import { runEdgeCaseGuards } from "../../../../src/commands/consolidate/edgeCaseGuards";

describe("runEdgeCaseGuards", () => {
  it("fails fast on adoption ID collisions in --yes mode", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: true,
          proposedAdoptions: [
            { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
            { sourcePath: "C:\\Code\\repo", proposedId: "repo" },
          ],
          destinationPaths: [],
          existingLock: null,
        },
        {
          isPidRunning: async () => false,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Adoption ID collision detected for 'repo' in --yes mode.");
  });

  it("fails on case-insensitive destination collisions", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: false,
          proposedAdoptions: [],
          destinationPaths: ["P:\\software\\Repo", "P:\\software\\repo"],
          existingLock: null,
        },
        {
          isPidRunning: async () => false,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Destination path collision detected: P:\\software\\Repo <-> P:\\software\\repo");
  });

  it("fails when lock file belongs to a running process", async () => {
    await expect(
      runEdgeCaseGuards(
        {
          yes: false,
          proposedAdoptions: [],
          destinationPaths: [],
          existingLock: { pid: 4242, path: "build/.consolidate.lock" },
        },
        {
          isPidRunning: async () => true,
          removeStaleLock: async () => undefined,
          resolveCollisionInteractively: async () => "repo-2",
        },
      ),
    ).rejects.toThrow("Another consolidation in progress (PID 4242)");
  });

  it("removes stale lock and resolves collision interactively", async () => {
    const removeStaleLock = vi.fn(async () => undefined);

    const result = await runEdgeCaseGuards(
      {
        yes: false,
        proposedAdoptions: [
          { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
          { sourcePath: "C:\\Code\\repo", proposedId: "repo" },
        ],
        destinationPaths: [],
        existingLock: { pid: 7777, path: "build/.consolidate.lock" },
      },
      {
        isPidRunning: async () => false,
        removeStaleLock,
        resolveCollisionInteractively: async () => "repo-2",
      },
    );

    expect(removeStaleLock).toHaveBeenCalledWith("build/.consolidate.lock");
    expect(result.resolvedAdoptions).toEqual([
      { sourcePath: "C:\\Code\\Repo", proposedId: "repo" },
      { sourcePath: "C:\\Code\\repo", proposedId: "repo-2" },
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/integration/consolidate/edgeCaseGuards.integration.test.ts`
Expected: FAIL with `Cannot find module '../../../../src/commands/consolidate/edgeCaseGuards'`

**Step 3: Write minimal implementation**
```typescript
type ProposedAdoption = {
  sourcePath: string;
  proposedId: string;
};

type ExistingLock = {
  pid: number;
  path: string;
};

type EdgeGuardInput = {
  yes: boolean;
  proposedAdoptions: ProposedAdoption[];
  destinationPaths: string[];
  existingLock: ExistingLock | null;
};

type EdgeGuardHandlers = {
  isPidRunning: (pid: number) => Promise<boolean>;
  removeStaleLock: (lockPath: string) => Promise<void>;
  resolveCollisionInteractively: (collidingId: string, sourcePath: string) => Promise<string>;
};

function findDestinationCollision(paths: string[]): string | undefined {
  const seen = new Map<string, string>();
  for (const path of paths) {
    const key = path.toLowerCase();
    const existing = seen.get(key);
    if (existing && existing !== path) {
      return `${existing} <-> ${path}`;
    }
    seen.set(key, path);
  }
  return undefined;
}

export async function runEdgeCaseGuards(
  input: EdgeGuardInput,
  handlers: EdgeGuardHandlers,
): Promise<{ resolvedAdoptions: ProposedAdoption[] }> {
  if (input.existingLock) {
    const running = await handlers.isPidRunning(input.existingLock.pid);
    if (running) {
      throw new Error(`Another consolidation in progress (PID ${input.existingLock.pid})`);
    }
    await handlers.removeStaleLock(input.existingLock.path);
  }

  const collision = findDestinationCollision(input.destinationPaths);
  if (collision) {
    throw new Error(`Destination path collision detected: ${collision}`);
  }

  const seenIds = new Set<string>();
  const resolved: ProposedAdoption[] = [];

  for (const item of input.proposedAdoptions) {
    const key = item.proposedId.toLowerCase();
    if (!seenIds.has(key)) {
      seenIds.add(key);
      resolved.push(item);
      continue;
    }

    if (input.yes) {
      throw new Error(`Adoption ID collision detected for '${item.proposedId}' in --yes mode.`);
    }

    const nextId = await handlers.resolveCollisionInteractively(item.proposedId, item.sourcePath);
    seenIds.add(nextId.toLowerCase());
    resolved.push({ ...item, proposedId: nextId });
  }

  return { resolvedAdoptions: resolved };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/integration/consolidate/edgeCaseGuards.integration.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/commands/consolidate/edgeCaseGuards.ts tests/integration/consolidate/edgeCaseGuards.integration.test.ts
git commit -m 'test: add consolidate edge-case guards for lock and collision failures'
```

### Task 30: End-to-End Migration Workflow Validation

**Files:**
- Create: src/e2e/validateMigrationWorkflow.ts
- Test: tests/e2e/devEnvironmentMigrationWorkflow.e2e.test.ts

**Step 1: Write the failing test**
```typescript
import { describe, expect, it } from "vitest";
import { validateMigrationWorkflow } from "../../../src/e2e/validateMigrationWorkflow";

describe("validateMigrationWorkflow", () => {
  it("validates dry-run then execute workflow with post-move doctor checks", async () => {
    const events: string[] = [];

    const result = await validateMigrationWorkflow(
      {
        source: "C:\\Code",
        destinationRoot: "P:\\software",
      },
      {
        runConsolidate: async (args) => {
          events.push(args.dryRun ? "consolidate:dry-run" : "consolidate:execute");
          if (args.dryRun) {
            return { executed: false, manualFixes: [] };
          }
          return {
            executed: true,
            manualFixes: ["Update $PROFILE alias path", "Update scheduled task MorningBrief"],
          };
        },
        verifySourceEmpty: async () => {
          events.push("verify:source-empty");
          return true;
        },
        verifyRegistryPathsUnderDestination: async () => {
          events.push("verify:registry-destination");
          return true;
        },
        verifyDoctorClean: async () => {
          events.push("verify:doctor");
          return { ok: true, issues: [] };
        },
      },
    );

    expect(events).toEqual([
      "consolidate:dry-run",
      "consolidate:execute",
      "verify:source-empty",
      "verify:registry-destination",
      "verify:doctor",
    ]);
    expect(result.ok).toBe(true);
    expect(result.manualFixes).toEqual([
      "Update $PROFILE alias path",
      "Update scheduled task MorningBrief",
    ]);
  });

  it("fails when post-move doctor still reports blocking issues", async () => {
    await expect(
      validateMigrationWorkflow(
        {
          source: "C:\\Code",
          destinationRoot: "P:\\software",
        },
        {
          runConsolidate: async ({ dryRun }) => ({ executed: !dryRun, manualFixes: [] }),
          verifySourceEmpty: async () => true,
          verifyRegistryPathsUnderDestination: async () => true,
          verifyDoctorClean: async () => ({ ok: false, issues: ["Registry entry missing path for streamside"] }),
        },
      ),
    ).rejects.toThrow("End-to-end validation failed: Registry entry missing path for streamside");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `pnpm vitest run tests/e2e/devEnvironmentMigrationWorkflow.e2e.test.ts`
Expected: FAIL with `Cannot find module '../../../src/e2e/validateMigrationWorkflow'`

**Step 3: Write minimal implementation**
```typescript
type WorkflowInput = {
  source: string;
  destinationRoot: string;
};

type WorkflowHandlers = {
  runConsolidate: (args: {
    from: string;
    to: string;
    dryRun: boolean;
    yes: boolean;
    stopPm2: boolean;
    ackScheduledTasks: boolean;
  }) => Promise<{ executed: boolean; manualFixes: string[] }>;
  verifySourceEmpty: (source: string) => Promise<boolean>;
  verifyRegistryPathsUnderDestination: (destinationRoot: string) => Promise<boolean>;
  verifyDoctorClean: () => Promise<{ ok: boolean; issues: string[] }>;
};

export async function validateMigrationWorkflow(
  input: WorkflowInput,
  handlers: WorkflowHandlers,
): Promise<{ ok: boolean; manualFixes: string[] }> {
  await handlers.runConsolidate({
    from: input.source,
    to: input.destinationRoot,
    dryRun: true,
    yes: true,
    stopPm2: false,
    ackScheduledTasks: true,
  });

  const executed = await handlers.runConsolidate({
    from: input.source,
    to: input.destinationRoot,
    dryRun: false,
    yes: true,
    stopPm2: true,
    ackScheduledTasks: true,
  });

  const sourceEmpty = await handlers.verifySourceEmpty(input.source);
  if (!sourceEmpty) {
    throw new Error(`End-to-end validation failed: source directory not empty (${input.source})`);
  }

  const registryOk = await handlers.verifyRegistryPathsUnderDestination(input.destinationRoot);
  if (!registryOk) {
    throw new Error(`End-to-end validation failed: registry paths not rooted at ${input.destinationRoot}`);
  }

  const doctor = await handlers.verifyDoctorClean();
  if (!doctor.ok) {
    throw new Error(`End-to-end validation failed: ${doctor.issues[0] ?? "unknown doctor issue"}`);
  }

  return {
    ok: true,
    manualFixes: executed.manualFixes,
  };
}
```

**Step 4: Run test to verify it passes**
Run: `pnpm vitest run tests/e2e/devEnvironmentMigrationWorkflow.e2e.test.ts`
Expected: PASS

**Step 5: Commit**
```bash
git add src/e2e/validateMigrationWorkflow.ts tests/e2e/devEnvironmentMigrationWorkflow.e2e.test.ts
git commit -m 'test: add end-to-end migration workflow validation harness'
```
