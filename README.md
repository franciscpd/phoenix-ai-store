# PhoenixAI Store

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ai_store.svg)](https://hex.pm/packages/phoenix_ai_store)
[![CI](https://github.com/franciscpd/phoenix-ai-store/actions/workflows/ci.yml/badge.svg)](https://github.com/franciscpd/phoenix-ai-store/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/phoenix_ai_store)

Persistence, memory management, guardrails, cost tracking, and an audit
event log for [PhoenixAI](https://hex.pm/packages/phoenix_ai) conversations.

## Features

- **Conversation Persistence** — ETS (in-memory) and Ecto (PostgreSQL/SQLite) adapters
- **Memory Strategies** — Sliding window, token-aware truncation, pinned messages
- **Guardrails** — Token budgets, cost budgets, and rate limiting before AI calls
- **Cost Tracking** — Per-conversation and per-user cost accumulation with Decimal precision
- **Event Log** — Append-only audit trail with cursor pagination and PII redaction
- **Single-Function Pipeline** — `converse/3` handles load → memory → guardrails → AI → save → track

## Installation

Add `phoenix_ai_store` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_ai_store, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Add to your supervision tree
children = [
  {PhoenixAI.Store, name: :my_store, adapter: PhoenixAI.Store.Adapters.ETS}
]

# Create a conversation
{:ok, conv} = PhoenixAI.Store.save_conversation(
  %PhoenixAI.Store.Conversation{title: "My Chat"},
  store: :my_store
)

# Run the full pipeline
{:ok, response} = PhoenixAI.Store.converse(
  conv.id,
  "Hello!",
  provider: :openai,
  model: "gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY"),
  store: :my_store
)
```

## Documentation

- [Getting Started](https://hexdocs.pm/phoenix_ai_store/getting-started.html) — Installation and first conversation
- [Adapters Guide](https://hexdocs.pm/phoenix_ai_store/adapters.html) — ETS vs Ecto, custom adapters
- [Memory & Guardrails](https://hexdocs.pm/phoenix_ai_store/memory-and-guardrails.html) — Context window management
- [Telemetry & Events](https://hexdocs.pm/phoenix_ai_store/telemetry-and-events.html) — Automatic event capture

## License

MIT — see [LICENSE](LICENSE) for details.
