# AGENTS.md

This file defines default Codex behavior for this repository.
Scope: entire repo.

## Primary Goal

Maintain a practical, patch-based NetBird + AmneziaWG fork with minimal risk and minimal logic churn.

## Working Style

1. Keep changes minimal and targeted. Do not refactor unrelated code.
2. Prefer the smallest fix that solves the reported issue.
3. Preserve existing behavior unless the task explicitly requires behavior changes.
4. Keep backward compatibility in mind (older clients/older OSes) when possible.

## Patch-First Workflow

1. Source of truth is under `workdir/repos/*`.
2. Persist distributable changes in patch files under `patches/`.
3. After edits, ensure patches still apply cleanly.
4. If patch application is broken, fix patch integrity first (do not leave corrupt hunks).

## Validation Policy

1. By default, do not run full test suites.
2. Run tests only when explicitly requested.
3. Always run lightweight patch validation when changing patched sources:
   - `./scripts/prepare_sources.sh`
   - or `git apply --check` for touched patch files.

## Communication

1. Be concise and concrete.
2. Explain what changed and why.
3. If something cannot be verified locally, state that explicitly.
