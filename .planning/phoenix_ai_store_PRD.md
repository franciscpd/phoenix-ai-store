# PRD: PhoenixAI Store

> Companion library for [PhoenixAI](https://hex.pm/packages/phoenix_ai) providing persistence, memory management, guardrails, and cost tracking for AI agent conversations.

## Problem Statement

PhoenixAI (v0.1.0) provides a unified Elixir API for AI providers (OpenAI, Anthropic, OpenRouter) with Agents, Pipelines, Teams, and Tool Calling. By design, it keeps no persistent state — the Agent GenServer holds conversation history only in memory.

Applications building on PhoenixAI need:
- **Persistence** — Save and restore conversation history across process restarts
- **Memory management** — Handle long conversations that exceed context windows
- **Guardrails** — Enforce token budgets, content policies, and tool restrictions
- **Cost tracking** — Monitor and control spending across providers and models
- **Auditability** — Immutable event log for compliance and debugging

The existing `agent_session_manager` package (v0.8.0) was evaluated but is designed for CLI agent orchestration (Claude Code, Codex, Amp), not API-based chat completions. Its session/run/event model doesn't map cleanly to PhoenixAI's Agent/Pipeline/Team abstractions, and it brings 16 dependencies.

## Vision

A focused, composable library that plugs into PhoenixAI's existing structs (`Conversation`, `Message`, `Response`) and adds the persistence and governance layer. Users who only need `AI.chat/2` don't pay for what they don't use.

```
┌─────────────────────────────┐
│  User's Phoenix App         │
├─────────────────────────────┤
│  phoenix_ai_store           │  ← this lib
│    - Store behaviour        │
│    - Memory strategies      │
│    - Guardrails             │
│    - Cost tracker           │
├─────────────────────────────┤
│  phoenix_ai                 │  ← existing lib (runtime + providers)
│    - AI.chat/stream         │
│    - Agent, Pipeline, Team  │
│    - Providers              │
└─────────────────────────────┘
```

## Core Features

### 1. Conversation Persistence

**Goal**: Save and load conversations with pluggable storage backends.

- **Store behaviour** with callbacks: `save_conversation/1`, `load_conversation/1`, `list_conversations/1`, `delete_conversation/1`
- **Ecto adapter** (primary) — Postgres/SQLite schemas for conversations, messages, metadata
- **InMemory adapter** — For testing and development (ETS-backed)
- Integration point: `PhoenixAI.Conversation` struct (already exists as stub in PhoenixAI)
- Support for conversation metadata (tags, user_id, agent config, etc.)
- Pagination and filtering for conversation listing

### 2. Memory Management

**Goal**: Keep conversations within context window limits without losing important context.

- **Sliding window** — Keep last N messages, drop oldest
- **Token-aware truncation** — Trim based on token count per provider/model
- **Summarization** — Use the AI itself to summarize older messages into a condensed system message
- **Pinned messages** — Mark certain messages (e.g., system prompt) as never-evictable
- **Strategy behaviour** — Pluggable, composable memory strategies
- Hook into Agent's `manage_history` to apply strategies automatically before each completion call

### 3. Guardrails

**Goal**: Enforce safety and budget policies on AI interactions.

- **Token budget** — Max tokens per conversation, per time window, per user
- **Cost budget** — Max spend per conversation/user/time window
- **Tool policies** — Allow/deny specific tools per conversation or globally
- **Content filtering** — Pre/post hooks for message content validation
- **Rate limiting** — Max requests per time window
- **Policy behaviour** — Stackable, composable policies (inspired by AgentSessionManager's deterministic stacking)
- Violations return `{:error, %PolicyViolation{}}` with clear reason

### 4. Cost Tracking

**Goal**: Track and report AI usage costs across all interactions.

- **Model pricing tables** — Configurable input/output token prices per provider/model
- **Per-conversation cost** — Accumulated from `Response.usage` data
- **Per-user cost** — Aggregate across conversations
- **Cost events** — Telemetry events for real-time monitoring
- **Budget integration** — Feed into guardrails for automatic budget enforcement
- **Reporting** — Query costs by time range, provider, model, user, conversation
- **Ecto schema** for cost records linked to conversations

### 5. Event Log (Audit Trail)

**Goal**: Immutable record of all AI interactions for compliance and debugging.

- **Event types**: `conversation_created`, `message_sent`, `response_received`, `tool_called`, `tool_result`, `policy_violation`, `cost_recorded`, `memory_trimmed`
- **Immutable** — Append-only, never modified or deleted
- **Cursor-based pagination** — For streaming/replaying event history
- **Redaction support** — Strip sensitive data before persistence
- **Ecto schema** with indexed timestamps and conversation references

## Integration Points with PhoenixAI

| PhoenixAI Struct | Store Integration |
|---|---|
| `Conversation` | Persisted with ID, messages, metadata |
| `Message` | Stored as part of conversation, used by memory strategies |
| `Response` | `usage` field feeds cost tracking |
| `Agent` | Hook into `manage_history` for memory + guardrails |
| `ToolCall` / `ToolResult` | Logged in event trail, governed by tool policies |
| Telemetry events | Extended with cost and guardrail events |

## Non-Goals (v1.0)

- **RAG / Vector embeddings** — Separate concern, different lib
- **Provider routing / failover** — Belongs in PhoenixAI core
- **Multi-agent workflow orchestration** — Belongs in PhoenixAI core (Teams)
- **Workspace snapshots** — Not relevant for API-based interactions
- **Real-time UI / rendering** — Application concern

## Technical Constraints

- **Elixir >= 1.15**, OTP >= 26 (match PhoenixAI)
- **phoenix_ai** as peer dependency (not hard dep — structs can be referenced without runtime coupling)
- **Ecto as optional dep** — Only required if using Ecto adapter
- **Zero required dependencies beyond phoenix_ai** — Adapters bring their own deps
- Follow PhoenixAI patterns: behaviours, `{:ok, t} | {:error, term}`, NimbleOptions, telemetry

## Inspirations

- **AgentSessionManager** — Event model, policy stacking, storage behaviour pattern
- **LangChain memory** — Sliding window, summarization strategies
- **Instructor (Elixir)** — Clean behaviour-driven design
- **Oban** — Optional Ecto dependency pattern, migration generator

## Success Criteria

- [ ] Conversations persist and restore across Agent restarts
- [ ] Memory strategies keep conversations within token limits transparently
- [ ] Cost tracking matches actual provider billing within 5% margin
- [ ] Guardrails block policy violations before API calls are made
- [ ] Event log enables full conversation replay
- [ ] Zero impact on PhoenixAI users who don't need persistence
