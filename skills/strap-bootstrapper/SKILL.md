---
name: strap-bootstrapper
description: "Bootstrap and template repos using the strap tool. Use when a user wants to create a new repo/app/tool/API/CLI, bootstrap/scaffold/init a project, or snapshot a repo into a template. Infer the correct strap template from intent (UI+backend=mono, backend-only=node-ts-service, frontend-only=node-ts-web, python tooling=python). Use strap templatize when a user wants to turn an existing repo into a template."
---

# Strap Bootstrapper

Use this skill to infer which strap template to use and run strap commands. Trigger on intent, not keywords; do not require the user to say “strap”.

## Template inference rubric

Choose **mono** when the request implies BOTH UI + backend, or "an app":
- web app, dashboard, PWA, UI, admin panel
- endpoints + UI pages
- phone UI or control panel
- anything like codex-relay (sessions list + buttons + streaming output)

Choose **node-ts-service** when backend-only:
- API, service, webhook, worker, cron, SSE, queue, run command, process files
- no UI or pages

Choose **node-ts-web** when frontend-only:
- landing page, marketing site, static site, portfolio
- no DB, no server, no auth/backend requirements
- integrates with an existing API elsewhere

Choose **python** when it's a python tool/script/automation:
- CLI, script, pipeline, notebook, ETL, parse, scrape, automation
- mentions pip/pytest/pyproject or python libs

## Tie-breakers

1. Phone UI or web UI → **mono**
2. Streaming output / run commands, no UI → **node-ts-service**
3. "Quick tool" → **python** unless web is implied
4. Uncertain service vs mono → **mono**

## Fallback

If constraints explicitly require another stack (Rust/Go/Flutter/Unity/etc.):
- Say: "No matching template found. Create empty repo?"
- Then: mkdir + cd + git init
- Offer: "If you want to templatize later, let me know"

## Commands

### Bootstrap

- `strap <name> -t <template> [-p <path>] [--install|--start|--skip-install]`
- Default path is `P:\software` unless user says otherwise

### Templatize

When the user wants to create a template from an existing repo:
- `strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]`
- Templatize is a filtered copy and does not modify the source repo.

### Doctor

Run after strap or template changes (including moves/renames), or when asked "did I break strap?":
- `strap doctor` (add `--keep` only if asked)

## Notes

- Prefer deterministic actions and clear status output.
- Do not modify repo contents beyond what strap does unless explicitly asked.