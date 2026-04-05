# Phase 7: Event Log — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an append-only event log that automatically records significant actions with configurable redaction and cursor-based pagination.

**Architecture:** Thin EventLog orchestrator wraps adapter calls with fire-and-forget semantics. Events are immutable (no update/delete in sub-behaviour). Inline logging hooks into existing facade functions when `event_log.enabled: true`. Cursor pagination uses Base64-encoded `(inserted_at, id)` composite keys.

**Tech Stack:** Elixir, phoenix_ai ~> 0.3.1, Ecto (optional), NimbleOptions, Telemetry

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/event_log/event.ex` | Create | Event struct |
| `lib/phoenix_ai/store/event_log.ex` | Create | Orchestrator (log/3, list/2, cursor encode/decode, redaction) |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Add EventStore sub-behaviour |
| `test/support/event_store_contract_test.ex` | Create | Shared contract tests |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement EventStore |
| `lib/phoenix_ai/store/schemas/event.ex` | Create | Ecto schema |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement EventStore |
| `priv/templates/events_migration.exs.eex` | Create | Migration template |
| `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` | Modify | Add --events flag |
| `lib/phoenix_ai/store/config.ex` | Modify | Add event_log section |
| `lib/phoenix_ai/store.ex` | Modify | Add log_event/2, list_events/2, count_events/2, inline logging |

---

## Task 1: Event Struct

**Files:**
- Create: `lib/phoenix_ai/store/event_log/event.ex`

- [ ] **Step 1: Create Event struct**

```elixir
defmodule PhoenixAI.Store.EventLog.Event do
  @moduledoc """
  An immutable event record in the append-only event log.

  Events capture significant actions (message sent, cost recorded,
  policy violation, etc.) with a `type` atom and a `data` map
  containing type-specific payload.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          conversation_id: String.t() | nil,
          user_id: String.t() | nil,
          type: atom(),
          data: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :type,
    :inserted_at,
    data: %{},
    metadata: %{}
  ]
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean compilation

- [ ] **Step 3: Commit**

```bash
git add lib/phoenix_ai/store/event_log/event.ex
git commit -m "feat(events): add Event struct"
```

---

## Task 2: EventStore Sub-behaviour + Contract Tests

**Files:**
- Modify: `lib/phoenix_ai/store/adapter.ex`
- Create: `test/support/event_store_contract_test.ex`

- [ ] **Step 1: Write contract tests**

Create `test/support/event_store_contract_test.ex`:

```elixir
defmodule PhoenixAI.Store.EventStoreContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.EventStore`.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.{Conversation, Message}
      alias PhoenixAI.Store.EventLog.Event

      @adapter unquote(macro_opts[:adapter])

      defp build_event(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          conversation_id: Uniq.UUID.uuid7(),
          user_id: "event_user",
          type: :message_sent,
          data: %{role: :user, content: "Hello"},
          metadata: %{},
          inserted_at: DateTime.utc_now()
        }

        struct(Event, Map.merge(defaults, attrs))
      end

      describe "EventStore: log_event/2" do
        test "saves and returns an event", %{opts: opts} do
          event = build_event()
          assert {:ok, %Event{} = saved} = @adapter.log_event(event, opts)
          assert saved.type == :message_sent
          assert saved.data == %{role: :user, content: "Hello"}
        end
      end

      describe "EventStore: list_events/2" do
        test "returns events ordered by inserted_at asc", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          now = DateTime.utc_now()

          e1 = build_event(%{conversation_id: conv_id, type: :conversation_created, inserted_at: now})
          e2 = build_event(%{conversation_id: conv_id, type: :message_sent, inserted_at: DateTime.add(now, 1, :second)})
          e3 = build_event(%{conversation_id: conv_id, type: :cost_recorded, inserted_at: DateTime.add(now, 2, :second)})

          {:ok, _} = @adapter.log_event(e1, opts)
          {:ok, _} = @adapter.log_event(e2, opts)
          {:ok, _} = @adapter.log_event(e3, opts)

          assert {:ok, %{events: events, next_cursor: _}} =
                   @adapter.list_events([conversation_id: conv_id], opts)

          assert length(events) == 3
          assert hd(events).type == :conversation_created
          assert List.last(events).type == :cost_recorded
        end

        test "filters by conversation_id", %{opts: opts} do
          conv1 = Uniq.UUID.uuid7()
          conv2 = Uniq.UUID.uuid7()

          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv1}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv2}), opts)

          assert {:ok, %{events: events}} = @adapter.list_events([conversation_id: conv1], opts)
          assert length(events) == 1
          assert hd(events).conversation_id == conv1
        end

        test "filters by type", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, type: :message_sent}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, type: :cost_recorded}), opts)

          assert {:ok, %{events: events}} = @adapter.list_events([conversation_id: conv_id, type: :message_sent], opts)
          assert length(events) == 1
          assert hd(events).type == :message_sent
        end

        test "filters by user_id", %{opts: opts} do
          {:ok, _} = @adapter.log_event(build_event(%{user_id: "alice"}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{user_id: "bob"}), opts)

          assert {:ok, %{events: events}} = @adapter.list_events([user_id: "alice"], opts)
          assert length(events) == 1
          assert hd(events).user_id == "alice"
        end

        test "cursor-based pagination", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          now = DateTime.utc_now()

          for i <- 1..5 do
            {:ok, _} = @adapter.log_event(
              build_event(%{
                conversation_id: conv_id,
                type: :message_sent,
                inserted_at: DateTime.add(now, i, :second),
                data: %{index: i}
              }),
              opts
            )
          end

          # Page 1: first 2 events
          assert {:ok, %{events: page1, next_cursor: cursor1}} =
                   @adapter.list_events([conversation_id: conv_id, limit: 2], opts)

          assert length(page1) == 2
          assert hd(page1).data.index == 1
          assert cursor1 != nil

          # Page 2: next 2 events
          assert {:ok, %{events: page2, next_cursor: cursor2}} =
                   @adapter.list_events([conversation_id: conv_id, limit: 2, cursor: cursor1], opts)

          assert length(page2) == 2
          assert hd(page2).data.index == 3
          assert cursor2 != nil

          # Page 3: last event
          assert {:ok, %{events: page3, next_cursor: cursor3}} =
                   @adapter.list_events([conversation_id: conv_id, limit: 2, cursor: cursor2], opts)

          assert length(page3) == 1
          assert hd(page3).data.index == 5
          assert cursor3 == nil
        end

        test "returns empty result with no events", %{opts: opts} do
          assert {:ok, %{events: [], next_cursor: nil}} =
                   @adapter.list_events([conversation_id: "nonexistent"], opts)
        end

        test "filters by time range", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          now = DateTime.utc_now()

          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, inserted_at: now}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, inserted_at: DateTime.add(now, 60, :second)}), opts)

          future = DateTime.add(now, 30, :second)
          assert {:ok, %{events: events}} = @adapter.list_events([conversation_id: conv_id, after: future], opts)
          assert length(events) == 1
        end
      end

      describe "EventStore: count_events/2" do
        test "counts events matching filters", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()

          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, type: :message_sent}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, type: :message_sent}), opts)
          {:ok, _} = @adapter.log_event(build_event(%{conversation_id: conv_id, type: :cost_recorded}), opts)

          assert {:ok, 3} = @adapter.count_events([conversation_id: conv_id], opts)
          assert {:ok, 2} = @adapter.count_events([conversation_id: conv_id, type: :message_sent], opts)
        end

        test "returns 0 for no matches", %{opts: opts} do
          assert {:ok, 0} = @adapter.count_events([conversation_id: "nonexistent"], opts)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Add EventStore sub-behaviour to adapter.ex**

Add inside `lib/phoenix_ai/store/adapter.ex`, after the `CostStore` sub-behaviour:

```elixir
defmodule EventStore do
  @moduledoc """
  Sub-behaviour for adapters that support the append-only event log.

  No update or delete callbacks — events are immutable once written.
  """

  alias PhoenixAI.Store.EventLog.Event

  @callback log_event(Event.t(), keyword()) ::
              {:ok, Event.t()} | {:error, term()}

  @callback list_events(filters :: keyword(), keyword()) ::
              {:ok, %{events: [Event.t()], next_cursor: String.t() | nil}}

  @callback count_events(filters :: keyword(), keyword()) ::
              {:ok, non_neg_integer()}
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapter.ex test/support/event_store_contract_test.ex
git commit -m "feat(events): add EventStore sub-behaviour + contract tests"
```

---

## Task 3: ETS Adapter — EventStore + Cursor Pagination

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex`
- Modify: `test/phoenix_ai/store/adapters/ets_test.exs`

- [ ] **Step 1: Wire contract tests**

Add to `test/phoenix_ai/store/adapters/ets_test.exs`:

```elixir
use PhoenixAI.Store.EventStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep "EventStore"`
Expected: FAIL

- [ ] **Step 3: Implement EventStore in ETS adapter**

Add `@behaviour PhoenixAI.Store.Adapter.EventStore` at the top.

Add `alias PhoenixAI.Store.EventLog.Event`.

Add after the CostStore callbacks:

```elixir
# -- EventStore callbacks --

@impl PhoenixAI.Store.Adapter.EventStore
def log_event(%Event{} = event, opts) do
  table = Keyword.fetch!(opts, :table)

  event = %{
    event
    | id: event.id || Uniq.UUID.uuid7(),
      inserted_at: event.inserted_at || DateTime.utc_now()
  }

  :ets.insert(table, {{:event, event.inserted_at, event.id}, event})
  {:ok, event}
end

@impl PhoenixAI.Store.Adapter.EventStore
def list_events(filters, opts) do
  table = Keyword.fetch!(opts, :table)
  limit = Keyword.get(filters, :limit, 50)
  cursor = Keyword.get(filters, :cursor)

  events =
    :ets.match_object(table, {{:event, :_, :_}, :_})
    |> Enum.map(fn {_key, event} -> event end)
    |> filter_events(Keyword.drop(filters, [:limit, :cursor]))
    |> Enum.sort_by(&{&1.inserted_at, &1.id}, fn {ts1, id1}, {ts2, id2} ->
      case DateTime.compare(ts1, ts2) do
        :lt -> true
        :gt -> false
        :eq -> id1 < id2
      end
    end)
    |> maybe_apply_cursor(cursor)
    |> Enum.take(limit)

  next_cursor =
    if length(events) == limit do
      last = List.last(events)
      encode_cursor(last)
    else
      nil
    end

  {:ok, %{events: events, next_cursor: next_cursor}}
end

@impl PhoenixAI.Store.Adapter.EventStore
def count_events(filters, opts) do
  table = Keyword.fetch!(opts, :table)

  count =
    :ets.match_object(table, {{:event, :_, :_}, :_})
    |> Enum.map(fn {_key, event} -> event end)
    |> filter_events(filters)
    |> length()

  {:ok, count}
end

defp filter_events(events, []), do: events

defp filter_events(events, [{:conversation_id, conv_id} | rest]) do
  events |> Enum.filter(&(&1.conversation_id == conv_id)) |> filter_events(rest)
end

defp filter_events(events, [{:user_id, user_id} | rest]) do
  events |> Enum.filter(&(&1.user_id == user_id)) |> filter_events(rest)
end

defp filter_events(events, [{:type, type} | rest]) do
  events |> Enum.filter(&(&1.type == type)) |> filter_events(rest)
end

defp filter_events(events, [{:after, dt} | rest]) do
  events
  |> Enum.filter(&(DateTime.compare(&1.inserted_at, dt) in [:gt, :eq]))
  |> filter_events(rest)
end

defp filter_events(events, [{:before, dt} | rest]) do
  events
  |> Enum.filter(&(DateTime.compare(&1.inserted_at, dt) in [:lt, :eq]))
  |> filter_events(rest)
end

defp filter_events(events, [_ | rest]), do: filter_events(events, rest)

defp maybe_apply_cursor(events, nil), do: events

defp maybe_apply_cursor(events, cursor) do
  {cursor_ts, cursor_id} = decode_cursor(cursor)

  Enum.drop_while(events, fn event ->
    case DateTime.compare(event.inserted_at, cursor_ts) do
      :lt -> true
      :gt -> false
      :eq -> event.id <= cursor_id
    end
  end)
end

defp encode_cursor(%Event{inserted_at: ts, id: id}) do
  Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
end

defp decode_cursor(cursor) do
  cursor
  |> Base.url_decode64!(padding: false)
  |> String.split("|", parts: 2)
  |> then(fn [ts_str, id] ->
    {:ok, ts, _} = DateTime.from_iso8601(ts_str)
    {ts, id}
  end)
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep -E "(EventStore|passed|failed)"`
Expected: All EventStore tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex test/phoenix_ai/store/adapters/ets_test.exs
git commit -m "feat(events): implement EventStore in ETS adapter with cursor pagination"
```

---

## Task 4: Ecto Schema + Adapter + Migration

**Files:**
- Create: `lib/phoenix_ai/store/schemas/event.ex`
- Create: `priv/templates/events_migration.exs.eex`
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex`
- Modify: `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`
- Modify: `test/phoenix_ai/store/adapters/ecto_test.exs`

- [ ] **Step 1: Create Ecto schema**

Create `lib/phoenix_ai/store/schemas/event.ex`:

```elixir
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Event do
    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.EventLog.Event, as: StoreEvent

    @primary_key {:id, :binary_id, autogenerate: false}

    schema "phoenix_ai_store_events" do
      field :conversation_id, :binary_id
      field :user_id, :string
      field :type, :string
      field :data, :map, default: %{}
      field :metadata, :map, default: %{}
      field :inserted_at, :utc_datetime_usec
    end

    @cast_fields ~w(id conversation_id user_id type data metadata inserted_at)a
    @required_fields ~w(type inserted_at)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreEvent{
        id: schema.id,
        conversation_id: schema.conversation_id,
        user_id: schema.user_id,
        type: safe_to_atom(schema.type),
        data: atomize_keys(schema.data || %{}),
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at
      }
    end

    def from_store_struct(%StoreEvent{} = event) do
      %{
        id: event.id,
        conversation_id: event.conversation_id,
        user_id: event.user_id,
        type: to_string(event.type),
        data: stringify_keys(event.data),
        metadata: event.metadata,
        inserted_at: event.inserted_at
      }
    end

    defp safe_to_atom(nil), do: nil
    defp safe_to_atom(str) when is_binary(str), do: String.to_existing_atom(str)
    defp safe_to_atom(atom) when is_atom(atom), do: atom

    defp atomize_keys(map) when is_map(map) do
      Map.new(map, fn
        {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
        {k, v} -> {k, v}
      end)
    rescue
      _ -> map
    end

    defp stringify_keys(map) when is_map(map) do
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end
  end
end
```

- [ ] **Step 2: Create migration template**

Create `priv/templates/events_migration.exs.eex`:

```elixir
defmodule <%= @repo_module %>.Migrations.Add<%= @migration_module %>EventsTables do
  use Ecto.Migration

  def change do
    create table(:<%= @prefix %>events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, :binary_id
      add :user_id, :string
      add :type, :string, null: false
      add :data, :map, default: %{}
      add :metadata, :map, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:<%= @prefix %>events, [:conversation_id])
    create index(:<%= @prefix %>events, [:user_id])
    create index(:<%= @prefix %>events, [:inserted_at])
    create index(:<%= @prefix %>events, [:inserted_at, :id])
    create index(:<%= @prefix %>events, [:conversation_id, :inserted_at])
  end
end
```

Note: Postgres RULE for append-only enforcement is omitted from the default migration to keep it portable (SQLite3 doesn't support RULEs). The `@moduledoc` in the EventStore sub-behaviour documents the append-only contract. Users who need database-level enforcement can add RULEs manually.

- [ ] **Step 3: Add --events flag to migration generator**

In `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`, add `events: :boolean` to OptionParser, add `events_only = Keyword.get(opts, :events, false)`, extend the cond with `events_only -> generate_events_migration(...)`, and add `generate_events_migration/3`, `find_events_template/0`, `fallback_events_template_path/0` following the exact LTM/cost pattern.

- [ ] **Step 4: Implement EventStore in Ecto adapter**

Add `@behaviour PhoenixAI.Store.Adapter.EventStore` at the top.

Add aliases: `alias PhoenixAI.Store.Schemas.Event, as: EventSchema` and `alias PhoenixAI.Store.EventLog.Event`.

Add after CostStore callbacks:

```elixir
# -- EventStore --

@impl PhoenixAI.Store.Adapter.EventStore
def log_event(%Event{} = event, opts) do
  repo = Keyword.fetch!(opts, :repo)
  attrs = EventSchema.from_store_struct(event)

  %EventSchema{}
  |> Ecto.put_meta(source: event_table_name(opts))
  |> EventSchema.changeset(attrs)
  |> repo.insert()
  |> handle_event_result()
end

@impl PhoenixAI.Store.Adapter.EventStore
def list_events(filters, opts) do
  repo = Keyword.fetch!(opts, :repo)
  limit = Keyword.get(filters, :limit, 50)
  cursor = Keyword.get(filters, :cursor)

  query =
    from(e in event_source(opts),
      order_by: [asc: e.inserted_at, asc: e.id],
      limit: ^limit
    )
    |> apply_event_filters(Keyword.drop(filters, [:limit, :cursor]))
    |> maybe_apply_ecto_cursor(cursor)

  events =
    repo.all(query)
    |> Enum.map(&EventSchema.to_store_struct/1)

  next_cursor =
    if length(events) == limit do
      last = List.last(events)
      encode_cursor(last)
    else
      nil
    end

  {:ok, %{events: events, next_cursor: next_cursor}}
end

@impl PhoenixAI.Store.Adapter.EventStore
def count_events(filters, opts) do
  repo = Keyword.fetch!(opts, :repo)

  query =
    from(e in event_source(opts), select: count(e.id))
    |> apply_event_filters(filters)

  {:ok, repo.one(query)}
end

defp apply_event_filters(query, []), do: query

defp apply_event_filters(query, [{:conversation_id, conv_id} | rest]) do
  query |> where([e], e.conversation_id == ^conv_id) |> apply_event_filters(rest)
end

defp apply_event_filters(query, [{:user_id, user_id} | rest]) do
  query |> where([e], e.user_id == ^user_id) |> apply_event_filters(rest)
end

defp apply_event_filters(query, [{:type, type} | rest]) do
  query |> where([e], e.type == ^to_string(type)) |> apply_event_filters(rest)
end

defp apply_event_filters(query, [{:after, dt} | rest]) do
  query |> where([e], e.inserted_at >= ^dt) |> apply_event_filters(rest)
end

defp apply_event_filters(query, [{:before, dt} | rest]) do
  query |> where([e], e.inserted_at <= ^dt) |> apply_event_filters(rest)
end

defp apply_event_filters(query, [_ | rest]), do: apply_event_filters(query, rest)

defp maybe_apply_ecto_cursor(query, nil), do: query

defp maybe_apply_ecto_cursor(query, cursor) do
  {cursor_ts, cursor_id} = decode_cursor(cursor)

  query
  |> where([e], e.inserted_at > ^cursor_ts or (e.inserted_at == ^cursor_ts and e.id > ^cursor_id))
end

defp event_source(opts), do: {event_table_name(opts), EventSchema}
defp event_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "events"

defp handle_event_result({:ok, schema}), do: {:ok, EventSchema.to_store_struct(schema)}
defp handle_event_result({:error, changeset}), do: {:error, changeset}

defp encode_cursor(%Event{inserted_at: ts, id: id}) do
  Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
end

defp decode_cursor(cursor) do
  cursor
  |> Base.url_decode64!(padding: false)
  |> String.split("|", parts: 2)
  |> then(fn [ts_str, id] ->
    {:ok, ts, _} = DateTime.from_iso8601(ts_str)
    {ts, id}
  end)
end
```

- [ ] **Step 5: Wire contract tests, generate + run migration**

Add to `test/phoenix_ai/store/adapters/ecto_test.exs`:

```elixir
use PhoenixAI.Store.EventStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
```

Run:
```bash
mix phoenix_ai_store.gen.migration --events
mix ecto.migrate
```

- [ ] **Step 6: Run all tests**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/store/schemas/event.ex lib/phoenix_ai/store/adapters/ecto.ex lib/phoenix_ai/store/adapters/ets.ex priv/templates/events_migration.exs.eex lib/mix/tasks/phoenix_ai_store.gen.migration.ex test/phoenix_ai/store/adapters/ets_test.exs test/phoenix_ai/store/adapters/ecto_test.exs
git commit -m "feat(events): implement EventStore in ETS and Ecto adapters"
```

---

## Task 5: EventLog Orchestrator + Redaction

**Files:**
- Create: `lib/phoenix_ai/store/event_log.ex`
- Create: `test/phoenix_ai/store/event_log_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/event_log_test.exs`:

```elixir
defmodule PhoenixAI.Store.EventLogTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.EventLog
  alias PhoenixAI.Store.EventLog.Event

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.EventStore

    @impl true
    def log_event(event, _opts), do: {:ok, event}

    @impl true
    def list_events(_filters, _opts), do: {:ok, %{events: [], next_cursor: nil}}

    @impl true
    def count_events(_filters, _opts), do: {:ok, 0}
  end

  defmodule NoEventAdapter do
  end

  describe "log/3" do
    test "builds and saves an event" do
      opts = [adapter: StubAdapter, adapter_opts: []]

      assert {:ok, %Event{} = event} =
               EventLog.log(:message_sent, %{role: :user, content: "Hi"}, opts)

      assert event.type == :message_sent
      assert event.data == %{role: :user, content: "Hi"}
      assert event.id != nil
      assert event.inserted_at != nil
    end

    test "applies redact_fn before saving" do
      redact_fn = fn %Event{data: data} = event ->
        %{event | data: Map.put(data, :content, "[REDACTED]")}
      end

      opts = [adapter: StubAdapter, adapter_opts: [], redact_fn: redact_fn]

      assert {:ok, %Event{data: data}} =
               EventLog.log(:message_sent, %{role: :user, content: "Secret PII"}, opts)

      assert data.content == "[REDACTED]"
    end

    test "passes through when redact_fn is nil" do
      opts = [adapter: StubAdapter, adapter_opts: [], redact_fn: nil]

      assert {:ok, %Event{data: data}} =
               EventLog.log(:message_sent, %{content: "Visible"}, opts)

      assert data.content == "Visible"
    end

    test "returns error when adapter doesn't support EventStore" do
      opts = [adapter: NoEventAdapter, adapter_opts: []]

      assert {:error, :event_store_not_supported} =
               EventLog.log(:message_sent, %{}, opts)
    end

    test "passes conversation_id and user_id" do
      opts = [adapter: StubAdapter, adapter_opts: [], conversation_id: "conv_1", user_id: "user_1"]

      assert {:ok, %Event{conversation_id: "conv_1", user_id: "user_1"}} =
               EventLog.log(:message_sent, %{}, opts)
    end
  end

  describe "cursor encoding/decoding" do
    test "round-trips correctly" do
      now = DateTime.utc_now()
      event = %Event{id: "test-id-123", inserted_at: now}

      cursor = EventLog.encode_cursor(event)
      assert is_binary(cursor)

      {decoded_ts, decoded_id} = EventLog.decode_cursor(cursor)
      assert decoded_id == "test-id-123"
      assert DateTime.compare(decoded_ts, DateTime.truncate(now, :second)) in [:eq, :gt]
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/event_log_test.exs`
Expected: FAIL — `EventLog` not defined

- [ ] **Step 3: Implement EventLog orchestrator**

Create `lib/phoenix_ai/store/event_log.ex`:

```elixir
defmodule PhoenixAI.Store.EventLog do
  @moduledoc """
  Orchestrates event logging with optional redaction.

  Builds `Event` structs, applies configured `redact_fn`, and
  delegates to the adapter's `EventStore` sub-behaviour.
  Fire-and-forget semantics — callers wrap in try/rescue.
  """

  alias PhoenixAI.Store.EventLog.Event

  @doc "Logs an event. Returns `{:ok, Event.t()}` or `{:error, term()}`."
  @spec log(atom(), map(), keyword()) :: {:ok, Event.t()} | {:error, term()}
  def log(type, data, opts) do
    with {:ok, adapter, adapter_opts} <- resolve_adapter(opts),
         :ok <- check_event_store_support(adapter) do
      event = build_event(type, data, opts)
      event = maybe_redact(event, Keyword.get(opts, :redact_fn))

      :telemetry.span([:phoenix_ai_store, :event, :log], %{type: type}, fn ->
        result = adapter.log_event(event, adapter_opts)
        {result, %{type: type}}
      end)
    end
  end

  @doc "Encodes an event as an opaque cursor string."
  @spec encode_cursor(Event.t()) :: String.t()
  def encode_cursor(%Event{inserted_at: ts, id: id}) do
    Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  @doc "Decodes a cursor string to `{DateTime.t(), id}`."
  @spec decode_cursor(String.t()) :: {DateTime.t(), String.t()}
  def decode_cursor(cursor) do
    cursor
    |> Base.url_decode64!(padding: false)
    |> String.split("|", parts: 2)
    |> then(fn [ts_str, id] ->
      {:ok, ts, _} = DateTime.from_iso8601(ts_str)
      {ts, id}
    end)
  end

  # -- Private --

  defp resolve_adapter(opts) do
    case {Keyword.get(opts, :adapter), Keyword.get(opts, :adapter_opts)} do
      {nil, _} -> {:error, :no_adapter}
      {adapter, adapter_opts} -> {:ok, adapter, adapter_opts || []}
    end
  end

  defp check_event_store_support(adapter) do
    if function_exported?(adapter, :log_event, 2) do
      :ok
    else
      {:error, :event_store_not_supported}
    end
  end

  defp build_event(type, data, opts) do
    %Event{
      id: Uniq.UUID.uuid7(),
      conversation_id: Keyword.get(opts, :conversation_id),
      user_id: Keyword.get(opts, :user_id),
      type: type,
      data: data,
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: DateTime.utc_now()
    }
  end

  defp maybe_redact(event, nil), do: event
  defp maybe_redact(event, redact_fn) when is_function(redact_fn, 1), do: redact_fn.(event)
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/event_log_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/event_log.ex test/phoenix_ai/store/event_log_test.exs
git commit -m "feat(events): add EventLog orchestrator with redaction"
```

---

## Task 6: Config + Store Facade + Inline Logging

**Files:**
- Modify: `lib/phoenix_ai/store/config.ex`
- Modify: `lib/phoenix_ai/store.ex`
- Create: `test/phoenix_ai/store/events_integration_test.exs`

- [ ] **Step 1: Write integration tests**

Create `test/phoenix_ai/store/events_integration_test.exs`:

```elixir
defmodule PhoenixAI.Store.EventsIntegrationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.EventLog.Event

  setup do
    store = :"events_test_#{System.unique_integer([:positive])}"

    {:ok, _} =
      Store.start_link(
        name: store,
        adapter: PhoenixAI.Store.Adapters.ETS,
        event_log: [enabled: true]
      )

    {:ok, store: store}
  end

  describe "inline event logging" do
    test "save_conversation logs :conversation_created", %{store: store} do
      conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "ev_user", title: "Test", messages: []}
      {:ok, _} = Store.save_conversation(conv, store: store)

      {:ok, %{events: events}} = Store.list_events([conversation_id: conv.id], store: store)
      assert Enum.any?(events, &(&1.type == :conversation_created))
    end

    test "add_message logs :message_sent", %{store: store} do
      conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "ev_user", title: "Test", messages: []}
      {:ok, _} = Store.save_conversation(conv, store: store)

      {:ok, _} = Store.add_message(conv.id, %Message{role: :user, content: "Hi", token_count: 5}, store: store)

      {:ok, %{events: events}} = Store.list_events([conversation_id: conv.id, type: :message_sent], store: store)
      assert length(events) == 1
      assert hd(events).data.role == :user
    end
  end

  describe "explicit log_event/2" do
    test "logs custom event", %{store: store} do
      event = %Event{
        type: :custom_action,
        data: %{action: "manual_log"},
        user_id: "ev_user"
      }

      assert {:ok, %Event{type: :custom_action}} = Store.log_event(event, store: store)
    end
  end

  describe "list_events/2 with cursor pagination" do
    test "paginates through events", %{store: store} do
      conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "ev_user", title: "Test", messages: []}
      {:ok, _} = Store.save_conversation(conv, store: store)

      # Add several messages to generate events
      for i <- 1..5 do
        {:ok, _} = Store.add_message(
          conv.id,
          %Message{role: :user, content: "msg #{i}", token_count: i},
          store: store
        )
      end

      # Page 1 (includes conversation_created + 5 message_sent = 6 total, get first 3)
      {:ok, %{events: page1, next_cursor: cursor}} =
        Store.list_events([conversation_id: conv.id, limit: 3], store: store)

      assert length(page1) == 3
      assert cursor != nil

      # Page 2
      {:ok, %{events: page2, next_cursor: cursor2}} =
        Store.list_events([conversation_id: conv.id, limit: 3, cursor: cursor], store: store)

      assert length(page2) == 3
      assert cursor2 == nil  # last page
    end
  end

  describe "redaction" do
    test "redact_fn strips PII before persistence" do
      store = :"redact_test_#{System.unique_integer([:positive])}"

      redact_fn = fn
        %Event{type: :message_sent, data: data} = event ->
          %{event | data: Map.put(data, :content, "[REDACTED]")}

        event ->
          event
      end

      {:ok, _} =
        Store.start_link(
          name: store,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: true, redact_fn: redact_fn]
        )

      conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "ev_user", title: "Test", messages: []}
      {:ok, _} = Store.save_conversation(conv, store: store)

      {:ok, _} = Store.add_message(
        conv.id,
        %Message{role: :user, content: "My SSN is 123-45-6789", token_count: 10},
        store: store
      )

      {:ok, %{events: events}} = Store.list_events([conversation_id: conv.id, type: :message_sent], store: store)
      assert hd(events).data.content == "[REDACTED]"
    end
  end

  describe "event_log disabled" do
    test "no events logged when disabled" do
      store = :"disabled_test_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Store.start_link(
          name: store,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: false]
        )

      conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "ev_user", title: "Test", messages: []}
      {:ok, _} = Store.save_conversation(conv, store: store)

      {:ok, %{events: events}} = Store.list_events([conversation_id: conv.id], store: store)
      assert events == []
    end
  end
end
```

- [ ] **Step 2: Add event_log config section**

In `lib/phoenix_ai/store/config.ex`, add after the `cost_tracking` key:

```elixir
event_log: [
  type: :keyword_list,
  default: [],
  doc: "Event log configuration.",
  keys: [
    enabled: [type: :boolean, default: false, doc: "Enable event logging."],
    redact_fn: [
      type: {:or, [{:fun, 1}, nil]},
      default: nil,
      doc: "Function `(Event.t()) -> Event.t()` to redact sensitive data before persistence."
    ]
  ]
]
```

- [ ] **Step 3: Add facade functions and inline logging to store.ex**

Add `alias PhoenixAI.Store.EventLog` and `alias PhoenixAI.Store.EventLog.Event` at the top.

Add facade functions after the Cost Tracking section:

```elixir
# -- Event Log Facade --

@doc "Logs an event to the event log."
@spec log_event(Event.t(), keyword()) :: {:ok, Event.t()} | {:error, term()}
def log_event(%Event{} = event, opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :event, :log], %{}, fn ->
    {adapter, adapter_opts, config} = resolve_adapter(opts)

    event_opts =
      [adapter: adapter, adapter_opts: adapter_opts]
      |> Keyword.put(:conversation_id, event.conversation_id)
      |> Keyword.put(:user_id, event.user_id)
      |> Keyword.put(:redact_fn, get_in(config, [:event_log, :redact_fn]))

    result = EventLog.log(event.type, event.data, event_opts)
    {result, %{}}
  end)
end

@doc "Lists events with cursor-based pagination."
@spec list_events(keyword(), keyword()) ::
        {:ok, %{events: [Event.t()], next_cursor: String.t() | nil}} | {:error, term()}
def list_events(filters \\ [], opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :event, :list], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    result =
      if function_exported?(adapter, :list_events, 2) do
        adapter.list_events(filters, adapter_opts)
      else
        {:error, :event_store_not_supported}
      end

    {result, %{}}
  end)
end

@doc "Counts events matching filters."
@spec count_events(keyword(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
def count_events(filters \\ [], opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :event, :count], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    result =
      if function_exported?(adapter, :count_events, 2) do
        adapter.count_events(filters, adapter_opts)
      else
        {:error, :event_store_not_supported}
      end

    {result, %{}}
  end)
end
```

Add private helper for inline fire-and-forget logging:

```elixir
defp maybe_log_event(type, data, opts) do
  {_adapter, _adapter_opts, config} = resolve_adapter(opts)

  if get_in(config, [:event_log, :enabled]) do
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    event_opts =
      [adapter: adapter, adapter_opts: adapter_opts]
      |> Keyword.merge(Keyword.take(data, [:conversation_id, :user_id]))
      |> Keyword.put(:redact_fn, get_in(config, [:event_log, :redact_fn]))

    try do
      EventLog.log(type, Map.drop(data, [:conversation_id, :user_id]), event_opts)
    rescue
      e -> require Logger; Logger.warning("Event log failed: #{inspect(e)}")
    end
  end

  :ok
end
```

Then add `maybe_log_event` calls inside existing facade functions:

In `save_conversation/2` — after successful result, before `{result, %{}}`:
```elixir
case result do
  {:ok, saved} ->
    maybe_log_event(:conversation_created, %{
      conversation_id: saved.id,
      user_id: saved.user_id,
      title: saved.title
    }, opts)
  _ -> :ok
end
```

In `add_message/3` — after successful result:
```elixir
case result do
  {:ok, saved_msg} ->
    maybe_log_event(:message_sent, %{
      conversation_id: conversation_id,
      role: saved_msg.role,
      content: saved_msg.content,
      token_count: saved_msg.token_count
    }, opts)
  _ -> :ok
end
```

In `check_guardrails/3` — on error (policy violation):
```elixir
case result do
  {:error, %PhoenixAI.Guardrails.PolicyViolation{} = v} ->
    maybe_log_event(:policy_violation, %{
      conversation_id: request.conversation_id,
      user_id: request.user_id,
      policy: inspect(v.policy),
      reason: v.reason
    }, opts)
  _ -> :ok
end
```

In `record_cost/3` — after successful CostTracking.record result:
```elixir
case result do
  {:ok, saved} ->
    maybe_log_event(:cost_recorded, %{
      conversation_id: conversation_id,
      user_id: saved.user_id,
      provider: saved.provider,
      model: saved.model,
      total_cost: Decimal.to_string(saved.total_cost),
      input_tokens: saved.input_tokens,
      output_tokens: saved.output_tokens
    }, opts)
  _ -> :ok
end
```

In `apply_memory/3` — after successful pipeline run, before converting to PhoenixAI messages:
```elixir
case result do
  {:ok, filtered} ->
    maybe_log_event(:memory_trimmed, %{
      conversation_id: conversation_id,
      before_count: length(messages),
      after_count: length(filtered)
    }, opts)
  _ -> :ok
end
```

- [ ] **Step 4: Run integration tests**

Run: `mix test test/phoenix_ai/store/events_integration_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/config.ex lib/phoenix_ai/store.ex test/phoenix_ai/store/events_integration_test.exs
git commit -m "feat(events): add log_event/2, list_events/2, inline logging + config"
```

---

## Task 7: Final Verification

- [ ] **Step 1: Full test suite**

Run: `mix test`
Expected: All tests pass (307 + ~30 new)

- [ ] **Step 2: Credo**

Run: `mix credo --strict`
Expected: No new issues in event log files

- [ ] **Step 3: Clean compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 4: Commit any cleanup**

Only if needed.

---

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| EVNT-01 (core event types) | Task 6: inline logging (5 types) + Phase 8 (3 types) |
| EVNT-02 (append-only immutable) | Task 2: no update/delete in EventStore behaviour |
| EVNT-03 (cursor-based pagination) | Task 3-4: composite (inserted_at, id) cursor |
| EVNT-04 (configurable redaction) | Task 5: redact_fn in EventLog orchestrator |
| EVNT-05 (Ecto schema with indexes) | Task 4: 5 indexes including composite |
