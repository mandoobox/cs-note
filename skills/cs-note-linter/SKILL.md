---
name: cs-note-linter
description: Lint and normalize markdown notes in a CS study repository. Use when handling `.md` notes and tasks like checking frontmatter completeness, fixing tag consistency, finding broken local links, validating section numbering, and spotting mojibake indicators, or when the user asks to clean up note quality.
---

# Cs Note Linter

## Overview

Run deterministic checks for CS note quality before publishing, interview prep, or study export.

## Workflow

1. Discover note files with `Get-ChildItem -Recurse -Filter *.md` and exclude `skills/**`.
2. Run one of:
- `scripts/lint-cs-notes.ps1 -Root <repo-root>` (PowerShell)
- `node scripts/lint-cs-notes.mjs --root <repo-root>` (cross-platform)
- `scripts/lint-cs-notes.sh --root <repo-root>` (bash wrapper)
- `scripts/lint-cs-notes.cmd --root <repo-root>` (cmd wrapper)
to collect issues.
3. Sort findings by severity:
- `ERROR`: structural problems that can break parsing.
- `WARN`: consistency or quality issues that should be fixed.
- `INFO`: optional improvements.
4. Apply safe fixes with one of:
- `scripts/lint-cs-notes.ps1 -Root <repo-root> -Fix`
- `node scripts/lint-cs-notes.mjs --root <repo-root> --fix`
5. Re-run lint and report delta plus remaining issues.

## Built-in Checks

- Verify YAML frontmatter boundaries and required keys (`title`, `date`, `category`, `tags`) when frontmatter exists.
- Detect known tag typo `datsstructure` and normalize to `datastructure` in fix mode.
- Detect missing local markdown link targets.
- Detect `## N.` numbering drift across second-level sections.
- Detect mojibake indicators (`U+FFFD`) and control characters.

## Output Contract

- Emit one issue per line in this format: `[SEVERITY] rule path:line - message`.
- Emit non-zero exit code when any issue exists.
- Emit `2` when at least one `ERROR` exists.
- Write JSON report when `-JsonOut` is provided.

## Guardrails

- Limit auto-fix to deterministic edits.
- Preserve semantic content and section order.
- Review diff after fix mode before additional content edits.
