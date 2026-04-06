# Technology Stack

**Project:** PhoenixAI Store — v0.3.0 Dashboard Queries
**Researched:** 2026-04-06
**Scope:** Additions and changes needed for filter-based cost record querying with cursor pagination. Does not re-cover the full v0.1.0/v0.2.0 stack — see prior STACK.md entries in git history for that baseline.

---

## No New Dependencies Required

The v0.3.0 milestone requires **zero new library additions**. Every capability needed is already present:

| Capability | Already Available Via |
|------------|----------------------|
| Ecto query composition with dynamic filters | `ecto ~> 3.13` (already in mix.exs as optional dep) |
| Cursor-based pagination | Hand-rolled pattern already used in `list_events/2` — replicate it |
| ETS scan + filter | OTP stdlib `:ets` — already used in `Adapters.ETS` |
| Decimal arithmetic for cost aggregation | `decimal ~> 2.0` (already a hard dep in mix.exs) |

No new `mix.exs` entries are needed.

---

## What Changes (Behaviour + Adapter Signatures)

### CostStore Behaviour — Breaking Change

Current `get_cost_records/2` signature in `PhoenixAI.Store.Adapter.CostStore`:

```elixir
@callback get_cost_records(conversation_id :: String.t(), keyword()) ::
            {:ok, [CostRecord.t()]} | {:error, term()}
```

New unified signature (mirrors `list_events/2` and `list_conversations/2`):

```elixir
@callback list_cost_records(filters :: keyword(), keyword()) ::
            {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}
```

Rationale: `conversation_id` becomes an optional filter (`:conversation_id` key), not a required positional argument. This is a deliberate breaking change to `CostStore` — the behaviour callback count changes. Both adapters must be updated together.

### Return Shape

Adopt the same `%{records: [...], next_cursor: cursor_or_nil}` map shape used by `list_events/2`. Symmetric API across event and cost queries reduces cognitive overhead for callers.

---

## Ecto Query Composition Pattern (No New Library)

The existing `apply_cost_filters/2` and `apply_event_filters/2` in `Adapters.Ecto` already establish the pattern. Extend it with cursor support following the exact approach in `list_events/2`:

**Cursor encoding — reuse the existing event cursor approach:**

```elixir
# Encode: Base64URL of "iso8601_datetime|uuid"
defp encode_cost_cursor(%CostRecord{} = record) do
  Base.url_encode64("#{DateTime.to_iso8601(record.recorded_at)}|#{record.id}", padding: false)
end

# Ecto where clause — same composite inequality used for events
defp maybe_apply_cursor(query, nil), do: query
defp maybe_apply_cursor(query, cursor) do
  {cursor_ts, cursor_id} = decode_cost_cursor(cursor)
  where(query, [cr], cr.recorded_at > ^cursor_ts or
    (cr.recorded_at == ^cursor_ts and cr.id > ^cursor_id))
end
```

The ordering column for cost records is `recorded_at` (not `inserted_at` as used for events). The composite `(recorded_at, id)` cursor is stable because `id` is a UUID7 (monotonic within the same microsecond).

**ETS cursor — same drop-while pattern used in `Adapters.ETS.list_events/2`:**

```elixir
defp maybe_apply_cursor(records, nil), do: records
defp maybe_apply_cursor(records, cursor) do
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

**ETS key structure — requires change.** Current ETS key is `{:cost_record, conversation_id, record_id}`. This makes global queries (no conversation_id filter) require a full `match_object` scan with `:_` in the conversation_id position — which already works. No key structure change is needed; the existing wildcard pattern `{{:cost_record, :_, :_}, :_}` already enables global scans and `sum_cost/2` uses it. Keep the key unchanged.

---

## Dynamic Filter Support for Cost Records

Filters to support in `list_cost_records/2` (Ecto adapter via `apply_cost_filters/2`, ETS adapter via `filter_cost_records/2`):

| Filter Key | Ecto Clause | ETS Equivalent | Already in `sum_cost/2`? |
|------------|-------------|----------------|--------------------------|
| `:conversation_id` | `where cr.conversation_id == ^id` | `&1.conversation_id == id` | Yes |
| `:user_id` | `where cr.user_id == ^uid` | `&1.user_id == uid` | Yes |
| `:provider` | `where cr.provider == ^to_string(p)` | `&1.provider == p` | Yes |
| `:model` | `where cr.model == ^m` | `&1.model == m` | Yes |
| `:after` | `where cr.recorded_at >= ^dt` | `DateTime.compare >= :eq` | Yes |
| `:before` | `where cr.recorded_at <= ^dt` | `DateTime.compare <= :eq` | Yes |
| `:limit` | `limit(query, ^n)` | `Enum.take/2` | No — new |
| `:cursor` | composite where clause | `Enum.drop_while/2` | No — new |

All filter conditions except `:limit` and `:cursor` are already implemented in `apply_cost_filters/2` used by `sum_cost/2`. Reuse that function and add cursor/limit clauses on top.

---

## Index Recommendation (Postgres / Migration)

The existing `cost_records` table is likely indexed on `conversation_id`. For global dashboard queries (no `conversation_id`), add a composite index on `(recorded_at, id)` to support cursor pagination without a sequential scan:

```sql
CREATE INDEX phoenix_ai_store_cost_records_cursor_idx
  ON phoenix_ai_store_cost_records (recorded_at ASC, id ASC);
```

Add this to the generated migration in `mix phoenix_ai_store.gen.migration`. This is a migration file change, not a dependency change. Confidence: HIGH — same rationale applies as the event log; without this index, cursor queries on large datasets degrade to seqscans.

---

## What NOT to Add

| Avoid | Why |
|-------|-----|
| `paginator` / `scrivener_ecto` / `quarto` | All three add external dependencies for what is 15 lines of hand-rolled cursor logic already established in the codebase. The custom cursor is opaque (no external contract to maintain) and implementation-portable (ETS + Ecto use the same encoding). |
| `flop` | Powerful but heavyweight — it adds filter validation, sorting DSL, and Ecto fragment building. The Store's filter set is small and static. Bringing Flop would be over-engineering and would add a non-optional transitive dep. |
| `ecto_cursor_based_pagination` | Only supports Ecto; the ETS adapter would need divergent logic anyway. The hand-rolled pattern keeps both adapters symmetric. |
| Changing `conversation_id` to nullable in Ecto schema | `conversation_id` in `CostRecordSchema` is currently `@required_fields`. Making it optional in the changeset would allow nil values at write time, which is semantically wrong — cost records always belong to a conversation turn. The filter API makes `conversation_id` optional as a query filter, not as a record field. Leave the schema required field untouched. |

---

## Migration Scope

The DB schema itself does NOT change for v0.3.0. The `cost_records` table already has all the columns needed for the new filter queries. The only migration change is adding the `(recorded_at, id)` index described above.

---

## Integration Points

The `CostTracking` module (`lib/phoenix_ai/store/cost_tracking.ex`) calls `adapter.save_cost_record/2` — this is unaffected. The new `list_cost_records/2` callback is consumed directly by callers of the store facade (`PhoenixAI.Store`), not by `CostTracking`. The facade module needs a new `list_cost_records/2` public function that routes to the configured adapter.

---

## Sources

- Existing `Adapters.Ecto.list_events/2` implementation (cursor pattern baseline): `lib/phoenix_ai/store/adapters/ecto.ex:529-553`
- Existing `Adapters.ETS.list_events/2` implementation (ETS cursor baseline): `lib/phoenix_ai/store/adapters/ets.ex:465-493`
- Existing `apply_cost_filters/2` (filter reuse): `lib/phoenix_ai/store/adapters/ecto.ex:449-487`
- Ecto query composition docs: https://hexdocs.pm/ecto/Ecto.Query.html
- Elixir `Base.url_encode64/2`: https://hexdocs.pm/elixir/Base.html#url_encode64/2
- UUID7 monotonic ordering: https://www.ietf.org/rfc/rfc9562.html#section-5.7 (basis for stable `(recorded_at, id)` cursor)
