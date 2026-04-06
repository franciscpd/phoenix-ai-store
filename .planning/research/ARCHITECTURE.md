# Architecture Patterns

**Domain:** AI conversation persistence & governance (Elixir library)
**Researched:** 2026-04-06
**Milestone context:** v0.3.0 — Dashboard Queries

---

## v0.3.0 Change Summary

This milestone is three precise surgical changes to an otherwise stable architecture:

1. Replace `CostStore.get_cost_records(conversation_id, opts)` with `CostStore.list_cost_records(filters, opts)` — aligning the callback signature with the existing EventStore pattern and making conversation_id an optional filter rather than a required positional argument
2. Add cursor-based pagination to `list_cost_records` in both adapters, using the identical cursor encoding already used by EventStore
3. Update the `Store` facade to expose `list_cost_records/2` instead of `get_cost_records/2`

No new modules. No new supervision tree components. No schema changes.

---

## Existing Architecture (unchanged)

```
PhoenixAI.Store.Adapter (base behaviour)
  ├── .FactStore (optional sub-behaviour)
  ├── .ProfileStore (optional sub-behaviour)
  ├── .TokenUsage (optional sub-behaviour)
  ├── .CostStore (optional sub-behaviour)     ← CHANGING
  └── .EventStore (optional sub-behaviour)    ← reference / model pattern
```

Adapters declare `@behaviour` for each sub-behaviour they implement. The `Store` facade checks `function_exported?(adapter, :callback, arity)` at call time — no compile-time coupling between the facade and optional sub-behaviours.

---

## Current vs Target CostStore Callback Contract

### Current (to be removed)

```elixir
# lib/phoenix_ai/store/adapter.ex — CostStore (CURRENT)
@callback get_cost_records(conversation_id :: String.t(), keyword()) ::
            {:ok, [CostRecord.t()]} | {:error, term()}

@callback sum_cost(filters :: keyword(), keyword()) ::
            {:ok, Decimal.t()} | {:error, term()}
```

`get_cost_records/2` takes a required `conversation_id` as its first positional argument. This prevents global queries (no conversation scope) and prevents cursor pagination — there is no natural place for `:limit` or `:cursor` keys without putting them in the second `opts` argument, which breaks the `filters / opts` separation used everywhere else in the codebase.

### Target (to be added)

```elixir
# lib/phoenix_ai/store/adapter.ex — CostStore (TARGET)
@callback list_cost_records(filters :: keyword(), keyword()) ::
            {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}

@callback sum_cost(filters :: keyword(), keyword()) ::
            {:ok, Decimal.t()} | {:error, term()}
```

`conversation_id` becomes an optional filter key. The return shape matches `EventStore.list_events/2` exactly: a map with a `records` key and a `next_cursor` key. `sum_cost` is unchanged.

---

## Data Flow: Before and After

### Before

```
Store.get_cost_records(conversation_id, opts)
  → adapter.get_cost_records(conversation_id, adapter_opts)
  → {:ok, [%CostRecord{}, ...]}
```

Caller must always supply `conversation_id`. No pagination. No global query.

### After

```
Store.list_cost_records(filters, opts)
  → adapter.list_cost_records(filters, adapter_opts)
  → {:ok, %{records: [...], next_cursor: nil | cursor_string}}
```

Examples:

```elixir
# Conversation-scoped (equivalent to old get_cost_records)
Store.list_cost_records([conversation_id: id], store: :my_store)

# Global dashboard query — no conversation_id required
Store.list_cost_records([user_id: id, after: dt, limit: 50], store: :my_store)
Store.list_cost_records([provider: :openai, limit: 100], store: :my_store)

# Paginated continuation
Store.list_cost_records([limit: 50, cursor: prev_next_cursor], store: :my_store)
```

---

## Component Boundaries

| Component | What Changes |
|-----------|-------------|
| `Adapter.CostStore` (adapter.ex) | Remove `get_cost_records/2` callback; add `list_cost_records/2` callback |
| `Adapters.Ecto` (adapters/ecto.ex) | Remove `get_cost_records/2` impl; add `list_cost_records/2` with cursor logic |
| `Adapters.ETS` (adapters/ets.ex) | Remove `get_cost_records/2` impl; add `list_cost_records/2` with cursor logic |
| `Store` (store.ex) | Remove `get_cost_records/2` facade function; add `list_cost_records/2` |
| `CostStoreContractTest` (test/support/) | Replace `get_cost_records` tests with `list_cost_records` tests including cursor cases |

Unchanged: `CostTracking` orchestrator, `CostRecord` struct, `Schemas.CostRecord`, `sum_cost`, `EventStore`, supervision tree.

---

## Cursor Encoding Pattern

The cursor encoding is identical to EventStore. Copy, do not diverge:

```elixir
# Cursor encodes (recorded_at, id) as Base64URL without padding
# Sort order is: [asc: recorded_at, asc: id]

defp encode_cost_cursor(%CostRecord{recorded_at: ts, id: id}) do
  Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
end

defp decode_cost_cursor(cursor) do
  {:ok, decoded} = Base.url_decode64(cursor, padding: false)
  [ts_str, id] = String.split(decoded, "|", parts: 2)
  {:ok, ts, _} = DateTime.from_iso8601(ts_str)
  {ts, id}
end
```

### Ecto cursor predicate

```elixir
# Keyset pagination — same predicate as maybe_apply_ecto_cursor/2 in EventStore
defp maybe_apply_ecto_cost_cursor(query, nil), do: query

defp maybe_apply_ecto_cost_cursor(query, cursor) do
  {cursor_ts, cursor_id} = decode_cost_cursor(cursor)

  where(
    query,
    [cr],
    cr.recorded_at > ^cursor_ts or
      (cr.recorded_at == ^cursor_ts and cr.id > ^cursor_id)
  )
end
```

### ETS cursor

ETS has no index-based seek. Sort all matching records first, then `Enum.drop_while/2`:

```elixir
defp maybe_apply_cost_cursor(records, nil), do: records

defp maybe_apply_cost_cursor(records, cursor) do
  {cursor_ts, cursor_id} = decode_cost_cursor(cursor)

  Enum.drop_while(records, fn record ->
    case DateTime.compare(record.recorded_at, cursor_ts) do
      :lt -> true
      :gt -> false
      :eq -> record.id <= cursor_id
    end
  end)
end
```

This is O(n) but matches the existing ETS EventStore implementation. ETS is not durable production storage; O(n) is documented and expected.

---

## Filter Keys for list_cost_records

Carry all filter keys from the existing `sum_cost` implementation in both adapters, plus the two pagination keys:

| Filter key | Type | Notes |
|------------|------|-------|
| `:conversation_id` | `String.t()` | Optional — omit for global queries |
| `:user_id` | `String.t()` | Filter by user |
| `:provider` | `atom()` | e.g. `:openai`, `:anthropic` |
| `:model` | `String.t()` | e.g. `"gpt-4o"` |
| `:after` | `DateTime.t()` | Inclusive — `recorded_at >= dt` |
| `:before` | `DateTime.t()` | Inclusive — `recorded_at <= dt` |
| `:limit` | `pos_integer()` | Page size; `nil` means no limit |
| `:cursor` | `String.t()` | Opaque cursor from previous page's `next_cursor` |

The `apply_cost_filters/2` private function in both adapters already handles the first six keys. The `limit` and `cursor` keys are handled in the `list_cost_records/2` function body via dedicated private helpers, not inside `apply_cost_filters/2` — same separation as EventStore's `list_events/2`.

---

## Files That Need Changing

### 1. `lib/phoenix_ai/store/adapter.ex`

In the `defmodule CostStore` block:
- Remove `@callback get_cost_records(conversation_id :: String.t(), keyword())` declaration
- Add `@callback list_cost_records(filters :: keyword(), keyword()) :: {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}`
- Update `@moduledoc` to describe the filter-based API and pagination

### 2. `lib/phoenix_ai/store/adapters/ecto.ex`

- Remove `get_cost_records/2` function and its `@impl` annotation (lines 415–431)
- Add `list_cost_records/2` implementation:
  - Build base query: `from(cr in cost_record_source(opts), order_by: [asc: cr.recorded_at, asc: cr.id])`
  - Apply `apply_cost_filters(query, filters)` — existing function, no changes
  - Apply `maybe_apply_ecto_cost_cursor(query, cursor)` — new private helper
  - Apply `maybe_apply_ecto_limit(query, limit)` — new private helper (identical to events version)
  - Enumerate results with `CostRecordSchema.to_store_struct/1`
  - Compute `next_cursor = if limit && length(records) == limit, do: encode_cost_cursor(List.last(records)), else: nil`
  - Return `{:ok, %{records: records, next_cursor: next_cursor}}`
- Add `encode_cost_cursor/1` and `decode_cost_cursor/1` private helpers

### 3. `lib/phoenix_ai/store/adapters/ets.ex`

- Remove `get_cost_records/2` function and its `@impl` annotation (lines 377–388)
- Note: ETS key structure `{:cost_record, conversation_id, record_id}` is fine as-is — `sum_cost` already uses `match_object(table, {{:cost_record, :_, :_}, :_})` for global queries; `list_cost_records` uses the same match pattern
- Add `list_cost_records/2` implementation:
  - Match all: `:ets.match_object(table, {{:cost_record, :_, :_}, :_})`
  - Extract records with `Enum.map(fn {_key, r} -> r end)`
  - Apply `apply_cost_filters(records, filters)` — existing function, no changes
  - Sort by `{recorded_at, id}` ascending (same comparator as `list_events`)
  - Apply `maybe_apply_cost_cursor(records, cursor)` — new private helper
  - Apply `maybe_take(records, limit)` — new private helper (or reuse pattern from events)
  - Compute `next_cursor`
  - Return `{:ok, %{records: records, next_cursor: next_cursor}}`
- Add `encode_cost_cursor/1` and `decode_cost_cursor/1` private helpers

### 4. `lib/phoenix_ai/store.ex`

- Remove `get_cost_records/2` public function (lines 429–444)
- Add `list_cost_records/2` public function:
  - Signature: `list_cost_records(filters \\ [], opts \\ [])`
  - Telemetry span: `[:phoenix_ai_store, :cost, :list_records]`
  - Feature guard: `function_exported?(adapter, :list_cost_records, 2)`
  - Error atom when unsupported: `:cost_store_not_supported`
  - Delegate: `adapter.list_cost_records(filters, adapter_opts)`

### 5. `test/support/cost_store_contract_test.ex`

- Remove `describe "get_cost_records/2"` block
- Add `describe "list_cost_records/2"` block covering:
  - Returns `%{records: [], next_cursor: nil}` for no matches
  - Returns records ordered by `recorded_at` ascending
  - Filters by `conversation_id` (conversation-scoped, existing semantics)
  - Filters without `conversation_id` (global dashboard query, new)
  - Filters by `user_id`, `provider`, `model`, `after`, `before`
  - Cursor pagination: N records, page size K, yields `ceil(N/K)` pages, all distinct IDs, correct order
  - `next_cursor` is `nil` on the last page

---

## Build Order

Dependencies determine order. These steps must be sequential:

```
Step 1 — Behaviour change
  adapter.ex: remove get_cost_records/2, add list_cost_records/2
  ↓ defines the contract both adapters must satisfy

Step 2a — Ecto adapter (after Step 1)
  adapters/ecto.ex: implement list_cost_records/2

Step 2b — ETS adapter (after Step 1, parallel with 2a)
  adapters/ets.ex: implement list_cost_records/2

Step 3 — Contract test update (can author during Step 2, run after both complete)
  test/support/cost_store_contract_test.ex: update describe blocks

Step 4 — Facade update (after Step 2a + 2b)
  store.ex: remove get_cost_records/2, add list_cost_records/2

Step 5 — Full test run
  mix test — verify all 91 existing tests still pass + new contract tests
```

---

## Consistency Matrix Against EventStore

`list_cost_records/2` must be isomorphic to `list_events/2`. Any divergence is a defect.

| Aspect | EventStore | CostStore (target) |
|--------|------------|-------------------|
| Behaviour callback | `list_events(filters, opts)` | `list_cost_records(filters, opts)` |
| Return map key | `events:` | `records:` |
| Pagination key | `next_cursor:` | `next_cursor:` |
| Sort column | `inserted_at` | `recorded_at` |
| Tiebreaker | `id` | `id` |
| Cursor tuple | `{inserted_at, id}` | `{recorded_at, id}` |
| Ecto cursor predicate | `ts > cur OR (ts == cur AND id > cur_id)` | identical |
| ETS cursor | `Enum.drop_while` with DateTime.compare | identical |
| Facade feature guard | `function_exported?(..., :list_events, 2)` | `function_exported?(..., :list_cost_records, 2)` |
| Telemetry span | `[:phoenix_ai_store, :event, :list]` | `[:phoenix_ai_store, :cost, :list_records]` |

---

## Breaking Change Migration Notes

`Store.get_cost_records/2` is a public API function being removed in v0.3.0. Callers must update:

```elixir
# v0.2.x — requires conversation_id, no pagination
{:ok, records} = Store.get_cost_records(conversation_id, store: :my_store)

# v0.3.0 — conversation_id is an optional filter, returns pagination envelope
{:ok, %{records: records}} =
  Store.list_cost_records([conversation_id: conversation_id], store: :my_store)
```

Internal call audit: `CostTracking.record/3` calls `adapter.save_cost_record/2`, not `get_cost_records` — no change there. The `ConversePipeline` has no cost record reads. The only callers of the old `get_cost_records` are the facade itself and the contract test.

---

## Anti-Patterns to Avoid

### Keeping get_cost_records as a deprecated wrapper

Adding `list_cost_records/2` and keeping `get_cost_records/2` as a delegating shim permanently doubles the behaviour contract surface. Worse, the shim has a mismatched return type — `[CostRecord.t()]` vs `%{records: [...], next_cursor: ...}` — requiring an unwrap in the shim that hides pagination signal from callers. This is v0.3.0 with a clear breaking change window; remove the old callback entirely.

### Cursor and limit in opts rather than filters

All other pagination callbacks (EventStore) accept `:cursor` and `:limit` in the `filters` keyword, not the second `opts` argument. The second argument is for adapter-level options (`:repo`, `:table`, `:prefix`). Putting pagination state in `opts` breaks this established convention and makes the contract test asymmetric with EventStore.

### A separate global_cost_records function

Adding `global_cost_records/1` for dashboard queries alongside a kept `list_cost_records/2` artificially splits one concern (filtered cost record listing) into two API surface functions. A missing `:conversation_id` filter already means global. One function with optional filters is the right model.

### Diverging cursor fields from EventStore

Using a different cursor field (e.g., `id` only, dropping `recorded_at`) would break stable pagination when multiple records share the same timestamp. The `(recorded_at, id)` compound cursor matches how EventStore uses `(inserted_at, id)` — both fields are already indexed by the sort order.

---

## Sources

- Existing `EventStore.list_events/2` in `lib/phoenix_ai/store/adapters/ecto.ex` (lines 529–553) — the reference implementation for cursor pagination
- Existing `EventStore.list_events/2` in `lib/phoenix_ai/store/adapters/ets.ex` (lines 464–493) — ETS cursor pattern
- Current `CostStore.get_cost_records/2` in both adapters — the implementation being replaced
- `Adapter.CostStore` callback definitions in `lib/phoenix_ai/store/adapter.ex` (lines 74–89)
- `Store.get_cost_records/2` facade in `lib/phoenix_ai/store.ex` (lines 429–444) — facade pattern to update
- `CostStoreContractTest` in `test/support/cost_store_contract_test.ex` — contract test to update
- ETS key for cost records confirmed as `{:cost_record, conversation_id, record_id}` — supports global match via `:_` wildcard (verified in `ets.ex` lines 363–374 and `delete_conversation/2` line 103)
