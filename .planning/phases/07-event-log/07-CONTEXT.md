# Phase 7: Event Log - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Durable append-only event log that automatically records every significant action (8 core event types) with configurable redaction for PII compliance. Cursor-based pagination for efficient querying. Events are immutable once written.

Note: EVNT-V2-01 (PubSub streaming) and EVNT-V2-02 (event replay) are out of scope — future version.

</domain>

<decisions>
## Implementation Decisions

### EventStore Sub-Behaviour
- **D-01:** New `PhoenixAI.Store.Adapter.EventStore` sub-behaviour following the established pattern (FactStore, ProfileStore, TokenUsage, CostStore). Callbacks: `log_event/2`, `list_events/2`, `count_events/2`. **No update or delete callbacks** — append-only by design.

### Event Struct
- **D-02:** Generic `PhoenixAI.Store.EventLog.Event` struct with `type` atom + `data` map. Fields: `id`, `conversation_id`, `user_id`, `type` (atom — one of 8 core types), `data` (map — type-specific payload), `metadata` (map — extra context), `inserted_at` (DateTime).
- **D-03:** Core event types (atoms): `:conversation_created`, `:message_sent`, `:response_received`, `:tool_called`, `:tool_result`, `:policy_violation`, `:cost_recorded`, `:memory_trimmed`.

### Append-Only Enforcement
- **D-04:** Dual enforcement — **API-level** (no update/delete in EventStore behaviour) + **Postgres constraint** in migration template (`CREATE RULE no_update_events AS ON UPDATE TO events DO INSTEAD NOTHING; CREATE RULE no_delete_events AS ON DELETE TO events DO INSTEAD NOTHING`). ETS adapter has no enforcement beyond API — acceptable for dev/test.

### Cursor-Based Pagination
- **D-05:** Composite cursor `(inserted_at, id)` encoded as opaque Base64 string: `Base64.encode("#{DateTime.to_iso8601(inserted_at)}|#{id}")`. Decoded on the server side. Guarantees chronological order regardless of UUID ordering.
- **D-06:** `list_events/2` accepts keyword filters: `:cursor` (opaque string, start after this event), `:limit` (integer, default 50), `:conversation_id`, `:user_id`, `:type`, `:after` (DateTime), `:before` (DateTime). Returns `{:ok, %{events: [Event.t()], next_cursor: String.t() | nil}}`.

### Redaction
- **D-07:** Configurable `redact_fn` of type `(Event.t()) -> Event.t()` in NimbleOptions config. Runs synchronously in the EventLog orchestrator **before** the adapter call. Default: `nil` (no redaction). When configured, the function transforms event data (e.g., masking PII in `data` map) before persistence.
- **D-08:** Redaction is all-or-nothing per event — no field-level granularity in v1. The `redact_fn` receives the full Event struct and returns a modified Event. This keeps the interface simple.

### Automatic Recording
- **D-09:** Phase 7 adds inline event logging to the Store facade functions (`save_conversation/2`, `add_message/3`, `check_guardrails/3`, `record_cost/3`, `apply_memory/3`) that fire when `event_log.enabled: true` in config. This satisfies success criteria #1 ("without extra developer code beyond enabling").
- **D-10:** Phase 8 will additionally wire a TelemetryHandler for automatic capture of PhoenixAI core events (`:chat`, `:tool_call`, etc.). Phase 7 focuses on store-level events only.
- **D-11:** An explicit `Store.log_event/2` public function is also available for custom events beyond the 8 core types.

### Ecto Schema & Migration
- **D-12:** Table `phoenix_ai_store_events` with columns: `id` (binary_id PK), `conversation_id` (binary_id, indexed), `user_id` (string, indexed), `type` (string — atom stored as string), `data` (map/jsonb), `metadata` (map/jsonb), `inserted_at` (utc_datetime_usec, indexed). No `updated_at` column (immutable).
- **D-13:** Composite index on `(inserted_at, id)` for cursor pagination performance. Additional index on `(conversation_id, inserted_at)` for per-conversation queries.
- **D-14:** Migration generator gets `--events` flag for existing installs.

### ETS Implementation
- **D-15:** Key format `{{:event, inserted_at_unix_microseconds, id}, %Event{}}`. Using `inserted_at` as part of the key ensures natural chronological ordering via ETS ordered_set or match_object sort. For the default set table, sort post-query by `inserted_at` then `id`.

### Claude's Discretion
- Exact cursor encoding/decoding implementation
- Event data payload structure per event type (what fields go in `data` for each of the 8 types)
- Whether to add Postgres RULE or just rely on no-callback API enforcement
- Telemetry spans on event log operations
- ETS key format details

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (Phases 1-6)
- `lib/phoenix_ai/store/adapter.ex` — All sub-behaviours (pattern for EventStore)
- `lib/phoenix_ai/store/adapters/ets.ex` — ETS adapter (all sub-behaviours)
- `lib/phoenix_ai/store/adapters/ecto.ex` — Ecto adapter (all sub-behaviours)
- `lib/phoenix_ai/store/cost_tracking.ex` — Orchestrator pattern (model for EventLog orchestrator)
- `lib/phoenix_ai/store/cost_tracking/cost_record.ex` — Struct pattern (model for Event struct)
- `lib/phoenix_ai/store/config.ex` — NimbleOptions schema (extend with event_log section)
- `lib/phoenix_ai/store.ex` — Facade (add log_event/2, list_events/2, inline logging in existing fns)
- `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` — Migration generator (add --events flag)
- `priv/templates/cost_migration.exs.eex` — Migration template pattern
- `test/support/cost_store_contract_test.ex` — Contract test pattern

### Planning
- `.planning/REQUIREMENTS.md` — EVNT-01 through EVNT-05
- `.planning/phases/06-cost-tracking/06-CONTEXT.md` — Phase 6 decisions (CostStore pattern)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CostStore` sub-behaviour + contract test — direct template for EventStore
- `CostTracking` orchestrator — direct template for EventLog orchestrator (validate → transform → persist → telemetry)
- `CostRecord` struct — template for Event struct
- Migration generator with `--cost` and `--ltm` flags — extend with `--events`
- Config NimbleOptions — extend with `event_log` section

### Established Patterns
- Sub-behaviours with `function_exported?/3` checks
- `{:ok, result} | {:error, term}` return types
- Telemetry spans on all facade operations
- Contract tests via `__using__` macro
- Ecto adapter wrapped in `if Code.ensure_loaded?(Ecto)`
- Dynamic table names via prefix option

### Integration Points
- Inline logging in existing facade functions (save_conversation, add_message, etc.)
- `Store.log_event/2` — new facade function for explicit logging
- `Store.list_events/2` — new facade for querying with cursor pagination
- Event data captures the "what happened" — conversation_id links to "where"

</code_context>

<specifics>
## Specific Ideas

- The `data` map for each event type should include enough information to reconstruct what happened without needing to query other tables. For example, `:message_sent` data should include `role`, `content` (or redacted content), and `token_count`.
- Cursor pagination should return `next_cursor: nil` when there are no more results (last page).
- The inline logging in facade functions should be fire-and-forget — if event logging fails, the main operation should still succeed (log the error, don't crash).

</specifics>

<deferred>
## Deferred Ideas

- **EVNT-V2-01**: Event streaming via Phoenix PubSub — future version
- **EVNT-V2-02**: Event replay for conversation reconstruction — future version
- Field-level redaction granularity — v1 uses all-or-nothing per event
- Event retention/archival policies — future version

</deferred>

---

*Phase: 07-event-log*
*Context gathered: 2026-04-05*
