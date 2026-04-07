# Phase 12: Migration Index & Contract Tests - Context

**Gathered:** 2026-04-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Add composite `(recorded_at, id)` index to cost_records table for efficient cursor pagination. Provide an upgrade path for existing projects. Verify contract test coverage is complete.

</domain>

<decisions>
## Implementation Decisions

### Migration Strategy
- **D-01:** Update the existing cost migration template (`priv/templates/cost_migration.exs.eex`) to include `create index(:cost_records, [:recorded_at, :id])` — new projects get it automatically.
- **D-02:** Add an `--upgrade` flag to `mix phoenix_ai_store.gen.migration` that generates only additive index migrations for projects that already ran the initial migration. This generates a separate migration file with just the new cursor index.
- **D-03:** Document the upgrade path in CHANGELOG under v0.3.0.

### Contract Tests
- **D-04:** Contract tests were already updated in Phase 11 (Task 7) with 14 list_cost_records tests + 2 count_cost_records tests covering all filter combinations, cursor pagination, and error handling. Verify MIGR-02 is satisfied — if gaps exist, add missing tests.

### Claude's Discretion
- Naming convention for the upgrade migration template file
- Whether `--upgrade` generates just the cost cursor index or all missing indexes across all tables
- Test organization for migration generator tests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Migration Template
- `priv/templates/cost_migration.exs.eex` — Current migration template (add index here)
- `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` — Mix task (add --upgrade flag here)

### Existing Patterns
- `priv/templates/cost_migration.exs.eex` lines 24-27 — Existing index creation pattern
- The events table already has `[:inserted_at]` index — cost_records cursor index follows same pattern

### Phase 11 Context
- `.planning/phases/11-coststore-query-api/11-CONTEXT.md` — Cursor design decisions
- `test/support/cost_store_contract_test.ex` — Updated contract tests from Phase 11

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Migration generator already supports `--cost`, `--events`, `--ltm` flags — `--upgrade` follows same pattern
- Template uses EEx with `@prefix`, `@repo_module`, `@migration_module` assigns

### Established Patterns
- Each migration type has its own template file in `priv/templates/`
- Generator checks for existing migration files to prevent duplicates (`Path.wildcard`)
- Timestamp-based naming: `{timestamp}_add_{slug}_{type}_tables.exs`

### Integration Points
- `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` — Main entry point for --upgrade flag
- `priv/templates/` — New template file for upgrade migration

</code_context>

<specifics>
## Specific Ideas

- The --upgrade flag should be general enough to handle future index additions (not just cost cursor index)
- Index name should be explicit: `phoenix_ai_store_cost_records_cursor_idx` for clarity

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-migration-index-contract-tests*
*Context gathered: 2026-04-07*
