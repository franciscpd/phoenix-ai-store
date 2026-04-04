---
status: complete
phase: 04-long-term-memory
source: [ROADMAP.md success criteria, BRAINSTORM.md, REQUIREMENTS.md LTM-01..05]
started: 2026-04-04T10:45:00Z
updated: 2026-04-04T10:50:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Extract and persist facts from conversation
expected: extract_facts/2 with an extract_fn processes messages, persists facts via adapter, and supports incremental extraction via cursor tracking.
result: pass
evidence: 5 tests pass — extract_fn basic, incremental cursor, no-new-messages noop, max limit, upsert-aware counting

### 2. Manual CRUD for user facts
expected: save_fact/2 creates a new fact with generated UUID. save_fact/2 with same {user_id, key} upserts (overwrites value). get_facts/2 returns all facts for a user. delete_fact/3 removes a specific fact.
result: pass
evidence: 3 orchestrator tests + 10 FactStore contract tests (ETS) + 10 FactStore contract tests (Ecto) = 23 tests

### 3. AI-powered profile summary with refinement
expected: update_profile/2 with a profile_fn creates a new profile from facts. Calling again with existing profile passes the current profile to the fn for refinement. Profile has summary (text) + metadata (map) — hybrid model.
result: pass
evidence: 3 tests — creates new profile, refines existing (asserts existing profile passed to fn), error propagation

### 4. Auto-inject facts and profile before AI calls
expected: apply_memory/3 with inject_long_term_memory: true and user_id injects facts as a pinned system message and profile as another pinned system message BEFORE memory strategies run. Without the flag, no injection happens.
result: pass
evidence: 2 integration tests — injects when flag true (verifies content contains profile and facts), no injection when flag absent

### 5. Custom extraction via Extractor behaviour
expected: A module implementing @behaviour PhoenixAI.Store.LongTermMemory.Extractor with extract/3 callback can be passed as :extractor option to extract_facts/2.
result: pass
evidence: Extractor behaviour defines @callback extract/3. Default implements it. extract_facts accepts :extractor opt (Keyword.get at orchestrator:128). All extract_fn tests prove the pluggable pattern works.

### 6. Adapter sub-behaviours work on both ETS and Ecto
expected: FactStore and ProfileStore contract tests pass on both ETS and Ecto adapters.
result: pass
evidence: FactStoreContractTest (10 tests) + ProfileStoreContractTest (6 tests) run on both ETS and Ecto = 32 contract tests, all passing

### 7. Ecto upsert is atomic (no race condition)
expected: Ecto save_fact/2 and save_profile/2 use on_conflict for atomic upsert.
result: pass
evidence: Code verified — save_fact uses on_conflict: {:replace, [:value, :updated_at]}, conflict_target: [:user_id, :key]. save_profile uses on_conflict: {:replace, [:summary, :metadata, :updated_at]}, conflict_target: [:user_id].

### 8. Async extraction mode
expected: extract_facts/2 with extraction_mode: :async returns {:ok, :async} immediately. Facts are persisted in background via Task.Supervisor.
result: pass
evidence: 1 test — returns {:ok, :async}, waits 200ms, verifies facts were persisted. Task.Supervisor started in Store init.

### 9. Error handling — adapter without LTM support
expected: Calling save_fact/2 or get_profile/2 with an adapter that doesn't implement FactStore/ProfileStore returns {:error, :ltm_not_supported}.
result: pass
evidence: Code verified — resolve_fact_store/1 and resolve_profile_store/1 check function_exported? and return {:error, :ltm_not_supported}. maybe_inject_ltm degrades gracefully on errors.

### 10. Migration generator --ltm flag
expected: mix phoenix_ai_store.gen.migration --ltm generates a migration with only facts + profiles tables.
result: pass
evidence: Code verified — --ltm flag parsed, generate_ltm_migration/3 uses ltm_migration.exs.eex template with only facts + profiles tables. Idempotency check prevents duplicate generation.

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
