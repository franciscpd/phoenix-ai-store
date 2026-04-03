# CLAUDE.md

## .planning/ — Single Source of Truth

All planning artifacts MUST go in `.planning/`. Never outside it.

```
.planning/
└── phases/
    └── {N}-{slug}/          ← one folder per GSD phase (e.g. 01-auth)
        ├── DISCUSS.md        ← gsd:discuss output
        ├── BRAINSTORM.md     ← superpowers:brainstorm output
        ├── PLAN.md           ← superpowers:write-plan output
        ├── PROGRESS.md       ← superpowers:execute-plan tracking
        └── VERIFY.md         ← superpowers:requesting-code-review output
```

Before writing any artifact, MUST identify the active GSD phase and resolve its folder: `.planning/phases/{N}-{slug}/`. Create the folder if it does not exist. All Superpowers outputs for that phase go inside it.

---

## Workflow — Follow This Order Exactly

```
gsd:discuss → brainstorm → write-plan → execute-plan → gsd:verify
```

> `$PHASE` = active GSD phase folder, e.g. `.planning/phases/01-auth`

### Phase 1 — discuss
- Trigger: any new feature, task or bug with unclear scope
- MUST capture: requirements, scope, what's out of scope, priority
- MUST save output to `$PHASE/DISCUSS.md`
- MUST NOT proceed without explicit user approval

### Phase 2 — brainstorm
- Trigger: automatically after discuss approval
- MUST invoke `/superpowers:brainstorm` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` as context
- Focus: technical approach, architecture, trade-offs, Laravel patterns
- MUST save output to `$PHASE/BRAINSTORM.md`
- MUST NOT proceed without explicit user approval

### Phase 3 — write-plan
- Trigger: automatically after brainstorm approval
- MUST invoke `/superpowers:write-plan` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` + `$PHASE/BRAINSTORM.md` as input
- Output MUST include: affected files, atomic tasks, verify commands, commit messages
- MUST save output to `$PHASE/PLAN.md`
- MUST NOT proceed without explicit user approval

### Phase 4 — execute-plan
- Trigger: automatically after plan approval
- MUST invoke `/superpowers:execute-plan` using `$PHASE/PLAN.md`
- MUST follow TDD: write failing test → implement → pass (RED → GREEN → REFACTOR)
- MUST track progress in `$PHASE/PROGRESS.md`
- MUST commit atomically per logical task immediately after verify passes

### Phase 5 — verify
- Trigger: automatically after execute-plan completes
- MUST invoke `/superpowers:requesting-code-review`
- MUST run `php artisan test && php artisan pint` — nothing is done without passing evidence
- MUST save output to `$PHASE/VERIFY.md`


## Skip Rules

| Situation | Skip |
|---|---|
| Scope is already clear | Skip discuss, start at brainstorm |
| Approach is already clear | Skip brainstorm, start at write-plan |
| Small well-defined task | Skip discuss + brainstorm, start at write-plan |
| Known bug with clear fix | Use `/superpowers:systematic-debugging` directly |

---

## Commits

```
type(scope): description
```
Types: `feat | fix | refactor | test | docs | style | chore`
One commit per logical task. Never commit broken code.

---

## Rules

- Bugs before features. Max 2–3 WIP tasks.
- Never deploy without explicit approval.
- Never skip phases without a skip rule justifying it.
- Always ask when scope or approach is unclear.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**PhoenixAI Store**

A companion Elixir library for [PhoenixAI](https://hex.pm/packages/phoenix_ai) that adds persistence, memory management, guardrails, cost tracking, and an audit event log for AI agent conversations. Users who only need `AI.chat/2` don't pay for what they don't use.

**Core Value:** Conversations persist and restore transparently across process restarts, with memory strategies keeping them within context window limits — the foundation everything else builds on.

### Constraints

- **Elixir**: >= 1.15, OTP >= 26 (match PhoenixAI)
- **Peer dependency**: `phoenix_ai` on Hex (version with Usage struct normalization)
- **Ecto optional**: Only required when using the Ecto adapter — InMemory adapter (ETS-backed) has zero extra deps
- **Zero required deps beyond phoenix_ai**: Adapters bring their own dependencies
- **Patterns**: Follow PhoenixAI conventions — behaviours, `{:ok, t} | {:error, term}`, NimbleOptions, telemetry
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

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
## Installation (mix.exs deps)
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
## Key Design Patterns
### Optional Ecto — The Oban Pattern (adapted)
# In PhoenixAIStore.Adapters.Ecto — gated at compile time
### NimbleOptions Schema at Module Load Time
### Telemetry Span Convention
### Token Counting Strategy
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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
