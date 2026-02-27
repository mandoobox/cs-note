---
name: cs-note-interview-kit
description: Build structured CS interview practice sets from markdown notes. Use when the user asks for mock interview questions, model answer outlines, follow-up drill questions, or section-based interview prep from files like DataStructure.md, OS.md, Network.md, and Database.md.
---

# Cs Note Interview Kit

## Overview

Generate repeatable interview packs from markdown notes, then adapt depth by role and time budget.

## Workflow

1. Select target files by topic (`DataStructure`, `OS`, `Network`, `Database`) and role level.
2. Run one of:
- `scripts/build-interview-kit.ps1 -Root <repo-root> -Topics <topic-list>` (PowerShell)
- `node scripts/build-interview-kit.mjs --root <repo-root> --topics <topic-list>` (cross-platform)
- `scripts/build-interview-kit.sh --root <repo-root> --topics <topic-list>` (bash wrapper)
- `scripts/build-interview-kit.cmd --root <repo-root> --topics <topic-list>` (cmd wrapper)
3. Use generated JSON pack as the deterministic base.
4. Refine each question with:
- expected depth,
- follow-up chain,
- scoring rubric,
- common pitfalls.
5. Deliver final set as mock interview or study checklist.

## Question Mix Rules

- Include conceptual explanation prompts.
- Include comparison/tradeoff prompts.
- Include debugging or system-design scenario prompts.
- Include one fast recall checkpoint after every 3-4 deep questions.
- Keep each prompt single-intent and measurable.

## Grading Rules

- Score with four dimensions: correctness, reasoning depth, tradeoff awareness, communication clarity.
- Mark hard fail for confident but incorrect core claims.
- Flag partial credit when reasoning is valid but key constraints are omitted.
- Attach one concrete improvement action per wrong answer.

## Output Contract

- Generate machine-readable JSON first.
- Keep one entry per source section.
- Keep `question_type`, `difficulty`, `prompt`, `follow_up`, `rubric`, and `source` for each question.
- Regenerate deterministically before manual enrichment.
