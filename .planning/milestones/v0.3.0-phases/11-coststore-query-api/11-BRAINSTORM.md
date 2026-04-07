# Phase 11: CostStore Query API — Design Spec

**Date:** 2026-04-06
**Phase:** 11-coststore-query-api
**Approach:** Direct port of EventStore pattern to CostStore

## Overview

Replace `get_cost_records(conversation_id, opts)` with `list_cost_records(filters, opts)` — a filter-based API with cursor pagination. Add `count_cost_records(filters, opts)`. Extract cursor helpers into a shared module. Breaking change to the CostStore behaviour.

**Scope:** ~5 files modified, 1 new module, ~150 LOC net new

## 1. Behaviour Change (CostStore)

File: `lib/phoenix_ai/store/adapter.ex`

Remove the existing `get_cost_records/2` callback. Add two new callbacks:

```elixir
@callback list_cost_records(filters :: keyword(), keyword()) ::
            {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}
            | {:error, term()}

@callback count_cost_records(filters :: keyword(), keyword()) ::
            {:ok, non_neg_integer()}
```

**Supported filters** (same set as `sum_cost` + pagination):
- `:conversation_id` — scope to a single conversation
- `:user_id` — scope to a user
- `:provider` — filter by provider atom (`:openai`, `:anthropic`)
- `:model` — filter by model string (`"gpt-4o"`)
- `:after` — records with `recorded_at >= dt`
- `:before` — records with `recorded_at <= dt`
- `:cursor` — opaque cursor string from previous page
- `:limit` — max records per page

`:cursor` and `:limit` are extracted before passing to `apply_cost_filters`. They are pagination options, not filter predicates.

`save_cost_record/2` and `sum_cost/2` remain unchanged.

`conversation_id` remains a required field on `CostRecord` — the global query aggregates across conversations, it does not support orphan records.

## 2. Shared Cursor Module

New file: `lib/phoenix_ai/store/cursor.ex`

```elixir
defmodule PhoenixAI.Store.Cursor do
  @moduledoc "Shared keyset cursor encoding/decoding for paginated queries."

  @spec encode(DateTime.t(), String.t()) :: String.t()
  def encode(%DateTime{} = ts, id) do
    Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  @spec decode(String.t()) :: {:ok, {DateTime.t(), String.t()}} | {:error, :invalid_cursor}
  def decode(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [ts_str, id] <- String.split(decoded, "|", parts: 2),
         {:ok, ts, _} <- DateTime.from_iso8601(ts_str) do
      {:ok, {ts, id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end
end
```

### EventLog Migration

`EventLog.encode_cursor/1` and `decode_cursor/1` delegate to `Cursor.encode/2` and `Cursor.decode/1`. The public API of EventLog does not change — callers still use `EventLog.encode_cursor(%Event{})`, but internally it calls `Cursor.encode(event.inserted_at, event.id)`.

Both adapters' event cursor logic also migrates to use the shared module. This is **in scope for Phase 11** — the EventLog migration is part of extracting the shared Cursor module, not a separate task.

## 3. Ecto Adapter

File: `lib/phoenix_ai/store/adapters/ecto.ex`

Replace `get_cost_records/2` with:

```elixir
@impl PhoenixAI.Store.Adapter.CostStore
def list_cost_records(filters, opts) do
  repo = Keyword.fetch!(opts, :repo)
  {pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])
  limit = Keyword.get(pagination, :limit)
  cursor = Keyword.get(pagination, :cursor)

  query =
    from(cr in cost_record_source(opts), order_by: [asc: cr.recorded_at, asc: cr.id])
    |> apply_cost_filters(filter_opts)
    |> maybe_apply_cost_cursor(cursor)
    |> maybe_apply_cost_limit(limit)

  records = repo.all(query) |> Enum.map(&CostRecordSchema.to_store_struct/1)

  next_cursor =
    if limit && length(records) == limit do
      last = List.last(records)
      Cursor.encode(last.recorded_at, last.id)
    end

  {:ok, %{records: records, next_cursor: next_cursor}}
end

@impl PhoenixAI.Store.Adapter.CostStore
def count_cost_records(filters, opts) do
  repo = Keyword.fetch!(opts, :repo)
  {_pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])

  count =
    from(cr in cost_record_source(opts), select: count(cr.id))
    |> apply_cost_filters(filter_opts)
    |> repo.one()

  {:ok, count}
end
```

**Cursor helpers** (`maybe_apply_cost_cursor/2`, `maybe_apply_cost_limit/2`): mirror the EventStore equivalents. Keyset WHERE clause: `(recorded_at > cursor_ts) OR (recorded_at == cursor_ts AND id > cursor_id)`.

Invalid cursor from `Cursor.decode/1` returns `{:error, :invalid_cursor}` from the function.

Existing `apply_cost_filters/2` is reused without changes — it already handles all 6 filter keys with a catch-all `[_ | rest]` clause that silently skips unknown keys.

## 4. ETS Adapter

File: `lib/phoenix_ai/store/adapters/ets.ex`

Replace `get_cost_records/2` with:

```elixir
@impl PhoenixAI.Store.Adapter.CostStore
def list_cost_records(filters, opts) do
  table = Keyword.fetch!(opts, :table)
  {pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])

  base_records =
    case Keyword.get(filter_opts, :conversation_id) do
      nil -> :ets.match_object(table, {{:cost_record, :_, :_}, :_})
      conv_id -> :ets.match_object(table, {{:cost_record, conv_id, :_}, :_})
    end
    |> Enum.map(fn {_key, record} -> record end)
    |> apply_cost_filters(Keyword.delete(filter_opts, :conversation_id))
    |> Enum.sort_by(&{&1.recorded_at, &1.id}, {:asc, DateTime})

  {records, next_cursor} = apply_ets_cost_pagination(base_records, pagination)
  {:ok, %{records: records, next_cursor: next_cursor}}
end

@impl PhoenixAI.Store.Adapter.CostStore
def count_cost_records(filters, opts) do
  table = Keyword.fetch!(opts, :table)
  {_pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])

  count =
    case Keyword.get(filter_opts, :conversation_id) do
      nil -> :ets.match_object(table, {{:cost_record, :_, :_}, :_})
      conv_id -> :ets.match_object(table, {{:cost_record, conv_id, :_}, :_})
    end
    |> Enum.map(fn {_key, record} -> record end)
    |> apply_cost_filters(Keyword.delete(filter_opts, :conversation_id))
    |> length()

  {:ok, count}
end
```

**Key design choices:**
- Branch on `conversation_id` presence for ETS match pattern — avoids the `nil` match pitfall
- Delete `:conversation_id` from filter_opts after using it in match pattern — prevents double-filtering
- `apply_ets_cost_pagination/2` uses `Enum.drop_while` for cursor positioning, then `Enum.take` for limit
- Cursor decode uses shared `Cursor.decode/1` with `{:error, :invalid_cursor}` propagation

## 5. Store Facade

File: `lib/phoenix_ai/store.ex`

Remove `get_cost_records/2`. Add:

```elixir
@spec list_cost_records(keyword(), keyword()) ::
        {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}
        | {:error, term()}
def list_cost_records(filters \\ [], opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :cost, :list_records], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)
    filters = normalize_provider_filter(filters)

    result =
      if function_exported?(adapter, :list_cost_records, 2) do
        adapter.list_cost_records(filters, adapter_opts)
      else
        {:error, :cost_store_not_supported}
      end

    {result, %{}}
  end)
end

@spec count_cost_records(keyword(), keyword()) ::
        {:ok, non_neg_integer()} | {:error, term()}
def count_cost_records(filters \\ [], opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :cost, :count_records], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)
    filters = normalize_provider_filter(filters)

    result =
      if function_exported?(adapter, :count_cost_records, 2) do
        adapter.count_cost_records(filters, adapter_opts)
      else
        {:error, :cost_store_not_supported}
      end

    {result, %{}}
  end)
end

defp normalize_provider_filter(filters) do
  case Keyword.get(filters, :provider) do
    nil -> filters
    p when is_atom(p) -> filters
    p when is_binary(p) -> Keyword.put(filters, :provider, String.to_existing_atom(p))
  end
end
```

**Provider normalization** happens once in the facade — adapters always receive atoms.

## 6. Test Updates

### Contract Test Replacement

Replace `describe "get_cost_records/2"` with comprehensive `list_cost_records/2` tests:

- Returns all records when no filters
- Filters by each individual field (conversation_id, user_id, provider, model, after, before)
- Combines multiple filters
- Cursor pagination: first page, next page, exhausted (nil cursor)
- Invalid cursor returns `{:error, :invalid_cursor}`
- Records with same `recorded_at` sort stably by id

Add `describe "count_cost_records/2"`:
- Counts all records with no filters
- Count matches length of list_cost_records for same filters

### Stub Adapter Updates

Update stubs in `cost_tracking_test.exs` and `cost_budget_test.exs`:
- `def list_cost_records(_filters, _opts)` → `{:ok, %{records: [], next_cursor: nil}}`
- `def count_cost_records(_filters, _opts)` → `{:ok, 0}`

## 7. Migration (Phase 12)

Composite index for cursor pagination performance:

```elixir
create index(:phoenix_ai_store_cost_records, [:recorded_at, :id],
  name: :phoenix_ai_store_cost_records_cursor_idx)
```

This is Phase 12 scope but documented here for completeness.

## Files Changed Summary

| File | Action |
|------|--------|
| `lib/phoenix_ai/store/cursor.ex` | **New** — shared cursor encode/decode |
| `lib/phoenix_ai/store/adapter.ex` | Modify — CostStore callbacks |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify — replace get_cost_records, add count |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify — replace get_cost_records, add count |
| `lib/phoenix_ai/store/store.ex` | Modify — facade functions + provider normalization |
| `lib/phoenix_ai/store/event_log.ex` | Modify — delegate to Cursor module |
| `test/support/cost_store_contract_test.ex` | Modify — replace test block |
| `test/phoenix_ai/store/cost_tracking_test.exs` | Modify — stub signature |
| `test/phoenix_ai/store/guardrails/cost_budget_test.exs` | Modify — stub signature |

## Breaking Changes

- `get_cost_records(conversation_id, opts)` removed
- Callers migrate to `list_cost_records([conversation_id: id], opts)`
- Return type changes from `{:ok, [CostRecord.t()]}` to `{:ok, %{records: [...], next_cursor: ...}}`
- Custom adapters implementing `CostStore` must update callback signatures

## Decisions Log

| ID | Decision | Rationale |
|----|----------|-----------|
| D-01 | `list_cost_records` name, `%{records: ...}` return | Consistency with filter-based pattern; generic `:records` key |
| D-02 | Shared `Cursor` module | DRY, defensive decode, single maintenance point |
| D-03 | Provider normalized in facade | Single normalization point; adapters stay pure |
| D-04 | Clean break, no deprecation | 0.x semver allows it; simpler codebase |
| D-05 | `conversation_id` stays required on CostRecord | Global query aggregates across conversations, not orphan records |

---
*Design approved: 2026-04-06*
*Approach: A — Direct port of EventStore pattern*
