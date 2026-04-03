# Stack Research

**Domain:** AI conversation persistence & governance (Elixir hex library)
**Researched:** 2026-04-03
**Confidence:** HIGH (all versions verified against Hex.pm; patterns verified against official Elixir docs and production libraries)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Elixir | >= 1.15 | Language runtime | Matches PhoenixAI constraint; Elixir 1.17+ brings gradual set-theoretic types that improve typespec accuracy but 1.15 is the floor to match the peer dep |
| OTP | >= 26 | Supervision, ETS, GenServer | Matches PhoenixAI constraint; OTP 26 brings improved process labels and ETS performance improvements |
| `phoenix_ai` | ~> 0.1 | Peer dependency — AI runtime layer | The library this Store wraps. Provides `Agent`, `Message`, `Response`, structs and telemetry events. Reference as peer dep (not hard dep) so the Store does not force a PhoenixAI version on apps |
| `ecto` | ~> 3.13 | Optional peer dep — Ecto adapter only | Use `optional: true` in mix.exs. Not required for InMemory adapter. Latest stable is 3.13.5 (Nov 2025). Do NOT pull as a required dep — zero-dep promise for non-Ecto users |
| `ecto_sql` | ~> 3.13 | SQL migrations and query helpers | Required only by Ecto adapter. 3.13.5 (Mar 2026). Also `optional: true` |
| `nimble_options` | ~> 1.1 | Config schema validation and documentation | Already used by PhoenixAI (1.1.1 on Hex). Use `NimbleOptions.new!/1` at compile time in adapter `__using__` macros to validate config once, not on every call |
| `telemetry` | ~> 1.3 | Instrumentation — emit span events | Already a PhoenixAI dep (1.4.1 on Hex). Every Store operation should emit `[:phoenix_ai_store, :action, :start/stop/exception]` spans via `telemetry:span/3`. Attach-based handler is the automatic integration mode |

### Storage Adapters

| Adapter | Dependencies | Backend | Use When |
|---------|-------------|---------|----------|
| `PhoenixAIStore.Adapters.ETS` | None (stdlib) | ETS table in a supervised GenServer | Dev, test, and production workloads that do not need durability across node restarts |
| `PhoenixAIStore.Adapters.Ecto` | `ecto ~> 3.13`, `ecto_sql ~> 3.13`, + a DB driver | Postgres or SQLite3 | Production with persistence requirements; supports pagination, user scoping, cost reporting |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `postgrex` | ~> 0.22 | PostgreSQL wire driver | Ecto adapter on Postgres. Declare `optional: true` in mix.exs — user brings their own DB driver |
| `ecto_sqlite3` | ~> 0.22 | SQLite3 Ecto adapter | Ecto adapter on SQLite3 (testing, edge deployments). `optional: true`. Requires C compilation; warn users |
| `telemetry_metrics` | ~> 1.1 | Metrics aggregation over telemetry events | Include only in `dev/test` deps. Apps that want dashboards will add it themselves |
| `hammer` | ~> 7.3 | Rate limiting — token and request budgets | Guardrails rate-limiting feature. ETS backend is built-in (no extra dep). Declare `optional: true`; only needed if user enables rate-limiting guardrail |
| `tiktoken` | ~> 0.4 | Accurate BPE token counting (Rust NIF) | Token-aware memory truncation when precision matters. `optional: true` — heavyweight (requires Rust); fall back to heuristic (`chars / 4`) when absent |

### Development & Test Tools

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| `ex_doc` | ~> 0.40 | Documentation generation | `only: :dev`. Run `mix docs` as part of CI. Include `@moduledoc` and `@doc` for all public callbacks |
| `mox` | ~> 1.2 | Behaviour-based mocking in tests | `only: :test`. Define mock modules for `Store`, `MemoryStrategy`, `Policy` behaviours. Do not use for testing adapters — use InMemory adapter instead |
| `stream_data` | ~> 1.3 | Property-based testing | `only: [:dev, :test]`. Useful for guardrail boundary tests and token budget arithmetic |
| `credo` | ~> 1.7 | Static code analysis / style | `only: [:dev, :test], runtime: false`. Enforce consistency across adapter implementations |
| `dialyxir` | ~> 1.4 | Dialyzer type checking | `only: [:dev, :test], runtime: false`. Every public callback must have `@spec`. Run `mix dialyzer` in CI |
| `mimic` | ~> 2.3 | Function-level mocking | `only: :test`. Fallback if Mox behaviour contracts are not feasible for a particular test scenario; prefer Mox |

---

## Installation (mix.exs deps)

```elixir
defp deps do
  [
    # Required — peer dep on AI runtime
    {:phoenix_ai, "~> 0.1"},

    # Required — config validation and observability
    {:nimble_options, "~> 1.1"},
    {:telemetry, "~> 1.3"},

    # Optional — only when Ecto adapter is used
    {:ecto, "~> 3.13", optional: true},
    {:ecto_sql, "~> 3.13", optional: true},

    # Optional — DB drivers (user provides their own, but declare for compile checks)
    {:postgrex, "~> 0.22", optional: true},
    {:ecto_sqlite3, "~> 0.22", optional: true},

    # Optional — rate limiting guardrail
    {:hammer, "~> 7.3", optional: true},

    # Optional — precise token counting (requires Rust)
    {:tiktoken, "~> 0.4", optional: true},

    # Dev / docs
    {:ex_doc, "~> 0.40", only: :dev, runtime: false},

    # Dev / test
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:mox, "~> 1.2", only: :test},
    {:stream_data, "~> 1.3", only: [:dev, :test]},
    {:mimic, "~> 2.3", only: :test},
  ]
end
```

**CI validation for optional deps.** Add this to the CI matrix to confirm the library compiles without optional deps present:

```bash
mix compile --no-optional-deps --warnings-as-errors
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Config validation | `nimble_options` | Raw keyword validation | No documentation generation; PhoenixAI already uses NimbleOptions — consistency matters |
| Rate limiting | `hammer` | `ex_rated` | Hammer 7.x has a cleaner API, pluggable backends, and is actively maintained (7.3.0, Feb 2026); ExRated is stale |
| Token counting | `tiktoken` + heuristic fallback | Bumblebee tokenizers | Bumblebee pulls Nx/EXLA — enormous transitive dep for a utility function; tiktoken is purpose-built and optional |
| Token counting fallback | `chars / 4` heuristic | `gpt3_tokenizer` | gpt3_tokenizer last updated 2022, unmaintained; `chars / 4` is +/-15% accuracy for English text, sufficient for truncation decisions |
| Mocking in tests | `mox` | `mimic` | Mox enforces behaviour contracts at mock-definition time — critical for ensuring Store adapters stay in sync with their callbacks; keep Mimic as fallback only |
| Append-only event log | Custom Ecto schema with `insert_only` guards | `carbonite`, `ecto_trail` | Carbonite uses Postgres triggers (too heavy, not portable); ecto_trail logs changesets (wrong model for event sourcing). A simple `events` table with no update/delete in the repo is sufficient |
| In-memory storage | Stdlib `:ets` directly | `stash`, `elixir_cache` | Both add a dependency for wrapping what is ~30 lines of ETS boilerplate. Own the InMemory adapter entirely |
| Static analysis | `dialyxir` | Elixir 1.17+ built-in type inference | Built-in inference is additive, not a replacement for Dialyzer PLT analysis. Use both |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `agent_session_manager` | Designed for CLI agent orchestration (Claude Code, Codex); session/run/event model does not map to API-based chat completions; 16 transitive deps as of v0.9.0 | This library (phoenix_ai_store) IS the alternative |
| Hard `ecto` dep in root mix.exs | Forces Ecto on users who only want InMemory adapter — violates the zero-dep promise | `optional: true`; gate all Ecto code behind `Code.ensure_loaded?(Ecto)` checks at runtime and the adapter's `start_link/1` documentation |
| `GenStage` / `Broadway` for event pipeline | Overkill for an audit log; adds concurrency complexity and a non-trivial dependency | Synchronous Ecto `insert` in the `log_event` call path; async only if user explicitly configures a background telemetry handler |
| `EventStoreDB` / `Spear` | Correct tool for event sourcing systems at scale; wrong fit for a companion library that must work in any Phoenix app | Ecto append-only `events` table covers 99% of audit needs |
| `Jason` as explicit dep | Already pulled transitively by PhoenixAI; declaring it explicitly risks version conflicts | Use `Jason` if available but do not force it; metadata fields use native Elixir terms internally, serialized only at the storage boundary by the adapter |
| `telemetry_poller` as required dep | Only needed if the app wants periodic VM metric polling — not a Store concern | Document in guide; let app owners add it |
| Any OpenAI/Anthropic client library | The Store is provider-agnostic; it tracks cost via normalized `Usage` structs from PhoenixAI, not raw API responses | Rely entirely on PhoenixAI for provider communication |

---

## Key Design Patterns

### Optional Ecto — The Oban Pattern (adapted)

Oban requires `ecto_sql` as a hard dep because its core job queue IS the database. This Store differs: the InMemory adapter has zero DB deps. Declare Ecto as `optional: true` and guard Ecto-only modules:

```elixir
# In PhoenixAIStore.Adapters.Ecto — gated at compile time
if Code.ensure_loaded?(Ecto) do
  @behaviour PhoenixAIStore.Store
  # ... schema definitions
end
```

The Mix task (`mix phoenix_ai_store.gen.migration`) should check at runtime and fail fast with a clear error if Ecto is not present.

### NimbleOptions Schema at Module Load Time

Pre-validate schemas once during module initialization, not on every call:

```elixir
@store_schema NimbleOptions.new!([
  adapter: [type: :atom, required: true],
  repo: [type: :atom, required: false],
  ...
])
```

This produces compile-time errors for invalid schemas and auto-generates documentation from the spec.

### Telemetry Span Convention

Every public Store operation emits three events following the BEAM telemetry convention:

```
[:phoenix_ai_store, :save_conversation, :start]
[:phoenix_ai_store, :save_conversation, :stop]
[:phoenix_ai_store, :save_conversation, :exception]
```

Use `telemetry:span/3` (Erlang) or `:telemetry.span/3` (Elixir) to emit all three atomically. This is what the automatic telemetry handler subscribes to.

### Token Counting Strategy

Implement a two-tier approach for memory strategies:

1. **Precise** (when `tiktoken` is loaded): `Tiktoken.count_tokens(text, model)` — accurate BPE count
2. **Heuristic** (fallback): `div(byte_size(text), 4)` — ~15% error margin for English text, sufficient for truncation decisions

The memory strategy behaviour receives a `:token_counter` option that defaults to the detected available implementation.

---

## Sources

- NimbleOptions v1.1.1: https://hex.pm/packages/nimble_options
- Telemetry v1.4.1: https://hex.pm/packages/telemetry
- Ecto v3.13.5 / ecto_sql v3.13.5: https://hex.pm/packages/ecto, https://hex.pm/packages/ecto_sql
- PhoenixAI v0.1.0 deps: https://hex.pm/packages/phoenix_ai
- PhoenixAI Agent docs (manage_history): https://hexdocs.pm/phoenix_ai/PhoenixAI.Agent.html
- Postgrex v0.22.0: https://hex.pm/packages/postgrex
- ecto_sqlite3 v0.22.0: https://hex.pm/packages/ecto_sqlite3
- Hammer v7.3.0: https://hex.pm/packages/hammer
- Tiktoken v0.4.2: https://hex.pm/packages/tiktoken
- Mox v1.2.0: https://hex.pm/packages/mox
- Mimic v2.3.0: https://hex.pm/packages/mimic
- ExDoc v0.40.1: https://hex.pm/packages/ex_doc
- StreamData v1.3.0: https://hex.pm/packages/stream_data
- Credo v1.7.17: https://hex.pm/packages/credo
- Dialyxir v1.4.7: https://hex.pm/packages/dialyxir
- Elixir library guidelines (optional deps): https://hexdocs.pm/elixir/library-guidelines.html
- Telemetry span conventions: https://hexdocs.pm/telemetry/telemetry.html
- Elixir gradual types roadmap: https://elixir-lang.org/blog/2026/01/09/type-inference-of-all-and-next-15/
- agent_session_manager v0.9.0 (evaluated and rejected): https://github.com/nshkrdotcom/agent_session_manager
