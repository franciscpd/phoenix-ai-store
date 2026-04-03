# Phase 1: Storage Foundation - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the core storage contract: Adapter behaviour with pluggable backends (InMemory + Ecto), Conversation and Message structs with Ecto schemas, migration generator mix task, and NimbleOptions configuration. This phase produces the foundation every subsequent phase builds on.

</domain>

<decisions>
## Implementation Decisions

### Conversation Schema
- **D-01:** Messages stored in a **separate table** with FK to conversations — enables querying by role, content, timestamps, and is better for Event Log and Memory strategies downstream
- **D-02:** `user_id` is **configurable** — developer chooses via config whether it's required or optional (supports both authenticated apps and anonymous chatbots)
- **D-03:** IDs use **UUID v7** (sortable by timestamp) — good for cursor-based pagination in Event Log. Since minimum Elixir is 1.15 (pre-1.18), use an external library for UUID v7 generation
- **D-04:** Timestamps use **`utc_datetime_usec`** — maximum precision, recommended Ecto standard
- **D-05:** Metadata uses **specific columns + JSONB** — named columns for `title`, `tags` (array), `model` + a `metadata` JSONB column for arbitrary custom fields
- **D-06:** Delete is **configurable** — developer chooses hard delete or soft delete (via `deleted_at` timestamp) through config

### Adapter Behaviour API
- **D-07:** **6 conversation-level callbacks**: `save_conversation` (upsert), `load_conversation`, `list_conversations`, `delete_conversation`, `count_conversations`, `conversation_exists?`
- **D-08:** **Message-level callbacks** also in the behaviour: `add_message`, `get_messages` — adapter operates at both conversation and message level
- **D-09:** `save_conversation` is **upsert** semantic — if ID exists, update; if not, create. Single callback simplifies the consumer
- **D-10:** Missing conversation returns **`{:error, :not_found}`** — explicit error, forces consumer to handle the case. Follows PhoenixAI's `{:ok, t} | {:error, term}` pattern

### Migration Strategy
- **D-11:** Mix task generates **a single migration** with all tables — `mix phoenix_ai_store.gen.migration` (Oban pattern)
- **D-12:** Table names have a **configurable prefix** — default `phoenix_ai_store_` but developer can override (Oban uses `oban_` pattern)

### Project Bootstrap
- **D-13:** Root module is **`PhoenixAI.Store`** — namespaced under PhoenixAI family, indicates sub-package relationship
- **D-14:** Minimum Elixir version stays at **>= 1.15** (matching PhoenixAI constraint) — UUID v7 via external dependency
- **D-15:** Configuration supports **both global and per-instance** — `config :phoenix_ai, :store, adapter: ...` as default + `PhoenixAI.Store.start_link(adapter: ...)` for multi-store apps
- **D-16:** License is **MIT**

### Carried Forward (from project initialization)
- **D-17:** Ecto adapter module must be wrapped entirely in `if Code.ensure_loaded?(Ecto)` — not individual macros (confirmed by José Valim)
- **D-18:** InMemory adapter uses a **supervised GenServer as ETS table owner** — not the calling process
- **D-19:** All configuration validated via **NimbleOptions** at init time, not at call time

### Claude's Discretion
- Exact NimbleOptions schema structure
- Internal module organization within `lib/phoenix_ai/store/`
- Test structure and helper modules
- ExDoc configuration

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PhoenixAI Source (peer dependency)
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/agent.ex` — Agent GenServer with `manage_history: false` + `messages:` pattern
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/message.ex` — Message struct definition (role, content, tool_calls, metadata)
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/response.ex` — Response struct with `usage` field
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/conversation.ex` — Existing stub (id, messages, metadata) — Store defines its own
- `~/Projects/opensource/phoenix-ai/mix.exs` — Dependency versions to match (nimble_options ~> 1.1, telemetry ~> 1.3)

### Project Planning
- `.planning/PROJECT.md` — Constraints, key decisions, core value
- `.planning/REQUIREMENTS.md` — STOR-01→07, INTG-05 requirements for this phase
- `.planning/research/STACK.md` — Recommended stack with versions and rationale
- `.planning/research/ARCHITECTURE.md` — Component boundaries and build order
- `.planning/research/PITFALLS.md` — Optional Ecto compile-time trap, ETS ownership pitfall

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing code — this is a greenfield project. The `lib/` directory and `mix.exs` do not exist yet.

### Established Patterns (from PhoenixAI peer dependency)
- **Behaviours with `@callback`** — PhoenixAI uses behaviours for Provider, Tool interfaces
- **`{:ok, t} | {:error, term}` returns** — consistent across all PhoenixAI public functions
- **NimbleOptions `new!/1` at compile time** — PhoenixAI validates options schemas once, not per-call
- **Telemetry spans** — PhoenixAI uses `telemetry:span/3` for chat/stream operations
- **GenServer with `Process.flag(:trap_exit, true)`** — Agent pattern for supervised processes

### Integration Points
- The Store will be consumed by users who also use `PhoenixAI.Agent` — the `messages:` option on `prompt/3` is the primary integration point
- PhoenixAI's `Conversation` stub exists but Store defines its own — no collision if module names differ

</code_context>

<specifics>
## Specific Ideas

- Table prefix should default to `phoenix_ai_store_` but be overridable like Oban's `oban_` prefix
- Metadata columns: `title` (string), `tags` (array), `model` (string) + `metadata` (JSONB map) for custom fields
- UUID v7 for all IDs — need an external library since Elixir 1.15 doesn't have native UUID v7

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-storage-foundation*
*Context gathered: 2026-04-03*
