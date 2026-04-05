# Getting Started

This guide gets you from `mix deps.get` to a working `PhoenixAI.Store.converse/3` call
in under five minutes.

PhoenixAI.Store is a companion library for [PhoenixAI](https://hex.pm/packages/phoenix_ai).
It adds conversation persistence, memory management, guardrails, cost tracking, and an
audit event log. Users who only need `AI.chat/2` directly don't pay for what they don't use.

## Installation

Add `phoenix_ai_store` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_ai, "~> 0.3"},
    {:phoenix_ai_store, "~> 0.1"}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

## Quick Setup with ETS (no database required)

The ETS adapter keeps all data in memory. It is perfect for development, testing, and
production workloads that do not need durability across node restarts.

### 1. Start the store in your supervision tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {PhoenixAI.Store,
       name: :my_store,
       adapter: PhoenixAI.Store.Adapters.ETS,
       converse: [
         provider: :openai,
         model: "gpt-4o",
         api_key: System.get_env("OPENAI_API_KEY")
       ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 2. Create and save a conversation

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.Conversation

conv = %Conversation{title: "My first chat", user_id: "user-123"}
{:ok, conv} = Store.save_conversation(conv, store: :my_store)
```

The `save_conversation/2` call generates a UUID v7 for `conv.id` automatically if
`id` is `nil`, and injects `inserted_at` and `updated_at` timestamps.

### 3. Send a message

```elixir
{:ok, response} = Store.converse(conv.id, "Hello! What can you help me with?", store: :my_store)

IO.puts(response.content)
```

`converse/3` handles the full turn: it saves your user message, loads conversation
history, calls the AI provider, saves the assistant response, and returns the
`%PhoenixAI.Response{}`.

### 4. Reload the conversation

```elixir
{:ok, loaded_conv} = Store.load_conversation(conv.id, store: :my_store)

Enum.each(loaded_conv.messages, fn msg ->
  IO.puts("[#{msg.role}] #{msg.content}")
end)
```

## Setup with Ecto (PostgreSQL persistence)

For production workloads that need data to survive restarts, use the Ecto adapter.

### 1. Add Ecto dependencies

```elixir
def deps do
  [
    {:phoenix_ai, "~> 0.3"},
    {:phoenix_ai_store, "~> 0.1"},
    {:ecto_sql, "~> 3.13"},
    {:postgrex, "~> 0.19"}
  ]
end
```

### 2. Configure your Repo

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  url: System.get_env("DATABASE_URL")

config :my_app, ecto_repos: [MyApp.Repo]
```

### 3. Generate migrations

```bash
mix phoenix_ai_store.gen.migration
mix ecto.migrate
```

For optional subsystems, generate their migrations separately:

```bash
mix phoenix_ai_store.gen.migration --ltm     # long-term memory tables
mix phoenix_ai_store.gen.migration --cost    # cost tracking tables
mix phoenix_ai_store.gen.migration --events  # event log tables
```

### 4. Start the store with the Ecto adapter

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyApp.Repo,
      {PhoenixAI.Store,
       name: :my_store,
       adapter: PhoenixAI.Store.Adapters.Ecto,
       repo: MyApp.Repo,
       converse: [
         provider: :openai,
         model: "gpt-4o",
         api_key: System.get_env("OPENAI_API_KEY")
       ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

The Ecto adapter requires a `:repo` option pointing at your `Ecto.Repo` module.

### 5. Use the same API

The public API is identical regardless of adapter:

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.Conversation

{:ok, conv} = Store.save_conversation(%Conversation{user_id: "u1"}, store: :my_store)
{:ok, response} = Store.converse(conv.id, "Tell me about Elixir", store: :my_store)
```

## Configuration Reference

The full set of options accepted by `PhoenixAI.Store.start_link/1`:

| Option | Type | Default | Description |
|---|---|---|---|
| `:name` | atom | required | Store instance name |
| `:adapter` | atom | required | Adapter module |
| `:repo` | atom | — | Ecto Repo (Ecto adapter only) |
| `:prefix` | string | `"phoenix_ai_store_"` | Table/collection name prefix |
| `:soft_delete` | boolean | `false` | Soft-delete conversations |
| `:user_id_required` | boolean | `false` | Reject conversations without user_id |
| `:converse` | keyword | `[]` | Default options for `converse/3` |
| `:cost_tracking` | keyword | `[]` | Cost tracking config |
| `:event_log` | keyword | `[]` | Event log config |
| `:long_term_memory` | keyword | `[]` | Long-term memory config |

Global defaults can be set in `config.exs` and are merged before validation:

```elixir
config :phoenix_ai_store, :defaults,
  soft_delete: true,
  prefix: "myapp_ai_"
```

## Next Steps

- [Adapters](adapters.html) — choose and configure the right backend
- [Memory & Guardrails](memory-and-guardrails.html) — manage conversation history and enforce budgets
- [Telemetry & Events](telemetry-and-events.html) — observe and audit your AI conversations
