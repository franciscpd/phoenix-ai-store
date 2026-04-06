# Feature Landscape: Dashboard Query API (v0.3.0)

**Domain:** Filter-based record listing API for an Elixir companion library (cost records + event log)
**Researched:** 2026-04-06
**Confidence:** HIGH — based on codebase inspection + verified ecosystem patterns

---

## Context: What Already Exists

The following is already built and must be preserved or superseded cleanly:

| Function | Signature | Gap |
|----------|-----------|-----|
| `get_cost_records/2` | `(conversation_id, opts)` | Requires conversation_id — no global query |
| `sum_cost/2` | `(filters, opts)` | Already filter-based, no change needed |
| `list_events/2` | `(filters, opts)` | Already filter-based with cursor pagination |
| `count_events/2` | `(filters, opts)` | Already filter-based, no change needed |

The `CostStore` behaviour callback `get_cost_records/2` is the only breaking change surface. Both the Ecto and ETS adapters implement it with `conversation_id` as the first positional argument, hardcoded into the ETS key pattern (`{:cost_record, conversation_id, id}`).

---

## Table Stakes

Features a filter-based listing API must have to be usable. Absence makes the API feel incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `list_cost_records(filters, opts)` replacing `get_cost_records/2` | Every peer API in the ecosystem (Oban, Ash, EventStore) uses filter-based listing, not positional resource scoping. A dashboard cannot group by model or user without iterating all conversations first. | Medium | Breaking change to `CostStore` behaviour. Both adapters (Ecto + ETS) need updating. `conversation_id` becomes an optional filter key, consistent with how `sum_cost/2` already works. |
| Cursor-based pagination for cost records | `list_events` already returns `%{events: [...], next_cursor: cursor}`. Cost records must follow the same shape for consistency. Without pagination, a single `list_cost_records` call on a busy store returns unbounded rows. | Medium | Cursor encodes `{recorded_at_usec, id}` — same technique as `list_events`. ETS adapter sorts in-memory and slices; Ecto adapter pushes `WHERE recorded_at > cursor_ts OR (recorded_at == cursor_ts AND id > cursor_id)` to the DB. |
| Filter by `user_id` | Dashboard view is per-user. `sum_cost` already supports this filter; `list_cost_records` must too. | Low | Already implemented in `apply_cost_filters` for both adapters. Only the routing function changes. |
| Filter by `conversation_id` | Existing callers of `get_cost_records/2` must be able to migrate to `list_cost_records([conversation_id: id], opts)` without losing behaviour. | Low | Already in `apply_cost_filters`. The filter key is the same. |
| Filter by `provider` and `model` | Provider-level and model-level cost breakdown is the primary use case for a dashboard. | Low | Already in `apply_cost_filters`. No new logic needed. |
| Filter by `after`/`before` date range | Time-bounded queries ("cost this month", "events this week"). | Low | Already in `apply_cost_filters` and `apply_event_filters`. Consistent naming across both. |
| `count_cost_records(filters, opts)` | Needed to implement total-count indicators and page indicators without a full scan. Mirrors `count_events/2`. | Low | Not yet in `CostStore` behaviour. New callback. ETS: `Enum.count` after filtering. Ecto: `Repo.aggregate(query, :count)`. |
| `{:ok, %{records: [...], next_cursor: cursor}}` return shape | Mirrors the existing `list_events` return shape exactly. Consistency within the library matters more than novelty. | Low | Return `next_cursor: nil` when there is no next page, same as events. |

---

## Differentiators

Not expected, but meaningfully useful for dashboard builders.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `sum_cost_by(group_field, filters, opts)` — group-by aggregate | Returns a map like `%{"gpt-4o" => Decimal, "claude-3-opus" => Decimal}` grouped by `:model`, `:provider`, or `:user_id`. Enables the most common dashboard widget (cost breakdown by model) in a single call. | Medium | Ecto: `group_by` + `select {field, sum(total_cost)}`. ETS: `Enum.group_by` + `Enum.reduce`. Needs a new `CostStore` callback so ETS and Ecto can optimize independently. |
| Stable opaque cursor encoding | Base64url-encoded `{recorded_at_usec, id}` cursor — same as `list_events`. Callers treat cursors as opaque strings; the library owns the encoding. | Low | Already proven in `list_events`. Copy the pattern directly. Do not expose cursor internals in docs. |
| Consistent filter keyword list API across all listing functions | `list_conversations`, `list_events`, `list_cost_records`, `count_events`, `count_cost_records` all accept the same filter keyword shape. A dashboard wrapper module can normalize user input once and pass it to multiple functions. | Low | This is an API design choice, not a code feature. Enforce it by auditing filter key names: `:user_id`, `:conversation_id`, `:after`, `:before`, `:limit`, `:cursor` are the standard set. |

---

## Anti-Features

Features to explicitly NOT build in v0.3.0.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Offset-based pagination (`page: 2, page_size: 50`) | Offset pagination degrades on large tables (full scan to skip N rows). The library already chose cursor pagination for events; adding offset would create two inconsistent pagination paradigms. | Cursor-based only. Document this in `@moduledoc`. Ash, Oban Pro, and the Paginator library all converged on cursor as the recommended pattern for large datasets. |
| `sort_by` / `order_by` as caller-controlled input | User-defined sort order breaks cursor stability — a cursor is only valid for the sort it was generated with. Ash's pagination docs explicitly call this out. | Fix the sort order: `recorded_at ASC, id ASC` for cost records (same as events). Document this. If a caller needs a different sort, they run a fresh query without a cursor. |
| Total count in every `list_cost_records` response | Counting all rows matching a filter is an expensive full-scan on Postgres. Oban does not bundle total count into job listing. | Provide `count_cost_records/2` as a separate function. Let callers opt in to the count query. |
| Flop / Paginator as a dependency | Both libraries add a non-trivial dependency tree. The existing `list_events` cursor implementation is ~30 lines of focused code with no extra deps. | Keep the cursor logic in-house. The pattern is simple enough. |
| `group_by` in `list_cost_records` (mixed list + aggregate) | Combining record listing with aggregation in a single function conflates two query shapes and complicates the return type. | Separate `sum_cost_by/3` for aggregates, `list_cost_records/2` for record listing. |
| Filterable / Flop-style dynamic filter structs | Over-engineering for a library with a fixed, known schema. Keyword filters are idiomatic Elixir and consistent with the rest of the codebase. | Keyword list filters, as already used by `sum_cost/2` and `list_events/2`. |

---

## Feature Dependencies

```
list_cost_records/2
  └── requires: CostStore behaviour change (get_cost_records → list_cost_records)
      └── requires: both Ecto and ETS adapters updated
          ETS adapter: use full scan ({:cost_record, :_, :_}) already proven in sum_cost/2
          Ecto adapter: DROP the conversation_id positional WHERE; accept it via apply_cost_filters

count_cost_records/2
  └── requires: new CostStore callback
  └── requires: both adapters updated

cursor pagination for cost records
  └── requires: list_cost_records/2 (cursor is part of its return shape)
  └── depends on: stable sort order (recorded_at ASC, id ASC)

sum_cost_by/3 (differentiator — optional for v0.3.0)
  └── independent of: cursor pagination
  └── requires: new CostStore callback OR convenience wrapper over list_cost_records
```

**ETS key pattern note:** The current ETS key is `{:cost_record, conversation_id, id}`. The existing `sum_cost/2` already does a full-table scan via `:ets.match_object(table, {{:cost_record, :_, :_}, :_})` and filters in-memory. `list_cost_records` can use the exact same scan-and-filter pattern — no ETS key schema change is required.

---

## MVP Recommendation for v0.3.0

Build (all are table stakes):

1. `list_cost_records(filters, opts)` — replaces `get_cost_records/2`, behaviour callback renamed, both adapters updated, same filter keys as `sum_cost/2`
2. Cursor-based pagination in `list_cost_records` — `{:ok, %{records: [...], next_cursor: cursor}}` shape mirroring `list_events`
3. `count_cost_records(filters, opts)` — new behaviour callback, both adapters, mirrors `count_events`
4. Confirm `list_events` filter coverage is sufficient (inspection shows it is — no action needed)

Defer to a subsequent milestone:

- `sum_cost_by/3` — useful but not blocking dashboard use; `sum_cost/2` with per-filter calls is a workable workaround

---

## Ecosystem Patterns Observed

**Oban:** Exposes no built-in `list_jobs` function. Users query `Oban.Job` directly via Ecto. Bulk operations (`cancel_all_jobs`, `delete_all_jobs`) accept `Ecto.Queryable` as the filter. Not directly applicable — this library abstracts the query layer behind adapters — but confirms that positional resource IDs are not the expected pattern for listing APIs.

**Ash Framework:** Cursor (keyset) pagination is the recommended default for read actions on large datasets. Ash explicitly documents that changing sort order invalidates an existing cursor. Filter arguments are passed as ordinary arguments to read actions. The `first`/`after` and `last`/`before` naming is Relay-compliant but more verbose than the `limit`/`cursor` + `next_cursor` pattern already used in `list_events` — no reason to change the existing convention.

**EventStore (Commanded):** Uses `start_version` + `count` for event stream reads — an offset by sequence number, not by time or opaque cursor. Streams are single-writer so sequence numbers are stable. Not applicable here (cost records have no monotonic sequence number; `recorded_at` + `id` is the stable ordering key).

**Flop:** Full filter/sort/pagination library. The `{results, meta}` return shape with `has_next_page?` and `end_cursor` is the most complete design, but the existing `{:ok, %{events: [...], next_cursor: cursor}}` shape in this codebase is equivalent and established — stick with it. Adding Flop as a dep is rejected (see Anti-Features).

**Paginator (duffelhq):** Cursor approach uses `cursor_fields: [:inserted_at, :id]` to define the sort-stable fields and encodes them as an opaque base64 string. Returns `%{entries: [...], metadata: %{after: cursor, before: cursor, limit: N}}`. The existing `list_events` implementation follows the same concept with a custom encoder — no external dep needed.

---

## Sources

- Existing codebase: `/lib/phoenix_ai/store/adapter.ex` (CostStore behaviour), `/lib/phoenix_ai/store/adapters/ecto.ex`, `/lib/phoenix_ai/store/adapters/ets.ex`, `/lib/phoenix_ai/store/store.ex`
- Ash pagination docs (keyset + sort stability): https://hexdocs.pm/ash/pagination.html
- Ash keyset + filter forum discussion: https://elixirforum.com/t/action-with-keyset-pagination-and-dynamic-filters/60213
- Flop filter/pagination API: https://hexdocs.pm/flop/Flop.html
- EventStore read API (Commanded): https://hexdocs.pm/eventstore/EventStore.html
- Oban job operations (no built-in list): https://hexdocs.pm/oban/Oban.html
- Paginator (duffelhq) cursor pattern: https://github.com/duffelhq/paginator
- Ecto aggregates guide: https://hexdocs.pm/ecto/aggregates-and-subqueries.html
