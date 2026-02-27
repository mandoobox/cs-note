---
name: cs-note-mermaid-validator
description: Validate Mermaid diagram blocks in markdown notes and report render-risk syntax issues. Use when a user says Mermaid diagrams are broken, asks to check diagram syntax, requests cleanup of Mermaid blocks, or before publishing markdown with many ` ```mermaid ` fences.
---

# Cs Note Mermaid Validator

## Overview

Detect render-risk Mermaid issues early and apply only deterministic whitespace-level fixes.

## Workflow

1. Collect markdown files and exclude `skills/**`.
2. Run one of:
- `scripts/validate-mermaid.ps1 -Root <repo-root>` (PowerShell)
- `node scripts/validate-mermaid.mjs --root <repo-root>` (cross-platform)
- `scripts/validate-mermaid.sh --root <repo-root>` (bash wrapper)
- `scripts/validate-mermaid.cmd --root <repo-root>` (cmd wrapper)
for diagnostics.
3. Prioritize `ERROR` items first, then `WARN`.
4. Apply safe formatting fixes with `-AutoFix` only when requested.
5. Re-run validator and report remaining items.

## Checks

- Detect unclosed Mermaid fences.
- Detect empty Mermaid blocks.
- Validate first diagram declaration token.
- Detect tab characters in Mermaid blocks.
- Detect likely bracket imbalance `()`, `[]`, `{}`.
- Detect odd count of unescaped double quotes.
- Detect `subgraph` and `end` count mismatch.

## Auto-Fix Scope

- Replace tabs with spaces inside Mermaid blocks.
- Trim trailing whitespace in Mermaid block lines.
- Leave semantic lines unchanged.

## Output Contract

- Emit one issue per line in this format: `[SEVERITY] rule path:blockStart:line - message`.
- Emit JSON when `-JsonOut` is set.
- Return exit code `2` when `ERROR` exists, `1` when only `WARN/INFO` exists, and `0` when clean.
