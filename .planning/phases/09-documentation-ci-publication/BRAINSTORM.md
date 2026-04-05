# Phase 9: Documentation, CI & Publication — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Requirements:** DOC-01

## Summary

Complete ExDoc documentation (4 guides + full @doc/@spec), GitHub Actions CI (4 checks, 2x2 matrix), and Hex publication readiness (README, LICENSE, CHANGELOG, mix hex.publish --dry-run).

## Deliverables

### 1. ExDoc Documentation

#### Guides (new files in `guides/`)

| Guide | File | Content |
|-------|------|---------|
| Getting Started | `guides/getting-started.md` | Installation, minimal ETS config, first `converse/3`, Ecto setup |
| Adapters | `guides/adapters.md` | ETS vs Ecto comparison, config for each, custom adapter tutorial |
| Memory & Guardrails | `guides/memory-and-guardrails.md` | Memory strategies, TokenBudget, CostBudget, pipeline composition |
| Telemetry & Events | `guides/telemetry-and-events.md` | TelemetryHandler + HandlerGuardian, Store.track/1, event log, redaction |

#### @doc Completion

Modules needing full `@doc` + `@spec` on all public functions:

**No @doc at all (need everything):**
- `lib/phoenix_ai/store/adapter.ex` — Behaviour callbacks
- `lib/phoenix_ai/store/guardrails/token_budget.ex`
- `lib/phoenix_ai/store/guardrails/cost_budget.ex`
- `lib/phoenix_ai/store/guardrails/token_budget/rate_limiter.ex`
- `lib/phoenix_ai/store/long_term_memory/extractor.ex`
- `lib/phoenix_ai/store/long_term_memory/injector.ex`
- `lib/phoenix_ai/store/long_term_memory/profile.ex`
- `lib/phoenix_ai/store/long_term_memory/extractor/default.ex`
- `lib/phoenix_ai/store/long_term_memory/fact.ex`
- `lib/phoenix_ai/store/cost_tracking/pricing_provider.ex`
- `lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex`
- `lib/phoenix_ai/store/cost_tracking/cost_record.ex`

**Partial @doc (need completion):**
- `lib/phoenix_ai/store.ex` — 27/28 defs documented
- `lib/phoenix_ai/store/telemetry_handler.ex` — 4/6
- `lib/phoenix_ai/store/memory/pipeline.ex` — 3/5
- `lib/phoenix_ai/store/handler_guardian.ex` — 1/3
- `lib/phoenix_ai/store/instance.ex` — 3/6
- `lib/phoenix_ai/store/adapters/ets/table_owner.ex` — 2/5

**Missing @moduledoc:**
- `lib/phoenix_ai/store/schemas/profile.ex`
- `lib/phoenix_ai/store/schemas/fact.ex`
- `lib/phoenix_ai/store/schemas/cost_record.ex`
- `lib/phoenix_ai/store/schemas/event.ex`

#### mix.exs docs() Update

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
    groups_for_modules: [
      "Core": [PhoenixAI.Store, PhoenixAI.Store.Conversation, PhoenixAI.Store.Message],
      "Adapters": [PhoenixAI.Store.Adapter, PhoenixAI.Store.Adapters.ETS, PhoenixAI.Store.Adapters.Ecto],
      "Memory": [PhoenixAI.Store.Memory.Pipeline, PhoenixAI.Store.Memory.SlidingWindow, PhoenixAI.Store.Memory.TokenTruncation, PhoenixAI.Store.Memory.PinnedMessages],
      "Guardrails": [PhoenixAI.Store.Guardrails.TokenBudget, PhoenixAI.Store.Guardrails.CostBudget],
      "Cost Tracking": [PhoenixAI.Store.CostTracking, PhoenixAI.Store.CostTracking.CostRecord, PhoenixAI.Store.CostTracking.PricingProvider],
      "Event Log": [PhoenixAI.Store.EventLog, PhoenixAI.Store.EventLog.Event],
      "Long-Term Memory": [PhoenixAI.Store.LongTermMemory, PhoenixAI.Store.LongTermMemory.Fact, PhoenixAI.Store.LongTermMemory.Profile],
      "Telemetry": [PhoenixAI.Store.TelemetryHandler, PhoenixAI.Store.HandlerGuardian],
      "Pipeline": [PhoenixAI.Store.ConversePipeline]
    ]
  ]
end
```

### 2. GitHub Actions CI

Single workflow `.github/workflows/ci.yml`:

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
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.15.8', '1.17.3']
        otp: ['26.2', '27.2']
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
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      - uses: actions/cache@v4
        with:
          path: deps
          key: deps-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('mix.lock') }}
      - run: mix deps.get
      - run: mix test

  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17.3'
          otp-version: '27.2'
      - uses: actions/cache@v4
        with:
          path: deps
          key: deps-1.17.3-27.2-${{ hashFiles('mix.lock') }}
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix credo --strict
      - run: mix format --check-formatted

  dialyzer:
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
            _build/dev/*.plt
            _build/dev/*.plt.hash
          key: dialyzer-1.17.3-27.2-${{ hashFiles('mix.lock') }}
      - run: mix deps.get
      - run: mix dialyzer

  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17.3'
          otp-version: '27.2'
      - uses: actions/cache@v4
        with:
          path: deps
          key: deps-1.17.3-27.2-${{ hashFiles('mix.lock') }}
      - run: mix deps.get
      - run: mix docs
```

### 3. Publication Files

#### README.md

Structure:
1. Badges: Hex version, CI status, HexDocs
2. Tagline: "Persistence, memory management, guardrails, cost tracking, and an audit event log for PhoenixAI conversations"
3. Features: 6 bullets (Persistence, Memory, Guardrails, Cost, Events, Converse pipeline)
4. Quick Start: ETS adapter + `converse/3` in ~15 lines
5. Links: HexDocs, GitHub, guides

#### LICENSE

MIT full text with "Copyright (c) 2026 Francisross Soares de Oliveira"

#### CHANGELOG.md

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-04-05

### Added

- Conversation persistence with ETS and Ecto adapters
- Memory strategies: sliding window, token-aware truncation, pinned messages
- Long-term memory: cross-conversation facts, user profiles
- Guardrails: token budget, cost budget, Hammer rate limiting
- Cost tracking with Decimal arithmetic and pluggable pricing
- Append-only event log with cursor pagination and redaction
- `converse/3` single-function pipeline
- `Store.track/1` ergonomic event capture
- TelemetryHandler + HandlerGuardian for automatic event capture
- Full telemetry instrumentation on all operations
- Mix task: `mix phoenix_ai_store.gen.migration`
```

## Requirements Coverage

| Requirement | Covered By |
|-------------|------------|
| DOC-01 (documentation) | ExDoc guides + @doc completion |
| SC-1 (mix docs clean) | @doc/@spec on all public modules + CI docs job |
| SC-2 (Getting Started guide) | guides/getting-started.md |
| SC-3 (CI pipeline) | .github/workflows/ci.yml with 4 jobs |
| SC-4 (hex.publish --dry-run) | README + LICENSE + CHANGELOG + package() |
| SC-5 (README on Hex) | README.md with badges, features, quick start |
