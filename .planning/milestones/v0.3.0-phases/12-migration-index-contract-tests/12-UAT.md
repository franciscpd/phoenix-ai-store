---
status: complete
phase: 12-migration-index-contract-tests
source: [ROADMAP.md success criteria, 12-PLAN.md]
started: 2026-04-07T00:30:00Z
updated: 2026-04-07T00:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cost template includes cursor index
expected: cost_migration.exs.eex contains create index for [:recorded_at, :id] with cursor_idx name
result: pass

### 2. Upgrade template exists with create_if_not_exists
expected: upgrade_v030_migration.exs.eex uses create_if_not_exists for idempotent upgrades
result: pass

### 3. --upgrade flag generates migration
expected: mix phoenix_ai_store.gen.migration --upgrade creates upgrade file with correct content
result: pass

### 4. --upgrade is idempotent
expected: Running --upgrade twice does not create duplicate file, shows "already exists" message
result: pass

### 5. All migration tests pass
expected: 7/7 migration tests pass (4 existing + 3 new upgrade tests)
result: pass

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
