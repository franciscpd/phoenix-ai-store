# Documentation, CI & Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PhoenixAI Store publishable on Hex.pm with complete ExDoc docs, GitHub Actions CI, and all required package files.

**Architecture:** Three independent workstreams — (1) complete @doc/@spec/@moduledoc across all modules, (2) write 4 ExDoc guides + update mix.exs docs config, (3) create CI workflow + root publication files (README, LICENSE, CHANGELOG). Task order: docs first (CI docs job depends on clean `mix docs`), then guides + mix.exs, then CI + root files, then final verification.

**Tech Stack:** ExDoc ~> 0.34, GitHub Actions (erlef/setup-beam), Dialyxir ~> 1.4, Credo ~> 1.7

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/schemas/profile.ex` | Modify | Add @moduledoc |
| `lib/phoenix_ai/store/schemas/fact.ex` | Modify | Add @moduledoc |
| `lib/phoenix_ai/store/schemas/cost_record.ex` | Modify | Add @moduledoc |
| `lib/phoenix_ai/store/schemas/event.ex` | Modify | Add @moduledoc |
| `lib/phoenix_ai/store/long_term_memory.ex` | Modify | Add @doc to 8 public functions |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Add @doc to 11 callback implementations |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Add @doc to 11 callback implementations |
| `lib/phoenix_ai/store.ex` | Modify | Add @spec to converse/3 and track/1 |
| `guides/getting-started.md` | Create | Installation → first converse/3 in 5 min |
| `guides/adapters.md` | Create | ETS vs Ecto, custom adapter |
| `guides/memory-and-guardrails.md` | Create | Memory strategies + guardrails |
| `guides/telemetry-and-events.md` | Create | TelemetryHandler, track/1, event log |
| `mix.exs` | Modify | Update docs() with extras, groups_for_modules |
| `README.md` | Create | Badges, features, quick start |
| `LICENSE` | Create | MIT full text |
| `CHANGELOG.md` | Create | Keep a Changelog format, v0.1.0 |
| `.github/workflows/ci.yml` | Create | CI with 4 jobs, 2x2 matrix |

---

### Task 1: Add @moduledoc to Schema modules

**Files:**
- Modify: `lib/phoenix_ai/store/schemas/profile.ex`
- Modify: `lib/phoenix_ai/store/schemas/fact.ex`
- Modify: `lib/phoenix_ai/store/schemas/cost_record.ex`
- Modify: `lib/phoenix_ai/store/schemas/event.ex`

- [ ] **Step 1: Read all 4 schema files**

Read each file to understand the struct fields and existing code.

- [ ] **Step 2: Add @moduledoc to each schema**

For each schema module, add a `@moduledoc` right after the `defmodule` line. Follow this pattern — adapt the description for each:

`lib/phoenix_ai/store/schemas/profile.ex`:
```elixir
@moduledoc """
Ecto schema for user profile summaries in long-term memory.

Maps between the database `phoenix_ai_store_profiles` table and
`PhoenixAI.Store.LongTermMemory.Profile` structs.
"""
```

`lib/phoenix_ai/store/schemas/fact.ex`:
```elixir
@moduledoc """
Ecto schema for cross-conversation facts in long-term memory.

Maps between the database `phoenix_ai_store_facts` table and
`PhoenixAI.Store.LongTermMemory.Fact` structs.
"""
```

`lib/phoenix_ai/store/schemas/cost_record.ex`:
```elixir
@moduledoc """
Ecto schema for cost records tracking AI usage expenses.

Maps between the database `phoenix_ai_store_cost_records` table and
`PhoenixAI.Store.CostTracking.CostRecord` structs. All monetary fields
use `Decimal` for precision.
"""
```

`lib/phoenix_ai/store/schemas/event.ex`:
```elixir
@moduledoc """
Ecto schema for the append-only audit event log.

Maps between the database `phoenix_ai_store_events` table and
`PhoenixAI.Store.EventLog.Event` structs. Events are insert-only —
no update or delete operations exist.
"""
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/schemas/
git commit -m "docs(schemas): add @moduledoc to all Ecto schema modules"
```

---

### Task 2: Add @doc to LongTermMemory facade

**Files:**
- Modify: `lib/phoenix_ai/store/long_term_memory.ex`

- [ ] **Step 1: Read the file**

Read `lib/phoenix_ai/store/long_term_memory.ex` to see all 8 public functions and their existing @spec.

- [ ] **Step 2: Add @doc to each public function**

Add `@doc` with description and `## Examples` before each public function. Read the actual function bodies first to write accurate docs. Each @doc should describe what the function does, its parameters, and return values. Include a realistic code example.

The 8 functions needing @doc are: `save_fact/2`, `get_facts/2`, `delete_fact/3`, `save_profile/2`, `get_profile/2`, `delete_profile/2`, `extract_facts/2`, `update_profile/2`.

Pattern to follow (adapt for each function):
```elixir
@doc """
Saves a fact to the long-term memory store.

Facts are cross-conversation knowledge extracted from messages that
persist beyond individual conversations.

## Examples

    fact = %Fact{key: "user_preference", value: "prefers dark mode", user_id: "user-1"}
    {:ok, saved} = LongTermMemory.save_fact(fact, store: :my_store)

"""
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory.ex
git commit -m "docs(ltm): add @doc to all LongTermMemory public functions"
```

---

### Task 3: Add @doc to ETS adapter

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex`

- [ ] **Step 1: Read the file**

Read `lib/phoenix_ai/store/adapters/ets.ex` to see all callback implementations.

- [ ] **Step 2: Add @doc to each callback implementation**

For each `@impl true` function, add a `@doc` right before the `@impl` attribute. Since these are adapter callbacks, the docs should be brief and focus on ETS-specific behavior.

Pattern:
```elixir
@doc """
Persists a conversation to the ETS table.

Generates an ID and timestamps if not already set. Overwrites
any existing conversation with the same ID.
"""
@impl true
def save_conversation(conversation, opts) do
```

Do this for all 11 public callback functions in the ETS adapter.

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex
git commit -m "docs(ets): add @doc to all ETS adapter callbacks"
```

---

### Task 4: Add @doc to Ecto adapter

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex`

- [ ] **Step 1: Read the file**

Read `lib/phoenix_ai/store/adapters/ecto.ex` to see all callback implementations.

- [ ] **Step 2: Add @doc to each callback implementation**

Same pattern as Task 3 but with Ecto-specific details (e.g., "Inserts via the configured Ecto Repo", "Uses a database transaction").

Do this for all 11 public callback functions in the Ecto adapter.

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ecto.ex
git commit -m "docs(ecto): add @doc to all Ecto adapter callbacks"
```

---

### Task 5: Add @spec to Store.converse/3 and Store.track/1

**Files:**
- Modify: `lib/phoenix_ai/store.ex`

- [ ] **Step 1: Read the relevant sections**

Read `lib/phoenix_ai/store.ex` and find `converse/3` and `track/1` — check if they have @spec.

- [ ] **Step 2: Add missing @spec**

If `converse/3` is missing @spec, add:
```elixir
@spec converse(String.t(), String.t(), keyword()) ::
        {:ok, PhoenixAI.Response.t()} | {:error, term()}
```

If `track/1` is missing @spec, add:
```elixir
@spec track(map()) :: {:ok, PhoenixAI.Store.EventLog.Event.t()} | {:error, term()}
```

- [ ] **Step 3: Run dialyzer to verify specs are correct**

Run: `mix dialyzer`
Expected: No new warnings from the added specs

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store.ex
git commit -m "docs(store): add @spec to converse/3 and track/1"
```

---

### Task 6: Create Getting Started guide

**Files:**
- Create: `guides/getting-started.md`

- [ ] **Step 1: Create guides directory**

```bash
mkdir -p guides
```

- [ ] **Step 2: Write the Getting Started guide**

Create `guides/getting-started.md` with this content (read `lib/phoenix_ai/store.ex` and `lib/phoenix_ai/store/config.ex` first to ensure accuracy):

```markdown
# Getting Started

This guide walks you through setting up PhoenixAI Store from scratch.
By the end, you'll have a working conversation with AI persistence.

## Installation

Add `phoenix_ai_store` to your dependencies in `mix.exs`:

    {:phoenix_ai_store, "~> 0.1.0"}

Then run:

    mix deps.get

## Quick Setup with ETS (No Database)

The ETS adapter stores conversations in memory — perfect for
development and testing.

### 1. Add the Store to your supervision tree

```elixir
# lib/my_app/application.ex
children = [
  {PhoenixAI.Store,
    name: :my_store,
    adapter: PhoenixAI.Store.Adapters.ETS}
]
```

### 2. Have a conversation

```elixir
# Create a conversation
{:ok, conv} = PhoenixAI.Store.save_conversation(
  %PhoenixAI.Store.Conversation{title: "My Chat"},
  store: :my_store
)

# Run the full pipeline: load → memory → guardrails → AI → save → cost → events
{:ok, response} = PhoenixAI.Store.converse(
  conv.id,
  "Hello! What can you help me with?",
  provider: :openai,
  model: "gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY"),
  store: :my_store
)

IO.puts(response.content)
```

That's it! The Store handles message persistence, and you can
continue the conversation by calling `converse/3` again with
the same `conv.id`.

## Setup with Ecto (Persistent Storage)

For production use, the Ecto adapter persists to PostgreSQL or SQLite.

### 1. Add Ecto dependencies

```elixir
# mix.exs
{:ecto_sql, "~> 3.13"},
{:postgrex, "~> 0.19"}  # or {:ecto_sqlite3, "~> 0.22"}
```

### 2. Generate and run migrations

```bash
mix phoenix_ai_store.gen.migration --conversations --messages --cost --events
mix ecto.migrate
```

### 3. Configure the Store

```elixir
children = [
  {PhoenixAI.Store,
    name: :my_store,
    adapter: PhoenixAI.Store.Adapters.Ecto,
    repo: MyApp.Repo}
]
```

### 4. Use it the same way

The API is identical — just swap the adapter:

```elixir
{:ok, response} = PhoenixAI.Store.converse(
  conv.id,
  "Remember our earlier chat?",
  provider: :openai,
  model: "gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY"),
  store: :my_store
)
```

## What's Next?

- [Adapters Guide](adapters.md) — ETS vs Ecto in depth, custom adapters
- [Memory & Guardrails](memory-and-guardrails.md) — Keep conversations within context limits
- [Telemetry & Events](telemetry-and-events.md) — Automatic event capture and audit logging
```

- [ ] **Step 3: Verify the guide renders**

Run: `mix docs`
Expected: Guide appears in the sidebar (will configure mix.exs in Task 10)

- [ ] **Step 4: Commit**

```bash
git add guides/getting-started.md
git commit -m "docs(guides): add Getting Started guide"
```

---

### Task 7: Create Adapters guide

**Files:**
- Create: `guides/adapters.md`

- [ ] **Step 1: Write the Adapters guide**

Read `lib/phoenix_ai/store/adapter.ex`, `lib/phoenix_ai/store/adapters/ets.ex`, and `lib/phoenix_ai/store/adapters/ecto.ex` to understand the behaviour and implementations. Then write `guides/adapters.md` covering:

1. **ETS Adapter** — When to use, configuration options, limitations (no persistence across restarts)
2. **Ecto Adapter** — When to use, required deps, Repo configuration, migration generation
3. **Comparison table** — ETS vs Ecto (persistence, speed, deps, use case)
4. **Custom Adapters** — How to implement the `PhoenixAI.Store.Adapter` behaviour, which callbacks are required vs optional (sub-behaviours), testing with contract tests

- [ ] **Step 2: Commit**

```bash
git add guides/adapters.md
git commit -m "docs(guides): add Adapters guide"
```

---

### Task 8: Create Memory & Guardrails guide

**Files:**
- Create: `guides/memory-and-guardrails.md`

- [ ] **Step 1: Write the Memory & Guardrails guide**

Read `lib/phoenix_ai/store/memory/pipeline.ex`, `lib/phoenix_ai/store/memory/sliding_window.ex`, `lib/phoenix_ai/store/memory/token_truncation.ex`, `lib/phoenix_ai/store/guardrails/token_budget.ex`, and `lib/phoenix_ai/store/guardrails/cost_budget.ex`. Then write `guides/memory-and-guardrails.md` covering:

1. **Memory Strategies** — SlidingWindow, TokenTruncation, PinnedMessages, how each works
2. **Pipeline Composition** — Chaining strategies with `Pipeline.new/1`
3. **Using with converse/3** — Passing `:memory_pipeline` option
4. **Guardrails** — TokenBudget (scopes: conversation, user, time_window), CostBudget
5. **Using with converse/3** — Passing `:guardrails` option
6. **Long-Term Memory** — Facts and profiles, extraction, injection

- [ ] **Step 2: Commit**

```bash
git add guides/memory-and-guardrails.md
git commit -m "docs(guides): add Memory & Guardrails guide"
```

---

### Task 9: Create Telemetry & Events guide

**Files:**
- Create: `guides/telemetry-and-events.md`

- [ ] **Step 1: Write the Telemetry & Events guide**

Read `lib/phoenix_ai/store/telemetry_handler.ex`, `lib/phoenix_ai/store/handler_guardian.ex`, `lib/phoenix_ai/store/event_log.ex`, and `lib/phoenix_ai/store/event_log/event.ex`. Then write `guides/telemetry-and-events.md` covering:

1. **Telemetry Events** — Complete list of `[:phoenix_ai_store, ...]` events emitted
2. **TelemetryHandler** — Auto-capture setup, Logger.metadata context propagation
3. **HandlerGuardian** — Supervised reattachment, supervision tree setup
4. **Store.track/1** — Explicit event capture API
5. **Event Log** — `log_event/2`, `list_events/2`, cursor pagination, redaction configuration
6. **Cost Tracking** — `record_cost/3`, pricing providers, Decimal arithmetic

- [ ] **Step 2: Commit**

```bash
git add guides/telemetry-and-events.md
git commit -m "docs(guides): add Telemetry & Events guide"
```

---

### Task 10: Update mix.exs docs() and verify mix docs

**Files:**
- Modify: `mix.exs:74-79`

- [ ] **Step 1: Read current mix.exs**

Read `mix.exs` to see the current `docs/0` function.

- [ ] **Step 2: Update docs() function**

Replace the existing `docs/0` with:

```elixir
defp docs do
  [
    main: "PhoenixAI.Store",
    source_ref: "v#{@version}",
    source_url: @source_url,
    extras: [
      "README.md",
      "guides/getting-started.md",
      "guides/adapters.md",
      "guides/memory-and-guardrails.md",
      "guides/telemetry-and-events.md",
      "CHANGELOG.md"
    ],
    groups_for_extras: [
      Guides: ~r/guides\/.*/
    ],
    groups_for_modules: [
      Core: [
        PhoenixAI.Store,
        PhoenixAI.Store.Conversation,
        PhoenixAI.Store.Message
      ],
      Adapters: [
        PhoenixAI.Store.Adapter,
        PhoenixAI.Store.Adapters.ETS,
        PhoenixAI.Store.Adapters.Ecto
      ],
      Memory: [
        PhoenixAI.Store.Memory.Pipeline,
        PhoenixAI.Store.Memory.SlidingWindow,
        PhoenixAI.Store.Memory.TokenTruncation,
        PhoenixAI.Store.Memory.PinnedMessages
      ],
      Guardrails: [
        PhoenixAI.Store.Guardrails.TokenBudget,
        PhoenixAI.Store.Guardrails.CostBudget
      ],
      "Cost Tracking": [
        PhoenixAI.Store.CostTracking,
        PhoenixAI.Store.CostTracking.CostRecord,
        PhoenixAI.Store.CostTracking.PricingProvider
      ],
      "Event Log": [
        PhoenixAI.Store.EventLog,
        PhoenixAI.Store.EventLog.Event
      ],
      "Long-Term Memory": [
        PhoenixAI.Store.LongTermMemory,
        PhoenixAI.Store.LongTermMemory.Fact,
        PhoenixAI.Store.LongTermMemory.Profile
      ],
      Telemetry: [
        PhoenixAI.Store.TelemetryHandler,
        PhoenixAI.Store.HandlerGuardian
      ],
      Pipeline: [
        PhoenixAI.Store.ConversePipeline
      ]
    ]
  ]
end
```

- [ ] **Step 3: Run mix docs and verify no warnings**

Run: `mix docs 2>&1`
Expected: Documentation generated with no warnings, guides appear in sidebar

- [ ] **Step 4: Commit**

```bash
git add mix.exs
git commit -m "docs(mix): update ExDoc config with guides and module groups"
```

---

### Task 11: Create README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README.md with badges, features, and quick start"
```

---

### Task 12: Create LICENSE and CHANGELOG.md

**Files:**
- Create: `LICENSE`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create LICENSE file**

Write `LICENSE` with MIT full text:

```
MIT License

Copyright (c) 2026 Francisross Soares de Oliveira

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create CHANGELOG.md**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-04-05

### Added

- Conversation persistence with ETS and Ecto adapters
- Memory strategies: sliding window, token-aware truncation, pinned messages
- Long-term memory: cross-conversation facts and user profile summaries
- Guardrails: token budget, cost budget, and Hammer rate limiting
- Cost tracking with Decimal arithmetic and pluggable pricing providers
- Append-only event log with cursor pagination and configurable redaction
- `converse/3` single-function pipeline (load → memory → guardrails → AI → save → track)
- `Store.track/1` ergonomic event capture API
- TelemetryHandler + HandlerGuardian for automatic PhoenixAI event capture
- Full telemetry instrumentation on all Store operations
- Mix task: `mix phoenix_ai_store.gen.migration`
```

- [ ] **Step 3: Commit**

```bash
git add LICENSE CHANGELOG.md
git commit -m "docs: add LICENSE (MIT) and CHANGELOG.md"
```

---

### Task 13: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  MIX_ENV: test

jobs:
  test:
    name: Test (Elixir ${{ matrix.elixir }} / OTP ${{ matrix.otp }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - elixir: '1.15.8'
            otp: '26.2'
          - elixir: '1.15.8'
            otp: '27.2'
          - elixir: '1.17.3'
            otp: '26.2'
          - elixir: '1.17.3'
            otp: '27.2'
    services:
      postgres:
        image: postgres:16
        ports: ['5432:5432']
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: phoenix_ai_store_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/phoenix_ai_store_test
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      - uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: mix-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('mix.lock') }}
          restore-keys: mix-${{ matrix.elixir }}-${{ matrix.otp }}-
      - run: mix deps.get
      - run: mix test

  quality:
    name: Code Quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17.3'
          otp-version: '27.2'
      - uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: mix-1.17.3-27.2-${{ hashFiles('mix.lock') }}
          restore-keys: mix-1.17.3-27.2-
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix credo --strict
      - run: mix format --check-formatted

  dialyzer:
    name: Dialyzer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        id: beam
        with:
          elixir-version: '1.17.3'
          otp-version: '27.2'
      - uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: mix-1.17.3-27.2-${{ hashFiles('mix.lock') }}
          restore-keys: mix-1.17.3-27.2-
      - uses: actions/cache@v4
        with:
          path: priv/plts
          key: plt-${{ steps.beam.outputs.elixir-version }}-${{ steps.beam.outputs.otp-version }}-${{ hashFiles('mix.lock') }}
          restore-keys: plt-${{ steps.beam.outputs.elixir-version }}-${{ steps.beam.outputs.otp-version }}-
      - run: mix deps.get
      - run: mix dialyzer

  docs:
    name: Documentation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17.3'
          otp-version: '27.2'
      - uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: mix-1.17.3-27.2-${{ hashFiles('mix.lock') }}
          restore-keys: mix-1.17.3-27.2-
      - run: mix deps.get
      - run: mix docs
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow with test matrix, quality, dialyzer, and docs"
```

---

### Task 14: Fix Dialyzer warnings and run full verification

**Files:**
- Possibly modify: any file with Dialyzer warnings

- [ ] **Step 1: Run dialyzer**

Run: `mix dialyzer`
Expected: Either clean or a list of warnings to fix

- [ ] **Step 2: Fix any warnings**

For each warning, add the correct `@spec` or fix the type mismatch. Use `@dialyzer {:nowarn_function, ...}` only as a last resort.

- [ ] **Step 3: Run full verification suite**

Run all checks that CI will run:

```bash
mix test && \
mix compile --warnings-as-errors && \
mix credo --strict && \
mix format --check-formatted && \
mix docs
```

Expected: All 5 commands pass

- [ ] **Step 4: Run hex.publish dry run**

Run: `mix hex.build`
Expected: Package builds successfully, lists all expected files

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve dialyzer warnings and verify publication readiness"
```

---

## Self-Review Checklist

| Spec Requirement | Task |
|-----------------|------|
| SC-1: mix docs clean, all public @moduledoc/@doc/@spec | Tasks 1-5, 10 |
| SC-2: Getting Started guide (5 min to converse/3) | Task 6 |
| SC-3: CI pipeline (test, credo, dialyzer, docs) | Task 13 |
| SC-4: hex.publish --dry-run passes | Tasks 11, 12, 14 |
| SC-5: README on Hex | Task 11 |
| D-01: 4 ExDoc guides | Tasks 6-9 |
| D-02: Complete @doc with Examples | Tasks 2-4 |
| D-03: @moduledoc on all modules | Task 1 |
| D-04: 2x2 matrix | Task 13 |
| D-05: 4 CI checks | Task 13 |
| D-06: Dialyzer warnings-as-errors | Task 14 |
| D-08: Version 0.1.0 | Already in mix.exs |
| D-09: Keep a Changelog | Task 12 |
| D-10: MIT license | Task 12 |
| D-11: README with badges | Task 11 |
