# Phase 11: CostStore Query API - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Unify cost record querying into a filter-based API with cursor pagination. Replace `get_cost_records(conversation_id, opts)` with `list_cost_records(filters, opts)`. Add `count_cost_records(filters, opts)`. Both adapters (Ecto + ETS) implement the new callbacks. Breaking change to the CostStore behaviour.

</domain>

<decisions>
## Implementation Decisions

### API Shape
- **D-01:** Rename `get_cost_records` to `list_cost_records(filters, opts)`. Return type changes from `{:ok, [CostRecord.t()]}` to `{:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}`. Generic key `:records` (not `:cost_records`).
- **D-02:** `count_cost_records(filters, opts)` returns `{:ok, non_neg_integer()}` — mirrors `count_events/2`.

### Cursor Encoding & Error Handling
- **D-03:** Extract cursor helpers into a shared `PhoenixAI.Store.Cursor` module used by both EventLog and CostTracking. Cursor format: `Base64URL("#{DateTime.to_iso8601(ts)}|#{id}")` with `(recorded_at, id)` composite for cost records and `(inserted_at, id)` for events.
- **D-04:** Decode cursor defensively using `with` chain. Return `{:error, :invalid_cursor}` on decode failure instead of crashing with MatchError. Migrate EventLog to use the shared module too.

### Provider Filter Normalization
- **D-05:** Normalize `:provider` filter in the Store facade before delegating to adapters. Convert string to atom via `String.to_existing_atom/1`. Adapters always receive atoms. This is a single normalization point — adapters stay pure.

### Backward Compatibility
- **D-06:** Clean break — no deprecation shim. Remove `get_cost_records/2` from CostStore behaviour entirely. Callers migrate to `list_cost_records([conversation_id: id], opts)`. Documented in CHANGELOG as breaking change. Acceptable at 0.x semver.

### Claude's Discretion
- Internal cursor helper API design (function signatures, module organization)
- Whether to add `@since "0.3.0"` annotations to new functions
- Test organization for cursor edge cases

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Pattern (blueprint)
- `lib/phoenix_ai/store/event_log.ex` §48-61 — EventLog cursor encode/decode (the pattern to generalize into shared module)
- `lib/phoenix_ai/store/adapters/ecto.ex` §529-553 — Ecto list_events implementation (keyset cursor pagination reference)
- `lib/phoenix_ai/store/adapters/ets.ex` §465-493 — ETS list_events implementation (drop-while cursor reference)

### Files to Modify
- `lib/phoenix_ai/store/adapter.ex` §75-89 — CostStore behaviour (callback signature change)
- `lib/phoenix_ai/store/adapters/ecto.ex` §416-432 — Ecto get_cost_records (replace with list_cost_records)
- `lib/phoenix_ai/store/adapters/ets.ex` §378-387 — ETS get_cost_records (replace with list_cost_records)
- `lib/phoenix_ai/store.ex` §431-444 — Store facade get_cost_records (replace + add provider normalization)

### Research
- `.planning/research/SUMMARY.md` — Synthesized research findings
- `.planning/research/PITFALLS.md` — 12 pitfalls with prevention strategies

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `apply_cost_filters/2` in both Ecto and ETS adapters — already handles all 6 filter keys, reusable directly
- `EventLog.encode_cursor/1` and `decode_cursor/1` — pattern to extract into shared module
- `maybe_apply_ecto_cursor/2` and `maybe_apply_ecto_limit/2` — Ecto cursor helpers from EventStore, same pattern needed

### Established Patterns
- Adapter sub-behaviours define callbacks, facade checks `function_exported?/3` before delegating
- Telemetry spans wrap every facade operation: `[:phoenix_ai_store, :cost, :action]`
- Filter functions use recursive head/tail pattern matching with catch-all `[_ | rest]` clause

### Integration Points
- `Store.get_cost_records/2` is called directly in facade — replace with `list_cost_records/2`
- `CostStore` behaviour in `adapter.ex` — callback signature is the root dependency
- Contract test at `test/support/cost_store_contract_test.ex` — calls old signature
- Stub adapters in `cost_tracking_test.exs` and `cost_budget_test.exs` — use old signature

</code_context>

<specifics>
## Specific Ideas

- EventStore's `list_events` is the exact blueprint — isomorphic port to CostStore
- Shared Cursor module should handle both `inserted_at` (events) and `recorded_at` (costs) timestamp fields
- Provider normalization uses `String.to_existing_atom/1` (not `String.to_atom/1`) — prevents atom table pollution from arbitrary input

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-coststore-query-api*
*Context gathered: 2026-04-06*
