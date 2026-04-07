# CostStore Query API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `get_cost_records(conversation_id, opts)` with filter-based `list_cost_records(filters, opts)` and `count_cost_records(filters, opts)`, with cursor pagination — enabling dashboard queries without requiring a conversation_id.

**Architecture:** Extract shared cursor helpers from EventLog into a new `Cursor` module. Update `CostStore` behaviour callbacks. Implement in both adapters (Ecto keyset cursor, ETS drop-while cursor). Update facade with provider normalization. Breaking change — clean break, no deprecation shim.

**Tech Stack:** Elixir, Ecto, ETS, ExUnit

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/cursor.ex` | Create | Shared cursor encode/decode with defensive error handling |
| `lib/phoenix_ai/store/event_log.ex` | Modify | Delegate to Cursor module |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Update CostStore behaviour callbacks |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement list_cost_records, count_cost_records |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement list_cost_records, count_cost_records |
| `lib/phoenix_ai/store.ex` | Modify | Facade functions + provider normalization |
| `test/phoenix_ai/store/cursor_test.exs` | Create | Unit tests for shared Cursor module |
| `test/support/cost_store_contract_test.ex` | Modify | Replace get_cost_records tests with list/count |
| `test/phoenix_ai/store/cost_tracking_test.exs` | Modify | Update stub adapter signature |
| `test/phoenix_ai/store/guardrails/cost_budget_test.exs` | Modify | Update stub adapter signature |

---

### Task 1: Shared Cursor Module

**Files:**
- Create: `lib/phoenix_ai/store/cursor.ex`
- Create: `test/phoenix_ai/store/cursor_test.exs`

- [ ] **Step 1: Write failing tests for Cursor module**

```elixir
# test/phoenix_ai/store/cursor_test.exs
defmodule PhoenixAI.Store.CursorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Cursor

  describe "encode/2 and decode/1" do
    test "round-trips a DateTime and id" do
      ts = ~U[2026-04-06 12:00:00.000000Z]
      id = "01912345-6789-7abc-def0-123456789abc"

      cursor = Cursor.encode(ts, id)
      assert is_binary(cursor)
      assert {:ok, {^ts, ^id}} = Cursor.decode(cursor)
    end

    test "encode produces URL-safe base64 without padding" do
      ts = ~U[2026-01-01 00:00:00Z]
      cursor = Cursor.encode(ts, "some-id")
      refute String.contains?(cursor, "=")
      refute String.contains?(cursor, "+")
      refute String.contains?(cursor, "/")
    end
  end

  describe "decode/1 error handling" do
    test "returns error for invalid base64" do
      assert {:error, :invalid_cursor} = Cursor.decode("not-valid-base64!!!")
    end

    test "returns error for valid base64 but missing pipe separator" do
      cursor = Base.url_encode64("no-pipe-here", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor)
    end

    test "returns error for valid base64 with pipe but invalid datetime" do
      cursor = Base.url_encode64("not-a-datetime|some-id", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor)
    end

    test "returns error for empty string" do
      assert {:error, :invalid_cursor} = Cursor.decode("")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/cursor_test.exs`
Expected: FAIL — module `PhoenixAI.Store.Cursor` not found

- [ ] **Step 3: Implement Cursor module**

```elixir
# lib/phoenix_ai/store/cursor.ex
defmodule PhoenixAI.Store.Cursor do
  @moduledoc """
  Shared keyset cursor encoding and decoding for paginated queries.

  Used by both EventLog and CostStore to produce opaque cursor strings
  for cursor-based pagination. The cursor encodes a `(DateTime, id)` pair
  as a Base64URL string.
  """

  @doc """
  Encodes a timestamp and id into an opaque cursor string.
  """
  @spec encode(DateTime.t(), String.t()) :: String.t()
  def encode(%DateTime{} = ts, id) when is_binary(id) do
    Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  @doc """
  Decodes a cursor string back into `{DateTime.t(), String.t()}`.

  Returns `{:error, :invalid_cursor}` if the cursor is malformed.
  """
  @spec decode(String.t()) :: {:ok, {DateTime.t(), String.t()}} | {:error, :invalid_cursor}
  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [ts_str, id] when id != "" <- String.split(decoded, "|", parts: 2),
         {:ok, ts, _} <- DateTime.from_iso8601(ts_str) do
      {:ok, {ts, id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/cursor_test.exs`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/cursor.ex test/phoenix_ai/store/cursor_test.exs
git commit -m "feat(cursor): add shared cursor encode/decode module"
```

---

### Task 2: Migrate EventLog to Shared Cursor

**Files:**
- Modify: `lib/phoenix_ai/store/event_log.ex:48-61`
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex:625-634`
- Modify: `lib/phoenix_ai/store/adapters/ets.ex:562-571`

- [ ] **Step 1: Update EventLog to delegate to Cursor module**

In `lib/phoenix_ai/store/event_log.ex`, replace `encode_cursor/1` and `decode_cursor/1`:

```elixir
# Replace lines 47-61 with:
  @doc """
  Encodes an event into a cursor string for pagination.
  """
  @spec encode_cursor(Event.t()) :: String.t()
  def encode_cursor(%Event{inserted_at: ts, id: id}) do
    PhoenixAI.Store.Cursor.encode(ts, id)
  end

  @doc """
  Decodes a cursor string back into `{DateTime.t(), id}`.
  """
  @spec decode_cursor(String.t()) :: {:ok, {DateTime.t(), String.t()}} | {:error, :invalid_cursor}
  def decode_cursor(cursor) do
    PhoenixAI.Store.Cursor.decode(cursor)
  end
```

- [ ] **Step 2: Update Ecto adapter event cursor helpers**

In `lib/phoenix_ai/store/adapters/ecto.ex`, replace `encode_event_cursor/1` and `decode_event_cursor/1` (lines 625-634):

```elixir
    defp encode_event_cursor(%Event{} = event) do
      PhoenixAI.Store.Cursor.encode(event.inserted_at, event.id)
    end

    defp decode_event_cursor(cursor) do
      {:ok, {ts, id}} = PhoenixAI.Store.Cursor.decode(cursor)
      {ts, id}
    end
```

- [ ] **Step 3: Update ETS adapter event cursor helpers**

In `lib/phoenix_ai/store/adapters/ets.ex`, replace `encode_event_cursor/1` and `decode_event_cursor/1` (lines 562-571):

```elixir
  defp encode_event_cursor(%Event{} = event) do
    PhoenixAI.Store.Cursor.encode(event.inserted_at, event.id)
  end

  defp decode_event_cursor(cursor) do
    {:ok, {ts, id}} = PhoenixAI.Store.Cursor.decode(cursor)
    {ts, id}
  end
```

- [ ] **Step 4: Run full test suite to verify no regressions**

Run: `mix test`
Expected: All existing tests PASS — cursor behaviour unchanged

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/event_log.ex lib/phoenix_ai/store/adapters/ecto.ex lib/phoenix_ai/store/adapters/ets.ex
git commit -m "refactor(cursor): migrate EventLog to shared Cursor module"
```

---

### Task 3: Update CostStore Behaviour

**Files:**
- Modify: `lib/phoenix_ai/store/adapter.ex:74-89`

- [ ] **Step 1: Update CostStore behaviour callbacks**

In `lib/phoenix_ai/store/adapter.ex`, replace the CostStore defmodule (lines 74-89):

```elixir
  defmodule CostStore do
    @moduledoc """
    Sub-behaviour for adapters that support cost record persistence.
    """

    alias PhoenixAI.Store.CostTracking.CostRecord

    @callback save_cost_record(CostRecord.t(), keyword()) ::
                {:ok, CostRecord.t()} | {:error, term()}

    @callback list_cost_records(filters :: keyword(), keyword()) ::
                {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}
                | {:error, term()}

    @callback count_cost_records(filters :: keyword(), keyword()) ::
                {:ok, non_neg_integer()}

    @callback sum_cost(filters :: keyword(), keyword()) ::
                {:ok, Decimal.t()} | {:error, term()}
  end
```

- [ ] **Step 2: Verify compilation (will have warnings about missing implementations)**

Run: `mix compile --warnings-as-errors 2>&1 || true`
Expected: Warnings about `list_cost_records/2` and `count_cost_records/2` not implemented in adapters. This is expected — we implement them next.

- [ ] **Step 3: Commit**

```bash
git add lib/phoenix_ai/store/adapter.ex
git commit -m "feat(adapter): update CostStore behaviour with list/count callbacks"
```

---

### Task 4: Implement Ecto Adapter

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex:414-507`

- [ ] **Step 1: Replace get_cost_records with list_cost_records and count_cost_records**

In `lib/phoenix_ai/store/adapters/ecto.ex`, replace `get_cost_records/2` (lines 414-432) with:

```elixir
    @doc """
    Queries cost records matching the given filters with cursor-based pagination.

    Filters: `:conversation_id`, `:user_id`, `:provider`, `:model`, `:after`, `:before`.
    Pagination: `:cursor`, `:limit`.
    """
    @impl PhoenixAI.Store.Adapter.CostStore
    def list_cost_records(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)
      {pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])
      limit = Keyword.get(pagination, :limit)
      cursor = Keyword.get(pagination, :cursor)

      with :ok <- validate_cost_cursor(cursor) do
        query =
          from(cr in cost_record_source(opts), order_by: [asc: cr.recorded_at, asc: cr.id])
          |> apply_cost_filters(filter_opts)
          |> maybe_apply_cost_cursor(cursor)
          |> maybe_apply_cost_limit(limit)

        records =
          repo.all(query)
          |> Enum.map(&CostRecordSchema.to_store_struct/1)

        next_cursor =
          if limit && length(records) == limit do
            last = List.last(records)
            PhoenixAI.Store.Cursor.encode(last.recorded_at, last.id)
          else
            nil
          end

        {:ok, %{records: records, next_cursor: next_cursor}}
      end
    end

    @doc "Counts cost records matching the given filters."
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

- [ ] **Step 2: Add cursor helpers after existing apply_cost_filters (after line 487)**

```elixir
    defp validate_cost_cursor(nil), do: :ok

    defp validate_cost_cursor(cursor) do
      case PhoenixAI.Store.Cursor.decode(cursor) do
        {:ok, _} -> :ok
        {:error, :invalid_cursor} -> {:error, :invalid_cursor}
      end
    end

    defp maybe_apply_cost_cursor(query, nil), do: query

    defp maybe_apply_cost_cursor(query, cursor) do
      {:ok, {cursor_ts, cursor_id}} = PhoenixAI.Store.Cursor.decode(cursor)

      where(
        query,
        [cr],
        cr.recorded_at > ^cursor_ts or (cr.recorded_at == ^cursor_ts and cr.id > ^cursor_id)
      )
    end

    defp maybe_apply_cost_limit(query, nil), do: query
    defp maybe_apply_cost_limit(query, limit), do: limit(query, ^limit)
```

- [ ] **Step 3: Remove the old valid_uuid? helper (lines 499-506) if no longer used**

Check if `valid_uuid?/1` is used elsewhere in the Ecto adapter. If only used by old `get_cost_records`, remove it.

- [ ] **Step 4: Verify compilation**

Run: `mix compile`
Expected: Compiles without errors (ETS adapter still has warnings — expected)

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ecto.ex
git commit -m "feat(ecto): implement list_cost_records and count_cost_records"
```

---

### Task 5: Implement ETS Adapter

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex:376-443`

- [ ] **Step 1: Replace get_cost_records with list_cost_records and count_cost_records**

In `lib/phoenix_ai/store/adapters/ets.ex`, replace `get_cost_records/2` (lines 376-387) with:

```elixir
  @doc """
  Queries cost records matching the given filters with cursor-based pagination.

  Note: O(n) full table scan — use the Ecto adapter for production workloads
  requiring efficient paginated queries over large datasets.
  """
  @impl PhoenixAI.Store.Adapter.CostStore
  def list_cost_records(filters, opts) do
    table = Keyword.fetch!(opts, :table)
    {pagination, filter_opts} = Keyword.split(filters, [:cursor, :limit])
    cursor = Keyword.get(pagination, :cursor)
    limit = Keyword.get(pagination, :limit)

    with :ok <- validate_cost_cursor(cursor) do
      base_records =
        case Keyword.get(filter_opts, :conversation_id) do
          nil -> :ets.match_object(table, {{:cost_record, :_, :_}, :_})
          conv_id -> :ets.match_object(table, {{:cost_record, conv_id, :_}, :_})
        end
        |> Enum.map(fn {_key, record} -> record end)
        |> apply_cost_filters(Keyword.delete(filter_opts, :conversation_id))
        |> Enum.sort_by(&{&1.recorded_at, &1.id}, fn {ts1, id1}, {ts2, id2} ->
          case DateTime.compare(ts1, ts2) do
            :lt -> true
            :gt -> false
            :eq -> id1 < id2
          end
        end)
        |> maybe_apply_cost_cursor(cursor)
        |> maybe_take_cost(limit)

      next_cursor =
        if limit && length(base_records) == limit do
          last = List.last(base_records)
          PhoenixAI.Store.Cursor.encode(last.recorded_at, last.id)
        else
          nil
        end

      {:ok, %{records: base_records, next_cursor: next_cursor}}
    end
  end

  @doc """
  Counts cost records matching the given filters.

  Note: O(n) — materializes the full filtered list then counts.
  """
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

- [ ] **Step 2: Add ETS cursor helpers after apply_cost_filters (after line 443)**

```elixir
  defp validate_cost_cursor(nil), do: :ok

  defp validate_cost_cursor(cursor) do
    case PhoenixAI.Store.Cursor.decode(cursor) do
      {:ok, _} -> :ok
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end

  defp maybe_apply_cost_cursor(records, nil), do: records

  defp maybe_apply_cost_cursor(records, cursor) do
    {:ok, {cursor_ts, cursor_id}} = PhoenixAI.Store.Cursor.decode(cursor)

    Enum.drop_while(records, fn record ->
      case DateTime.compare(record.recorded_at, cursor_ts) do
        :lt -> true
        :gt -> false
        :eq -> record.id <= cursor_id
      end
    end)
  end

  defp maybe_take_cost(records, nil), do: records
  defp maybe_take_cost(records, limit), do: Enum.take(records, limit)
```

- [ ] **Step 3: Verify compilation (clean — both adapters now implement the new callbacks)**

Run: `mix compile --warnings-as-errors`
Expected: Compiles clean (may have warnings from test stubs — we fix those next)

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex
git commit -m "feat(ets): implement list_cost_records and count_cost_records"
```

---

### Task 6: Update Store Facade

**Files:**
- Modify: `lib/phoenix_ai/store.ex:424-444`

- [ ] **Step 1: Replace get_cost_records with list_cost_records and count_cost_records**

In `lib/phoenix_ai/store.ex`, replace `get_cost_records/2` (lines 424-444) with:

```elixir
  @doc """
  Lists cost records matching the given filters with cursor pagination.

  Delegates to `adapter.list_cost_records/2` if the adapter supports CostStore.

  ## Filters

    * `:conversation_id` — filter by conversation
    * `:user_id` — filter by user
    * `:provider` — filter by provider (atom or string — normalized to atom)
    * `:model` — filter by model string (e.g. `"gpt-4o"`)
    * `:after` — include only records with `recorded_at >= dt`
    * `:before` — include only records with `recorded_at <= dt`
    * `:cursor` — opaque cursor from previous page
    * `:limit` — max records per page
  """
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

  @doc """
  Counts cost records matching the given filters.

  Delegates to `adapter.count_cost_records/2` if the adapter supports CostStore.
  Accepts the same filters as `list_cost_records/2` (excluding `:cursor` and `:limit`).
  """
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
```

- [ ] **Step 2: Add normalize_provider_filter helper (in the private functions section)**

```elixir
  defp normalize_provider_filter(filters) do
    case Keyword.get(filters, :provider) do
      nil -> filters
      p when is_atom(p) -> filters
      p when is_binary(p) -> Keyword.put(filters, :provider, String.to_existing_atom(p))
    end
  end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Compiles (test stubs will warn — fixed in next task)

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store.ex
git commit -m "feat(store): add list_cost_records and count_cost_records facade"
```

---

### Task 7: Update Test Stubs and Contract Tests

**Files:**
- Modify: `test/phoenix_ai/store/cost_tracking_test.exs:16`
- Modify: `test/phoenix_ai/store/guardrails/cost_budget_test.exs:16`
- Modify: `test/support/cost_store_contract_test.ex:84-126`

- [ ] **Step 1: Update stub in cost_tracking_test.exs**

In `test/phoenix_ai/store/cost_tracking_test.exs`, replace line 16:

```elixir
    # Old: def get_cost_records(_conv_id, _opts), do: {:ok, []}
    def list_cost_records(_filters, _opts), do: {:ok, %{records: [], next_cursor: nil}}

    @impl true
    def count_cost_records(_filters, _opts), do: {:ok, 0}
```

- [ ] **Step 2: Update stub in cost_budget_test.exs**

In `test/phoenix_ai/store/guardrails/cost_budget_test.exs`, replace line 16:

```elixir
    # Old: def get_cost_records(_, _), do: {:ok, []}
    def list_cost_records(_, _), do: {:ok, %{records: [], next_cursor: nil}}

    @impl true
    def count_cost_records(_, _), do: {:ok, 0}
```

- [ ] **Step 3: Replace contract test describe block for get_cost_records/2**

In `test/support/cost_store_contract_test.ex`, replace the `describe "get_cost_records/2"` block (lines 84-126) with:

```elixir
      describe "list_cost_records/2" do
        setup %{opts: opts} do
          conv1 = build_conversation(%{user_id: "lr_user_a"})
          {:ok, conv1} = @adapter.save_conversation(conv1, opts)

          conv2 = build_conversation(%{user_id: "lr_user_b"})
          {:ok, conv2} = @adapter.save_conversation(conv2, opts)

          now = DateTime.utc_now()
          earlier = DateTime.add(now, -60, :second)
          later = DateTime.add(now, 60, :second)

          r1 =
            build_cost_record(%{
              conversation_id: conv1.id,
              user_id: "lr_user_a",
              provider: :openai,
              model: "gpt-4",
              total_cost: Decimal.new("0.01"),
              recorded_at: later
            })

          r2 =
            build_cost_record(%{
              conversation_id: conv1.id,
              user_id: "lr_user_a",
              provider: :anthropic,
              model: "claude-3",
              total_cost: Decimal.new("0.02"),
              recorded_at: earlier
            })

          r3 =
            build_cost_record(%{
              conversation_id: conv2.id,
              user_id: "lr_user_b",
              provider: :openai,
              model: "gpt-3.5",
              total_cost: Decimal.new("0.005"),
              recorded_at: now
            })

          {:ok, _} = @cost_adapter.save_cost_record(r1, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r2, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r3, opts)

          {:ok,
           conv1: conv1,
           conv2: conv2,
           now: now,
           earlier: earlier,
           later: later}
        end

        test "returns all records when no filters (ordered by recorded_at)", %{opts: opts} do
          {:ok, %{records: records, next_cursor: nil}} =
            @cost_adapter.list_cost_records([], opts)

          assert length(records) == 3
          assert Enum.map(records, & &1.model) == ["claude-3", "gpt-3.5", "gpt-4"]
        end

        test "filters by conversation_id", %{opts: opts, conv1: conv1} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([conversation_id: conv1.id], opts)

          assert length(records) == 2
          assert Enum.all?(records, &(&1.conversation_id == conv1.id))
        end

        test "filters by user_id", %{opts: opts} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([user_id: "lr_user_b"], opts)

          assert length(records) == 1
          assert hd(records).model == "gpt-3.5"
        end

        test "filters by provider", %{opts: opts} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([provider: :anthropic], opts)

          assert length(records) == 1
          assert hd(records).model == "claude-3"
        end

        test "filters by model", %{opts: opts} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([model: "gpt-4"], opts)

          assert length(records) == 1
          assert hd(records).provider == :openai
        end

        test "filters by after date", %{opts: opts, now: now} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([after: now], opts)

          assert length(records) == 2
        end

        test "filters by before date", %{opts: opts, now: now} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([before: now], opts)

          assert length(records) == 2
        end

        test "combines multiple filters", %{opts: opts, now: now} do
          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records(
              [user_id: "lr_user_a", provider: :openai, after: now],
              opts
            )

          assert length(records) == 1
          assert hd(records).model == "gpt-4"
        end

        test "cursor pagination — first page with limit", %{opts: opts} do
          {:ok, %{records: records, next_cursor: cursor}} =
            @cost_adapter.list_cost_records([limit: 2], opts)

          assert length(records) == 2
          assert is_binary(cursor)
          assert Enum.map(records, & &1.model) == ["claude-3", "gpt-3.5"]
        end

        test "cursor pagination — second page using cursor", %{opts: opts} do
          {:ok, %{records: _, next_cursor: cursor}} =
            @cost_adapter.list_cost_records([limit: 2], opts)

          {:ok, %{records: page2, next_cursor: nil}} =
            @cost_adapter.list_cost_records([limit: 2, cursor: cursor], opts)

          assert length(page2) == 1
          assert hd(page2).model == "gpt-4"
        end

        test "cursor pagination — exhausted returns nil cursor", %{opts: opts} do
          {:ok, %{records: _, next_cursor: nil}} =
            @cost_adapter.list_cost_records([limit: 10], opts)
        end

        test "invalid cursor returns error", %{opts: opts} do
          assert {:error, :invalid_cursor} =
                   @cost_adapter.list_cost_records([cursor: "garbage!!!"], opts)
        end

        test "records with same recorded_at sort stably by id", %{opts: opts} do
          conv = build_conversation()
          {:ok, conv} = @adapter.save_conversation(conv, opts)

          same_time = ~U[2026-06-01 00:00:00.000000Z]

          ids =
            for _ <- 1..3 do
              id = Uniq.UUID.uuid7()

              record =
                build_cost_record(%{
                  id: id,
                  conversation_id: conv.id,
                  recorded_at: same_time
                })

              {:ok, _} = @cost_adapter.save_cost_record(record, opts)
              id
            end

          {:ok, %{records: records}} =
            @cost_adapter.list_cost_records([conversation_id: conv.id, after: same_time], opts)

          returned_ids = Enum.map(records, & &1.id)
          assert returned_ids == Enum.sort(returned_ids)
        end

        test "returns empty for no matches", %{opts: opts} do
          {:ok, %{records: [], next_cursor: nil}} =
            @cost_adapter.list_cost_records([user_id: "nonexistent_xyz"], opts)
        end
      end

      describe "count_cost_records/2" do
        setup %{opts: opts} do
          conv = build_conversation(%{user_id: "count_user"})
          {:ok, conv} = @adapter.save_conversation(conv, opts)

          for i <- 1..3 do
            record =
              build_cost_record(%{
                conversation_id: conv.id,
                user_id: "count_user",
                provider: if(rem(i, 2) == 0, do: :anthropic, else: :openai),
                recorded_at: DateTime.add(DateTime.utc_now(), i, :second)
              })

            {:ok, _} = @cost_adapter.save_cost_record(record, opts)
          end

          {:ok, conv: conv}
        end

        test "counts all records with no filters", %{opts: opts} do
          {:ok, count} = @cost_adapter.count_cost_records([], opts)
          assert count >= 3
        end

        test "counts with filters", %{opts: opts} do
          {:ok, count} =
            @cost_adapter.count_cost_records([user_id: "count_user", provider: :openai], opts)

          assert count == 2
        end
      end
```

- [ ] **Step 4: Run the full test suite**

Run: `mix test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add test/phoenix_ai/store/cost_tracking_test.exs test/phoenix_ai/store/guardrails/cost_budget_test.exs test/support/cost_store_contract_test.ex
git commit -m "test(cost): update stubs and contract tests for list/count_cost_records"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite with warnings-as-errors**

Run: `mix test && mix compile --warnings-as-errors`
Expected: All tests PASS, no compilation warnings

- [ ] **Step 2: Run formatter**

Run: `mix format`
Expected: No changes (code was already formatted)

- [ ] **Step 3: Run static analysis if available**

Run: `mix credo --strict 2>&1 || true`
Expected: No new issues

- [ ] **Step 4: Final commit if any formatting changes**

```bash
git add -A && git diff --cached --quiet || git commit -m "style: format cost query API changes"
```

---

## Task Dependency Order

```
Task 1 (Cursor module) → Task 2 (EventLog migration) → Task 3 (Behaviour)
                                                          ↓
                                                   Task 4 (Ecto) + Task 5 (ETS) [parallel]
                                                          ↓
                                                   Task 6 (Facade)
                                                          ↓
                                                   Task 7 (Tests)
                                                          ↓
                                                   Task 8 (Verification)
```

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| COST-01: Query without conversation_id | Tasks 4, 5, 6 |
| COST-02: Cursor-based pagination | Tasks 1, 4, 5 |
| COST-03: Count without loading records | Tasks 4, 5, 6 |
| COST-04: CostStore behaviour updated | Task 3 |
| ADPT-01: Ecto list_cost_records | Task 4 |
| ADPT-02: ETS list_cost_records | Task 5 |
| ADPT-03: Ecto count_cost_records | Task 4 |
| ADPT-04: ETS count_cost_records | Task 5 |

MIGR-01 and MIGR-02 are Phase 12 scope.
