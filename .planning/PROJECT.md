# PhoenixAI Store

## What This Is

A companion Elixir library for [PhoenixAI](https://hex.pm/packages/phoenix_ai) that adds persistence, memory management, guardrails, cost tracking, and an audit event log for AI agent conversations. Users who only need `AI.chat/2` don't pay for what they don't use.

## Core Value

Conversations persist and restore transparently across process restarts, with memory strategies keeping them within context window limits — the foundation everything else builds on.

## Requirements

### Validated

- ✓ Conversation persistence with pluggable storage backends (Ecto + InMemory adapters) — v0.1.0
- ✓ Memory management strategies (sliding window, token-aware truncation, summarization, pinned messages) — v0.1.0
- ✓ Guardrails enforcement (token/cost budgets, tool policies, content filtering, rate limiting) — v0.1.0
- ✓ Cost tracking and reporting across providers and models — v0.1.0
- ✓ Immutable event log for compliance and debugging (append-only audit trail) — v0.1.0
- ✓ Mix task for Ecto migration generation (Oban-style `mix phoenix_ai_store.gen.migration`) — v0.1.0
- ✓ Telemetry handler as automatic alternative to explicit API for event capture — v0.1.0
- ✓ Store-owned Conversation struct with persistence-specific fields (user_id, timestamps, metadata) — v0.1.0
- ✓ Streaming support in `converse/3` via `on_chunk` callback and `to` PID options — v0.2.0
- ✓ Streaming observability — telemetry span and event log metadata capture streaming mode — v0.2.0

### Active

- [ ] Unify cost record querying into filter-based API (breaking change to CostStore behaviour)
- [ ] Global cost and event queries for dashboard views without conversation_id
- [ ] Cursor-based pagination for cost records

## Current Milestone: v0.3.0 Dashboard Queries

**Goal:** Enable global cost and event querying without requiring a conversation_id, so consumers can build dashboard views.

**Target features:**
- Unify `get_cost_records` into a filter-based API (conversation_id becomes optional filter)
- Update `CostStore` behaviour callback signature
- Update both adapters (Ecto + ETS)
- Add cursor-based pagination for cost records
- Verify events API filter coverage is sufficient

### Out of Scope

- RAG / vector embeddings — separate concern, different library
- Provider routing / failover — belongs in PhoenixAI core
- Multi-agent workflow orchestration — belongs in PhoenixAI core (Teams)
- Workspace snapshots — not relevant for API-based interactions
- Real-time UI / rendering — application concern
- Automatic migration execution — users control when/how migrations run via mix task

## Context

**PhoenixAI (v0.1.0)** is published on Hex and provides a unified Elixir API for AI providers (OpenAI, Anthropic, OpenRouter) with Agents, Pipelines, Teams, and Tool Calling. Key integration points:

- **Agent GenServer** already supports `manage_history: false` + external `messages:` option — the Store controls history externally without modifying the Agent
- **Response.usage** currently passes raw provider maps (different formats per provider). A new PhoenixAI release with a normalized `Usage` struct is needed before Cost Tracking can work cleanly
- **Telemetry events** already cover `[:phoenix_ai, :chat]`, `[:phoenix_ai, :stream]`, `[:phoenix_ai, :tool_call]`, `[:phoenix_ai, :pipeline]`, `[:phoenix_ai, :team]`
- **Conversation struct** in PhoenixAI is a stub (Phase 4). The Store defines its own Conversation with persistence fields
- **Message, ToolCall, ToolResult** structs are fully implemented and stable

**Integration pattern**: Load from DB → apply memory strategy → pass via `messages:` to Agent → receive Response → persist back. Explicit API as primary interface, telemetry handler as automatic alternative.

**Inspirations**: AgentSessionManager (event model, policy stacking), LangChain memory (sliding window, summarization), Instructor (behaviour-driven design), Oban (optional Ecto dependency, migration generator).

## Constraints

- **Elixir**: >= 1.15, OTP >= 26 (match PhoenixAI)
- **Peer dependency**: `phoenix_ai` on Hex (version with Usage struct normalization)
- **Ecto optional**: Only required when using the Ecto adapter — InMemory adapter (ETS-backed) has zero extra deps
- **Zero required deps beyond phoenix_ai**: Adapters bring their own dependencies
- **Patterns**: Follow PhoenixAI conventions — behaviours, `{:ok, t} | {:error, term}`, NimbleOptions, telemetry

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Store defines its own Conversation struct | PhoenixAI's Conversation is a stub; Store needs persistence fields (user_id, timestamps, etc.) | ✓ Good |
| Ecto as optional dependency (Oban pattern) | InMemory adapter for dev/test doesn't need Ecto; keeps the library lightweight for simple use cases | ✓ Good |
| PhoenixAI normalizes Usage data (new release) | Cleaner architecture — normalization belongs at the source, not in every consumer | ✓ Good |
| Agent integration via manage_history: false | Already works without any changes to PhoenixAI Agent — maximum decoupling | ✓ Good |
| Explicit API + telemetry handler for event capture | API for control, telemetry for convenience — user chooses their integration style | ✓ Good |
| Mix task for migrations (Oban style) | User controls migration timing and can review generated SQL before running | ✓ Good |
| Streaming via guard clauses, not NimbleOptions | converse/3 uses Keyword.get — consistency with existing pattern; NimbleOptions migration deferred | ✓ Good |
| Conflict error for on_chunk + to | Explicit {:error, :conflicting_streaming_options} instead of silent precedence | ✓ Good |
| TestProvider for streaming tests, not Mox | TestProvider.stream/3 already exists; consistent with existing converse test infrastructure | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-06 after v0.3.0 milestone start*
