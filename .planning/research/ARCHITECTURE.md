# Architecture Research

**Domain:** AI conversation persistence & governance (Elixir library)
**Researched:** 2026-04-03
**Confidence:** HIGH (based on official Elixir/Oban/PhoenixAI docs, verified patterns)

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  User's Phoenix Application                                       │
│    - calls PhoenixAIStore.converse/2 or manages flow manually     │
│    - OR attaches PhoenixAIStore.TelemetryHandler to auto-capture  │
└───────────────────────┬──────────────────────────────────────────┘
                        │ explicit API  OR  telemetry attach
┌───────────────────────▼──────────────────────────────────────────┐
│  PhoenixAIStore (library boundary)                                │
│                                                                   │
│  ┌─────────────┐   ┌────────────────┐   ┌──────────────────┐    │
│  │  Store API  │   │  Memory Layer  │   │  Guardrails      │    │
│  │  (public)   │──▶│  (strategies)  │──▶│  (policy stack)  │    │
│  └──────┬──────┘   └────────────────┘   └────────┬─────────┘    │
│         │                                         │              │
│  ┌──────▼──────────────────────────────────────────▼──────────┐  │
│  │  Storage Adapter (behaviour)                                │  │
│  │  ┌─────────────────────┐   ┌──────────────────────────┐   │  │
│  │  │  Ecto Adapter        │   │  InMemory Adapter (ETS)  │   │  │
│  │  │  (optional dep)      │   │  (zero extra deps)       │   │  │
│  │  └─────────────────────┘   └──────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────┐   ┌──────────────┐   ┌──────────────────┐  │
│  │  CostTracker    │   │  EventLog    │   │  Telemetry       │  │
│  │  (per response) │   │  (append-    │   │  Handler         │  │
│  │                 │   │   only log)  │   │  (auto-capture)  │  │
│  └─────────────────┘   └──────────────┘   └──────────────────┘  │
└───────────────────────┬──────────────────────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────────────────────┐
│  PhoenixAI (peer dep)                                             │
│    Agent (manage_history: false) / AI.chat / Pipeline / Team      │
│    Telemetry: [:phoenix_ai, :chat/:stream/:tool_call/...]         │
└──────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Module(s) | Responsibility | Talks To |
|-----------|-----------|----------------|----------|
| Store API | `PhoenixAIStore` | Public facade: `converse/2`, `load/1`, `save/1`, `history/1` | Memory, Guardrails, StorageAdapter, CostTracker, EventLog |
| Conversation struct | `PhoenixAIStore.Conversation` | Canonical persistence struct (id, user_id, messages, metadata, timestamps) | StorageAdapter |
| Storage behaviour | `PhoenixAIStore.Adapter` | `@behaviour` contract: `save/1`, `load/1`, `list/1`, `delete/1` | — |
| Ecto adapter | `PhoenixAIStore.Adapters.Ecto` | Postgres/SQLite persistence via Ecto (optional dep) | Ecto.Repo |
| InMemory adapter | `PhoenixAIStore.Adapters.InMemory` | ETS-backed; zero extra deps; GenServer owner | ETS table |
| Memory strategies | `PhoenixAIStore.Memory.*` | Transform message list before passing to AI (sliding window, token truncation, summarization, pinning) | PhoenixAI.Message, PhoenixAI.AI.chat (summarization calls back into the AI) |
| Strategy behaviour | `PhoenixAIStore.Memory.Strategy` | `@callback apply(messages, opts) :: messages` | — |
| Guardrails | `PhoenixAIStore.Guardrails` | Run ordered policy stack; return `{:ok, :pass}` or `{:error, PolicyViolation.t()}` | CostTracker, StorageAdapter |
| Policy behaviour | `PhoenixAIStore.Guardrails.Policy` | `@callback check(context) :: :ok \| {:error, reason}` | — |
| Built-in policies | `PhoenixAIStore.Guardrails.Policies.*` | TokenBudget, CostBudget, ToolPolicy, ContentFilter, RateLimit | StorageAdapter (for aggregates), CostTracker |
| CostTracker | `PhoenixAIStore.CostTracker` | Parse `Response.usage`, look up pricing table, compute cost, persist record | StorageAdapter (event log), Guardrails (budget check) |
| EventLog | `PhoenixAIStore.EventLog` | Append-only Ecto schema inserts; cursor-based pagination; optional redaction | Ecto (optional dep) |
| TelemetryHandler | `PhoenixAIStore.TelemetryHandler` | Attaches to `[:phoenix_ai, ...]` events; calls Store API automatically | Store API |
| Config | `PhoenixAIStore.Config` | NimbleOptions schema validation; resolves adapter module at startup | All components |
| Supervisor | `PhoenixAIStore.Supervisor` | Starts InMemory adapter (ETS owner GenServer) when selected; optional child | InMemory GenServer |

---

## Recommended Project Structure

```
lib/
  phoenix_ai_store.ex                   # Public API + Application entry
  phoenix_ai_store/
    application.ex                      # Optional supervisor boot
    config.ex                           # NimbleOptions validation
    conversation.ex                     # Store-owned struct (id, user_id, messages, metadata)
    adapter.ex                          # @behaviour: save/load/list/delete
    adapters/
      ecto.ex                           # Ecto adapter (Code.ensure_loaded? Ecto)
      in_memory.ex                      # ETS adapter; GenServer owner
      in_memory/
        server.ex                       # GenServer managing ETS table lifecycle
    schemas/                            # Ecto schemas (optional dep boundary)
      conversation_schema.ex
      message_schema.ex
      event_log_schema.ex
      cost_record_schema.ex
    memory/
      strategy.ex                       # @behaviour: apply(messages, opts) :: messages
      sliding_window.ex
      token_truncation.ex
      summarization.ex
      pinned.ex
      pipeline.ex                       # Compose multiple strategies in order
    guardrails.ex                       # Orchestrates policy stack
    guardrails/
      policy.ex                         # @behaviour: check(context) :: :ok | {:error, reason}
      policy_violation.ex               # Struct with reason, policy, metadata
      policies/
        token_budget.ex
        cost_budget.ex
        tool_policy.ex
        content_filter.ex
        rate_limit.ex
    cost_tracker.ex                     # Usage → cost calculation
    cost_tracker/
      pricing.ex                        # Model pricing tables (configurable)
    event_log.ex                        # Public append API + query API
    telemetry_handler.ex                # Attach to [:phoenix_ai, ...] events
    migrations/                         # Migration templates (not auto-run)
      conversation_migration.ex
      event_log_migration.ex
      cost_records_migration.ex

mix/
  tasks/
    phoenix_ai_store.gen.migration.ex  # mix phoenix_ai_store.gen.migration
```

---

## Architectural Patterns

### 1. Optional Ecto Dependency (Oban Pattern)

Ecto is declared `optional: true` in `mix.exs`. Modules that depend on it are wrapped with a compile-time guard:

```elixir
# mix.exs
defp deps do
  [
    {:phoenix_ai, "~> 0.1"},
    {:ecto_sql, "~> 3.10", optional: true},
    {:nimble_options, "~> 1.1"}
  ]
end
```

```elixir
# lib/phoenix_ai_store/adapters/ecto.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAIStore.Adapters.Ecto do
    @behaviour PhoenixAIStore.Adapter
    # ... implementation
  end
end
```

The InMemory adapter has zero deps and is always available. The Ecto adapter compiles only when Ecto is present. This ensures library users who only want in-memory (dev/test) do not install Ecto.

**Source confirmation:** This exact pattern is used by the Dataloader library and documented in the Elixir Forum thread on optional dependencies. The `optional: true` flag in mix.exs prevents the dep from being forced on downstream users; `Code.ensure_loaded?/1` gates compilation.

### 2. Behaviour-Based Adapters

Three parallel behaviour trees, each following the same contract pattern from Aaron Renner's Elixir Adapter Pattern (2023):

```
StorageAdapter (@behaviour PhoenixAIStore.Adapter)
  └── Adapters.Ecto
  └── Adapters.InMemory
  └── User-supplied adapter

MemoryStrategy (@behaviour PhoenixAIStore.Memory.Strategy)
  └── Memory.SlidingWindow
  └── Memory.TokenTruncation
  └── Memory.Summarization
  └── Memory.Pinned
  └── Memory.Pipeline (meta-strategy: composes others)

GuardrailPolicy (@behaviour PhoenixAIStore.Guardrails.Policy)
  └── Policies.TokenBudget
  └── Policies.CostBudget
  └── Policies.ToolPolicy
  └── Policies.ContentFilter
  └── Policies.RateLimit
  └── User-supplied policy
```

Each behaviour is a single `@callback` that accepts a typed struct and returns `{:ok, result} | {:error, term}`. User-supplied implementations are first-class: the config accepts any module implementing the behaviour.

### 3. GenServer + ETS for InMemory Adapter

The InMemory adapter uses a GenServer as the ETS owner process to prevent table loss on restart:

```
PhoenixAIStore.Supervisor
  └── PhoenixAIStore.Adapters.InMemory.Server (GenServer)
        └── owns :phoenix_ai_store_conversations (ETS :set, :named_table, :public)
```

Conversation data is stored in ETS keyed by conversation ID. The GenServer handles crash recovery (table re-creation on restart). This pattern provides:
- Concurrent reads without bottleneck
- GenServer holds write coordination if needed
- Table survives individual caller crashes (owner is separate process)

### 4. Telemetry Handler (Dual Integration Modes)

Users choose one of two integration modes. Both are fully supported — they are not mutually exclusive and can coexist:

**Mode A — Explicit API (recommended for full control):**
```
User code
  → PhoenixAIStore.converse(conversation_id, prompt, opts)
      → load conversation from store
      → apply memory strategy
      → run guardrails check
      → call AI.Agent.prompt/2 with messages: [...]
      → receive Response
      → persist updated conversation
      → record cost
      → append to event log
      → return response
```

**Mode B — Telemetry Handler (zero-code integration):**
```
PhoenixAIStore.TelemetryHandler.attach()
  → listens to [:phoenix_ai, :chat, :stop]
                [:phoenix_ai, :tool_call, :stop]
                [:phoenix_ai, :stream, :stop]
  → on event: extract conversation_id from metadata
              → persist Response.usage → CostTracker
              → append to EventLog
              → optionally update conversation messages
```

Mode B is limited: it cannot intercept pre-call guardrails checks (those require the explicit API). The TelemetryHandler is best for retrofitting cost/event tracking onto existing PhoenixAI usage without restructuring code.

### 5. NimbleOptions Configuration Schema

All public APIs validate their options via NimbleOptions schemas defined at the module level. This provides:
- Compile-time documentation generation
- Runtime validation with clear error messages
- Consistent `{:ok, validated_opts} | {:error, NimbleOptions.ValidationError.t()}` return shape

```elixir
@store_opts_schema NimbleOptions.new!([
  adapter: [type: :atom, required: true],
  memory_strategy: [type: :atom, default: PhoenixAIStore.Memory.SlidingWindow],
  policies: [type: {:list, :atom}, default: []],
  ...
])
```

### 6. Append-Only Event Log

The EventLog never modifies or deletes rows. It uses:
- Auto-incrementing `id` + `inserted_at` for cursor-based pagination
- `conversation_id` foreign key (indexed)
- `event_type` enum column (indexed)
- `payload` JSONB for event-specific data
- `redacted_at` nullable timestamp (marks redaction without destroying record)

Inserts are fire-and-forget (cast to the EventLog process or direct Repo.insert). Reads use cursor pagination: `WHERE id > :cursor ORDER BY id ASC LIMIT :page_size`.

### 7. Cost Tracker — Pricing Table Pattern

Model pricing is stored as a configurable map (not hardcoded), supporting runtime overrides:

```elixir
# Default pricing config (users override in application config)
%{
  {"openai", "gpt-4o"} => %{input: 2.50, output: 10.00},   # per 1M tokens
  {"anthropic", "claude-3-5-sonnet"} => %{input: 3.00, output: 15.00},
  ...
}
```

CostTracker reads `Response.usage` (normalized by PhoenixAI), multiplies by pricing table entries, persists a `CostRecord` to Ecto (when adapter is Ecto), and emits `[:phoenix_ai_store, :cost, :recorded]` telemetry.

---

## Data Flow

### Request Flow (Explicit API)

```
1. PhoenixAIStore.converse(conv_id, user_message, opts)
   │
2. StorageAdapter.load(conv_id)
   → returns %Conversation{messages: [...], metadata: %{}}
   │
3. Memory.Strategy.apply(conversation.messages, strategy_opts)
   → trims/summarizes → returns pruned message list
   │
4. Guardrails.check(%{conversation: conv, message: user_message, opts: opts})
   → runs policies in order → {:ok, :pass} | {:error, %PolicyViolation{}}
   │
5. [if :pass] PhoenixAI.Agent.prompt(agent, user_message, messages: pruned_messages)
   OR         AI.chat(provider, pruned_messages ++ [new_message], opts)
   → returns {:ok, %Response{usage: %Usage{...}, message: %Message{}}}
   │
6. StorageAdapter.save(%Conversation{messages: updated_messages})
   │
7. CostTracker.record(conversation_id, response.usage, model_info)
   → persists CostRecord
   → emits [:phoenix_ai_store, :cost, :recorded]
   │
8. EventLog.append(conversation_id, :response_received, %{response: response})
   │
9. return {:ok, response}
```

### State Management (InMemory Adapter)

```
ETS table: :phoenix_ai_store_conversations
  key: conversation_id (string UUID)
  value: %PhoenixAIStore.Conversation{} struct (full struct serialized)

Read path:  ETS.lookup(table, id) → {:ok, conv} | {:error, :not_found}
Write path: ETS.insert(table, {id, conv})  (last-write-wins; no transactions)

Concurrent access: ETS is public + read_concurrency: true
Write safety: serialized through GenServer if write conflicts are a concern
             (for v1, direct ETS insert is acceptable; single-writer pattern)
```

### State Management (Ecto Adapter)

```
Postgres/SQLite schemas:
  conversations     (id uuid PK, user_id, metadata jsonb, inserted_at, updated_at)
  messages          (id, conversation_id FK, role, content, token_count, inserted_at)
  event_log         (id bigserial PK, conversation_id FK, event_type, payload jsonb, inserted_at)
  cost_records      (id, conversation_id FK, model, provider, input_tokens, output_tokens, cost_usd, inserted_at)

All reads/writes go through the user-configured Ecto.Repo (same repo as their app).
Migrations are generated via mix task, not auto-run.
```

---

## Anti-Patterns

### Anti-Pattern 1: Storing Messages Outside the Conversation Struct
**What goes wrong:** Separate messages table with join required on every load adds latency and complicates the memory strategy layer.
**Why bad:** Memory strategies operate on the full ordered message list; requiring a join to assemble it creates a leaky abstraction.
**Instead:** Store messages as an embedded JSONB array on the conversation row (fast, atomic) OR as a separate table but always load them together via a preload. Embedding is simpler for v1; separate table is better for querying individual messages. Choose one and commit.

### Anti-Pattern 2: Putting Persistence Logic Inside the Memory Strategy
**What goes wrong:** Strategies that write to the DB (e.g., summarization that saves the summary) create coupling between stateless transformation and stateful persistence.
**Instead:** Strategies return a transformed message list. The Store API decides what to persist. Summarization strategy returns the compressed messages; the API saves them.

### Anti-Pattern 3: Hard-coding the Ecto Repo
**What goes wrong:** `MyApp.Repo` references scattered through the library code.
**Instead:** Accept `repo` as config option (Oban pattern). The adapter receives the repo at initialization; the library never imports application code.

### Anti-Pattern 4: Synchronous Telemetry Handlers Blocking the AI Call
**What goes wrong:** Telemetry handlers run synchronously in the emitter's process. A slow EventLog insert blocks the PhoenixAI response path.
**Instead:** TelemetryHandler casts to a GenServer (fire-and-forget) or uses Task.start for persistence side effects. The 2024 async telemetry pattern (collect events + periodic batch flush via GenServer timeout) is appropriate for high-throughput scenarios.

### Anti-Pattern 5: Global Mutable Pricing Config
**What goes wrong:** Application.put_env calls mutating pricing at runtime create race conditions in concurrent environments.
**Instead:** Pass pricing config via opts at CostTracker.record/3 call site, falling back to compile-time defaults. NimbleOptions validates the schema.

### Anti-Pattern 6: Running Guardrails After the AI Call
**What goes wrong:** Post-call guardrails cannot prevent spending; they can only detect violations after cost is incurred.
**Instead:** Guardrails run before the AI call (pre-flight check). Budget guardrails estimate cost from conversation history; actual cost is reconciled post-call.

---

## Integration Points

### With PhoenixAI Agent (manage_history: false)

```elixir
# Start agent with history management disabled
{:ok, agent} = PhoenixAI.Agent.start_link(
  provider: :openai,
  model: "gpt-4o",
  manage_history: false,   # Store controls history externally
  system: "You are a helpful assistant."
)

# Each call passes full managed history
{:ok, response} = PhoenixAI.Agent.prompt(agent, "Hello",
  messages: pruned_message_list   # Store-assembled, strategy-applied
)
```

This integration requires zero changes to PhoenixAI. The Agent GenServer is stateless per prompt; the Store is the single source of truth for history.

### With AI.chat (stateless calls)

```elixir
# Simpler integration bypassing the Agent GenServer
{:ok, response} = PhoenixAI.AI.chat(
  :openai,
  pruned_message_list ++ [%PhoenixAI.Message{role: :user, content: user_input}],
  model: "gpt-4o",
  api_key: key
)
```

### With PhoenixAI Telemetry Events

PhoenixAI emits the following events the TelemetryHandler attaches to:
- `[:phoenix_ai, :chat, :start | :stop | :exception]`
- `[:phoenix_ai, :stream, :start | :stop | :exception]`
- `[:phoenix_ai, :tool_call, :start | :stop | :exception]`
- `[:phoenix_ai, :pipeline, :start | :stop | :exception]`
- `[:phoenix_ai, :team, :start | :stop | :exception]`

The Store also emits its own events:
- `[:phoenix_ai_store, :conversation, :saved]`
- `[:phoenix_ai_store, :memory, :trimmed]`
- `[:phoenix_ai_store, :guardrail, :violated]`
- `[:phoenix_ai_store, :cost, :recorded]`
- `[:phoenix_ai_store, :event_log, :appended]`

### With User's Application Supervision Tree

```elixir
# In user's application.ex
children = [
  MyApp.Repo,
  {PhoenixAIStore, adapter: PhoenixAIStore.Adapters.Ecto, repo: MyApp.Repo}
  # PhoenixAIStore.Supervisor starts only if InMemory adapter is selected
]
```

The library's supervision tree is minimal: only the InMemory GenServer (ETS owner) needs to be supervised. The Ecto adapter is stateless and needs no supervised process.

---

## Suggested Build Order (Component Dependencies)

Building components in this order respects hard dependencies:

```
Phase 1 — Foundation (no deps on other Store components)
  1a. Conversation struct + Adapter behaviour
  1b. InMemory adapter (ETS GenServer)
  1c. Ecto adapter + schemas + mix gen.migration task

Phase 2 — Core Pipeline (depends on Phase 1)
  2a. Memory.Strategy behaviour + SlidingWindow + TokenTruncation
  2b. Memory.Summarization (depends on having AI.chat integration working)
  2c. Memory.Pipeline (composes strategies)

Phase 3 — Governance (depends on Phase 1; partially Phase 2 for token counts)
  3a. Guardrails.Policy behaviour + PolicyViolation struct
  3b. Built-in policies (TokenBudget, ToolPolicy, ContentFilter first; CostBudget after Phase 4)
  3c. Guardrails orchestrator (runs stack in order)

Phase 4 — Cost Tracking (depends on Phase 1 + Ecto schema + PhoenixAI Usage struct)
  4a. CostTracker.Pricing table + config
  4b. CostTracker.record/3 + CostRecord Ecto schema
  4c. CostBudget policy (depends on 4b for aggregate queries)

Phase 5 — Event Log (depends on Phase 1 Ecto schemas)
  5a. EventLog Ecto schema + append/1
  5b. EventLog query API (cursor pagination)
  5c. Redaction support

Phase 6 — Telemetry Integration (depends on all above)
  6a. TelemetryHandler.attach() to [:phoenix_ai, ...] events
  6b. Store-side [:phoenix_ai_store, ...] event emission
  6c. Public API converse/2 composing all layers

Phase 7 — Polish
  7a. NimbleOptions validation throughout
  7b. Dialyzer typespecs
  7c. Comprehensive docs + usage guide
```

**Critical path:** Phase 1 → Phase 2 → Phase 6c (converse/2 is usable end-to-end)
**Blocker:** Phase 4 cannot be finalized until PhoenixAI ships a normalized `Usage` struct (noted as a pending upstream dependency).

---

## Sources

- [Elixir Adapter Pattern — Aaron Renner (2023)](https://aaronrenner.io/2023/07/22/elixir-adapter-pattern.html) — HIGH confidence; comprehensive walkthrough of behaviour/adapter pattern in Elixir
- [Optional Dependencies in Elixir Libraries — Elixir Forum](https://elixirforum.com/t/is-there-a-guide-for-relying-on-optional-dependencies-in-a-library/37318) — HIGH confidence; community consensus on `Code.ensure_loaded?` pattern
- [Oban — HexDocs v2.21.1](https://hexdocs.pm/oban/Oban.html) — HIGH confidence; peer dependency / repo injection pattern
- [Oban GitHub — oban-bg/oban](https://github.com/oban-bg/oban) — HIGH confidence; engine pluggability pattern
- [NimbleOptions — HexDocs v1.1.1](https://hexdocs.pm/nimble_options/) — HIGH confidence; options validation schema pattern
- [PhoenixAI.Agent — HexDocs v0.1.0](https://hexdocs.pm/phoenix_ai/PhoenixAI.Agent.html) — HIGH confidence; `manage_history: false` + `messages:` option confirmed
- [Async Elixir Telemetry — Christian Alexander (2024)](https://christianalexander.com/2024/02/21/async-elixir-telemetry/) — MEDIUM confidence; async telemetry GenServer batch pattern
- [Telemetry — Phoenix Framework Guides](https://hexdocs.pm/phoenix/telemetry.html) — HIGH confidence; standard attach/4 pattern
- [ETS vs GenServer State — Elixir Forum](https://elixirforum.com/t/alternative-design-using-ets-tables-to-store-each-genservers-data-instead-of-the-genservers-data-instead-of-the-genservers-state/67528) — MEDIUM confidence; ETS-as-owned-table pattern for concurrent reads
- [Append-Only Log with Ecto — dwyl/phoenix-ecto-append-only-log-example](https://github.com/dwyl/phoenix-ecto-append-only-log-example) — MEDIUM confidence; immutable event log with Ecto pattern
- [Writing Extensible Elixir with Behaviours — Darian Moody](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/) — HIGH confidence; behaviour-based pluggable backend design
- [Managing Distributed State with GenServers — AppSignal (2024)](https://blog.appsignal.com/2024/10/29/managing-distributed-state-with-genservers-in-phoenix-and-elixir.html) — MEDIUM confidence; GenServer state management patterns
