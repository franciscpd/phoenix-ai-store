# Adapters

PhoenixAI.Store separates its public API from its storage backend. You choose which
adapter to use; the rest of the library works identically.

## Adapter Comparison

| Property | ETS | Ecto |
|---|---|---|
| Persistence | No (in-memory only) | Yes (Postgres / SQLite3) |
| Speed | Very fast (in-process ETS) | Network round-trip |
| Extra deps | None | `ecto`, `ecto_sql`, a DB driver |
| Token budget queries | O(n) full scan | SQL `SUM` aggregate |
| Cost reporting | In-memory filter | SQL `SUM` with filters |
| Event log | In-memory, paginated | SQL, paginated |
| Use case | Dev, test, ephemeral prod | Durable production |

Both adapters implement all sub-behaviours: `FactStore`, `ProfileStore`, `CostStore`,
`EventStore`, and `TokenUsage`.

## ETS Adapter

`PhoenixAI.Store.Adapters.ETS` stores everything in an ETS table owned by a supervised
`TableOwner` GenServer. The store supervisor starts the `TableOwner` automatically.

### When to Use

- Local development and testing
- Production workloads that tolerate losing data on node restart
- High-throughput scenarios where latency matters more than durability

### Configuration

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.ETS}
```

No additional dependencies required. The ETS table is created during `init/1` and
lives as long as the `TableOwner` process.

### Limitations

- All data is lost when the node restarts
- `count_conversations/2` and token-sum operations are O(n) — they materialize the
  full filtered list before counting
- No SQL `SUM` pushdown for cost aggregation — the full cost record list is filtered
  in-process

## Ecto Adapter

`PhoenixAI.Store.Adapters.Ecto` persists all data to a relational database through
an Ecto Repo. It is only compiled when `ecto` is available as a dependency.

### Dependencies

Add to `mix.exs`:

```elixir
{:ecto_sql, "~> 3.13"},
{:postgrex, "~> 0.19"}  # or {:ecto_sqlite3, "~> 0.22"} for SQLite3
```

### Configuration

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.Ecto,
 repo: MyApp.Repo}
```

The `:repo` option is required for the Ecto adapter and must point at an `Ecto.Repo`
module that is already started in your supervision tree.

### Migrations

Generate migration files with the Mix task:

```bash
# Core tables (conversations, messages)
mix phoenix_ai_store.gen.migration

# Optional: long-term memory tables (facts, profiles)
mix phoenix_ai_store.gen.migration --ltm

# Optional: cost tracking tables (cost_records)
mix phoenix_ai_store.gen.migration --cost

# Optional: event log tables (events)
mix phoenix_ai_store.gen.migration --events
```

Supported flags:

| Flag | Tables created |
|---|---|
| (none) | conversations, messages |
| `--ltm` | facts, profiles |
| `--cost` | cost_records |
| `--events` | events |
| `--prefix myapp_ai_` | use a custom table prefix (default: `phoenix_ai_store_`) |
| `--migrations-path priv/repo/migrations` | output directory |

Apply migrations:

```bash
mix ecto.migrate
```

### Table Prefix

All table names are prefixed with `phoenix_ai_store_` by default. Override with the
`:prefix` config option if you want to avoid conflicts or namespace tables per tenant:

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.Ecto,
 repo: MyApp.Repo,
 prefix: "acme_ai_"}
```

The same prefix must be passed to the migration generator:

```bash
mix phoenix_ai_store.gen.migration --prefix acme_ai_
```

## Custom Adapters

Implement `PhoenixAI.Store.Adapter` to build a custom backend (Redis, S3, a
multi-tenant router, etc.).

### Required Behaviour

All adapters must implement the `PhoenixAI.Store.Adapter` callbacks:

```elixir
defmodule MyApp.MyAdapter do
  @behaviour PhoenixAI.Store.Adapter

  alias PhoenixAI.Store.{Conversation, Message}

  @impl true
  def save_conversation(%Conversation{} = conv, opts), do: ...

  @impl true
  def load_conversation(id, opts), do: ...

  @impl true
  def list_conversations(filters, opts), do: ...

  @impl true
  def delete_conversation(id, opts), do: ...

  @impl true
  def count_conversations(filters, opts), do: ...

  @impl true
  def conversation_exists?(id, opts), do: ...

  @impl true
  def add_message(conversation_id, %Message{} = msg, opts), do: ...

  @impl true
  def get_messages(conversation_id, opts), do: ...
end
```

### Optional Sub-Behaviours

Implement these to unlock additional features. Each sub-behaviour is checked at
runtime via `function_exported?/3` — missing callbacks gracefully degrade.

| Sub-behaviour | Enables |
|---|---|
| `PhoenixAI.Store.Adapter.FactStore` | Long-term memory facts (save, get, delete, count) |
| `PhoenixAI.Store.Adapter.ProfileStore` | User profiles (save, load, delete) |
| `PhoenixAI.Store.Adapter.TokenUsage` | TokenBudget guardrail (sum_conversation_tokens, sum_user_tokens) |
| `PhoenixAI.Store.Adapter.CostStore` | Cost tracking (save_cost_record, get_cost_records, sum_cost) |
| `PhoenixAI.Store.Adapter.EventStore` | Append-only event log (log_event, list_events, count_events) |

Example — implementing `FactStore`:

```elixir
@behaviour PhoenixAI.Store.Adapter.FactStore

alias PhoenixAI.Store.LongTermMemory.Fact

@impl PhoenixAI.Store.Adapter.FactStore
def save_fact(%Fact{} = fact, opts), do: ...

@impl PhoenixAI.Store.Adapter.FactStore
def get_facts(user_id, opts), do: ...

@impl PhoenixAI.Store.Adapter.FactStore
def delete_fact(user_id, key, opts), do: ...

@impl PhoenixAI.Store.Adapter.FactStore
def count_facts(user_id, opts), do: ...
```

### Testing Custom Adapters

The built-in ETS adapter is the recommended test double. Prefer starting a real
`PhoenixAI.Store` with `adapter: PhoenixAI.Store.Adapters.ETS` in test setup rather
than mocking the adapter behaviour:

```elixir
# test/support/store_case.ex
defmodule MyApp.StoreCase do
  use ExUnit.CaseTemplate

  setup do
    {:ok, _pid} =
      start_supervised(
        {PhoenixAI.Store,
         name: :test_store,
         adapter: PhoenixAI.Store.Adapters.ETS}
      )

    %{store: :test_store}
  end
end
```

Use `Mox` when you need to verify specific adapter call patterns:

```elixir
# test/support/mocks.ex
Mox.defmock(MyApp.MockAdapter, for: PhoenixAI.Store.Adapter)
```

## See Also

- [Getting Started](getting-started.html) — initial setup
- [Memory & Guardrails](memory-and-guardrails.html) — how adapters plug into memory pipelines
- [Telemetry & Events](telemetry-and-events.html) — cost and event log persistence
