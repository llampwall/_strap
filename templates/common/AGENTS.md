# Agents

Repo: {{REPO_NAME}}

## Guardrails
- Keep changes small and reviewable.
- Put automation in `scripts/` or `tools/`.

## No Python Replace for Newlines
Do not use ad‑hoc Python/regex replacements to edit files. For multiline/escape edits: show the 10–30 line snippet, edit directly, then re‑show the snippet (or `rg`) to verify.
LF is standard; CRLF only for .bat/.cmd.