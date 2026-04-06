# PhoenixAI Store

## What This Is

A companion Elixir library for [PhoenixAI](https://hex.pm/packages/phoenix_ai) that adds persistence, memory management, guardrails, cost tracking, and an audit event log for AI agent conversations. Users who only need `AI.chat/2` don't pay for what they don't use.

## Core Value

Conversations persist and restore transparently across process restarts, with memory strategies keeping them within context window limits — the foundation everything else builds on.

## Current Milestone: v0.2.0 Streaming Support

**Goal:** Add streaming callback support to `converse/3` so consumers can receive AI response tokens in real-time via `on_chunk` or `to` PID options.

**Target features:**
- `on_chunk` callback option in `converse/3`
- `to` PID option in `converse/3`
- Conditional routing in `call_ai/2` (stream vs chat)
- Backward compatibility (no streaming opts = identical behavior)
- Tests and documentation for both streaming modes

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

### Active

- [ ] `on_chunk` callback option in `converse/3` — dispatch `%StreamChunk{}` to a function during streaming
- [ ] `to` PID option in `converse/3` — send `{:phoenix_ai, {:chunk, chunk}}` messages to a process
- [ ] Conditional routing in `call_ai/2` — `AI.stream/2` when streaming opts present, `AI.chat/2` otherwise
- [ ] Backward compatibility — no streaming opts = identical behavior to v0.1.0
- [ ] Tests and documentation for both streaming modes

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
| Store defines its own Conversation struct | PhoenixAI's Conversation is a stub; Store needs persistence fields (user_id, timestamps, etc.) | — Pending |
| Ecto as optional dependency (Oban pattern) | InMemory adapter for dev/test doesn't need Ecto; keeps the library lightweight for simple use cases | — Pending |
| PhoenixAI normalizes Usage data (new release) | Cleaner architecture — normalization belongs at the source, not in every consumer | — Pending |
| Agent integration via manage_history: false | Already works without any changes to PhoenixAI Agent — maximum decoupling | — Pending |
| Explicit API + telemetry handler for event capture | API for control, telemetry for convenience — user chooses their integration style | — Pending |
| Mix task for migrations (Oban style) | User controls migration timing and can review generated SQL before running | — Pending |

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
*Last updated: 2026-04-05 after milestone v0.2.0 start*
