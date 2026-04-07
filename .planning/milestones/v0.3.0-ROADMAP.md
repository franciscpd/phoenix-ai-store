# Roadmap: PhoenixAI Store

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-9 (shipped 2026-04-05)
- ✅ **v0.2.0 Streaming Support** — Phase 10 (shipped 2026-04-06)
- 🚧 **v0.3.0 Dashboard Queries** — Phases 11-12 (in progress)

## Phases

<details>
<summary>✅ v0.1.0 Initial Release (Phases 1-9) — SHIPPED 2026-04-05</summary>

- [x] Phase 1: Storage Foundation — completed 2026-03-29
- [x] Phase 2: Storage Queries & Metadata — completed 2026-03-30
- [x] Phase 3: Memory Strategies — completed 2026-03-31
- [x] Phase 4: Long-Term Memory — completed 2026-04-01
- [x] Phase 5: Guardrails — completed 2026-04-03
- [x] Phase 6: Cost Tracking — completed 2026-04-04
- [x] Phase 7: Event Log — completed 2026-04-05
- [x] Phase 8: Public API & Telemetry Integration — completed 2026-04-05
- [x] Phase 9: Documentation, CI & Publication — completed 2026-04-05

48/48 requirements satisfied. 376 tests, 0 failures. 5,350 LOC.

See [full roadmap archive](milestones/v0.1.0-ROADMAP.md) for phase details.

</details>

<details>
<summary>✅ v0.2.0 Streaming Support (Phase 10) — SHIPPED 2026-04-06</summary>

- [x] Phase 10: Streaming Support — completed 2026-04-06

12/12 requirements satisfied. 383 tests, 0 failures. 5,400 LOC.

See [full roadmap archive](milestones/v0.2.0-ROADMAP.md) for phase details.

</details>

### 🚧 v0.3.0 Dashboard Queries (In Progress)

**Milestone Goal:** Enable global cost and event querying without requiring a conversation_id, so consumers can build dashboard views.

- [ ] **Phase 11: CostStore Query API** — Unified filter-based cost querying with cursor pagination across both adapters
- [ ] **Phase 12: Migration Index & Contract Tests** — Composite index for cursor pagination and updated adapter contract tests

## Phase Details

### Phase 11: CostStore Query API
**Goal**: Users can query cost records with optional filters and cursor pagination without requiring a conversation_id
**Depends on**: Phase 10 (existing CostStore behaviour)
**Requirements**: COST-01, COST-02, COST-03, COST-04, ADPT-01, ADPT-02, ADPT-03, ADPT-04
**Success Criteria** (what must be TRUE):
  1. Caller can invoke `list_cost_records(filters, opts)` with any combination of user_id, conversation_id, provider, model, after, and before — or none at all — and receive matching records
  2. Caller can paginate results using a cursor returned from the previous page (keyset pagination matching the list_events pattern)
  3. Caller can retrieve a count of matching cost records without loading full record structs
  4. Both the Ecto adapter and the ETS adapter implement the new `list_cost_records/2` and `count_cost_records/2` callbacks and pass all calls through the updated `CostStore` behaviour
  5. The old `get_cost_records(conversation_id, opts)` callback no longer exists on the behaviour — callers that pass no filters get all records
**Plans**: TBD

### Phase 12: Migration Index & Contract Tests
**Goal**: The database schema supports efficient cursor pagination and contract tests verify both adapters satisfy the new behaviour
**Depends on**: Phase 11
**Requirements**: MIGR-01, MIGR-02
**Success Criteria** (what must be TRUE):
  1. Running `mix phoenix_ai_store.gen.migration` generates a migration that includes a composite `(recorded_at, id)` index on the `cost_records` table
  2. The adapter contract test suite covers `list_cost_records/2` with all filter combinations and cursor pagination, and covers `count_cost_records/2`
  3. Both the Ecto adapter and the ETS adapter pass all contract tests without modification after Phase 11 changes
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation | v0.1.0 | — | Complete | 2026-03-29 |
| 2. Storage Queries & Metadata | v0.1.0 | — | Complete | 2026-03-30 |
| 3. Memory Strategies | v0.1.0 | — | Complete | 2026-03-31 |
| 4. Long-Term Memory | v0.1.0 | — | Complete | 2026-04-01 |
| 5. Guardrails | v0.1.0 | — | Complete | 2026-04-03 |
| 6. Cost Tracking | v0.1.0 | — | Complete | 2026-04-04 |
| 7. Event Log | v0.1.0 | — | Complete | 2026-04-05 |
| 8. Public API & Telemetry Integration | v0.1.0 | — | Complete | 2026-04-05 |
| 9. Documentation, CI & Publication | v0.1.0 | — | Complete | 2026-04-05 |
| 10. Streaming Support | v0.2.0 | 1/1 | Complete | 2026-04-06 |
| 11. CostStore Query API | v0.3.0 | 0/? | Not started | - |
| 12. Migration Index & Contract Tests | v0.3.0 | 0/? | Not started | - |
