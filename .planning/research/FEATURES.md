# Feature Research

**Domain:** AI conversation persistence & governance (Elixir library)
**Researched:** 2026-04-03
**Confidence:** HIGH (Store module patterns), MEDIUM (Memory strategy nuances), HIGH (Guardrails taxonomy), MEDIUM (Cost tracking precision requirements)

---

## Research Sources Summary

Examined: LangChain memory (Python + Elixir port), LangMem SDK, AgentSessionManager (Elixir v0.8.0),
Instructor Elixir, Oban migration pattern, LangChain for Elixir (brainlid), Amazon Bedrock Guardrails,
industry audit trail standards.

---

## Feature Landscape

### Table Stakes

Features users expect from any AI conversation persistence library. Missing = product feels incomplete or unshippable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Load conversation from storage | Without this, every session starts blank. Core value proposition. | Low | Must return `{:ok, conversation}` or `{:error, :not_found}` |
| Save conversation to storage | Without this, nothing persists. Core value proposition. | Low | Must be idempotent; upsert semantics |
| List conversations by user/tenant | Every real app needs to show "your conversations". Essential for multi-user apps. | Low | Pagination required from day one — unbounded lists cause production issues |
| Delete conversation | GDPR/privacy compliance. Users expect ability to delete history. | Low | Soft-delete preferred; hard-delete for compliance |
| Ecto adapter (Postgres/SQLite) | Production Elixir apps run on Ecto. Without this the library is dev-only. | Medium | Follows Oban's optional-dep pattern exactly |
| InMemory adapter (ETS-backed) | Test suites cannot depend on a database. Every serious library provides this. | Low | Also useful for dev prototyping |
| Pluggable store behaviour | Without this, users are locked in. Behaviour contract is the extensibility mechanism. | Low | `@callback save_conversation/1`, `load_conversation/1`, etc. |
| Sliding window memory strategy | LangChain's most-used memory type. Keeps last N messages. Every chat app needs this. | Low | `keep_last: N` — drop oldest, preserve system message |
| Token-aware truncation | Context windows are finite. Blowing the limit causes hard API errors. | Medium | Must be provider/model-aware; tiktoken-equivalent for Elixir |
| Pinned messages (never-evict) | System prompts must survive truncation. Without this, memory strategies are dangerous. | Low | Flag on message struct; respected by all strategies |
| `{:ok, t} \| {:error, term}` return types | Elixir convention. Violating it forces users to wrap every call. | Low | Non-negotiable for library credibility |
| NimbleOptions config validation | PhoenixAI uses it. Elixir ecosystem expects it. Runtime errors from bad config are painful. | Low | Config validated at init time, not at call time |
| Conversation metadata (user_id, timestamps) | Multi-user apps need owner tracking. Compliance needs timestamps. | Low | `user_id`, `inserted_at`, `updated_at`, `metadata` map minimum |
| Telemetry events | Standard Elixir observability. Libraries without telemetry can't be monitored in production. | Low | Follow `[:phoenix_ai_store, :module, :event]` naming convention |
| Policy violation errors with clear reason | Silent failures are worse than errors. Callers need to handle violations explicitly. | Low | `{:error, %PolicyViolation{rule: atom, reason: string, context: map}}` |
| Token budget guardrail | Most common production concern. Prevents runaway costs from a single conversation. | Medium | Per-conversation and per-user scopes both required |
| Cost tracking per conversation | Operators need to know what conversations cost. This is a basic operational requirement. | Medium | Depends on normalized `Usage` struct from PhoenixAI |
| Append-only event log | Compliance, debugging, and replay. "What happened in this conversation?" is asked constantly. | Medium | Immutable by design; never update, never delete event rows |
| Mix task for migration generation | Oban set the bar. Elixir developers expect `mix my_lib.gen.migration`. Without it, setup is painful. | Low | Generates both up/down, user reviews before running |
| Conversation struct with persistence fields | PhoenixAI's stub has no user_id, timestamps. The Store must define its own. | Low | Not a fork — a separate struct that wraps/maps to PhoenixAI structs |

### Differentiators

Features that make `phoenix_ai_store` stand out versus rolling your own or using AgentSessionManager.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Summarization memory strategy | Keeps old context without blowing token limit. LangChain calls this the most "human-like" strategy. AgentSessionManager lacks it. | High | Requires an AI call to summarize; async-friendly; must pin the summary as a system message |
| Composable strategy pipeline | Chain strategies: pin → summarize → slide → truncate. No other Elixir lib does this cleanly. | Medium | Each strategy is a behaviour; pipeline applies them in order |
| Policy stacking (inspired by AgentSessionManager) | Multiple policies merge deterministically: `[TokenBudget, CostBudget, ToolPolicy]`. Each independently evaluable. | Medium | Violation returns first-failing policy by default; configurable to collect-all |
| Cost budget guardrail (not just token budget) | Token budgets break when models change price. Dollar-denominated budgets are model-agnostic. | Medium | Requires model pricing table; configurable per provider/model |
| Tool policy (allow/deny per conversation) | Fine-grained tool governance. "This user conversation may not call payment tools." | Medium | Allow-list and deny-list semantics; conversation-scoped overrides global |
| Redaction support on event log | GDPR/HIPAA requirement. Strip PII from events before persistence. | Medium | Configurable redaction functions per event field; inspired by AgentSessionManager's EventRedactor |
| Cursor-based event log pagination | Required for streaming/replaying large conversation histories without loading all events. | Medium | Monotonic sequence numbers as cursor; `after_cursor:` param |
| Rate limiting guardrail | Prevents abuse. "Max 10 requests per minute per user." | Medium | Configurable window and max; ETS-backed counter for InMemory, DB-backed for Ecto |
| Per-user cost aggregation | "How much has user X spent this month?" Enables billing integrations. | Medium | Aggregation query across conversations; indexed on user_id |
| Telemetry handler (automatic capture) | Zero-config integration alternative. Attach telemetry handler, Store captures everything automatically. | High | Reads PhoenixAI telemetry events and routes to Store without explicit API calls |
| Behaviour-driven design throughout | Every module is extensible. Custom Store, Memory, Policy all defined by behaviour contract. Instructor-inspired. | Low | This is an architectural choice that enables the entire composability story |
| Content filtering hooks (pre/post) | Input/output validation. Block jailbreaks, PII, off-topic content. User-provided functions. | Medium | Pre-hook runs before sending to API; post-hook runs on response before persisting |
| Cost reporting queries | Time-range, provider, model, user, conversation facets. Enables dashboards and billing. | Medium | Ecto-backed only; query API returns structured results |
| Event replay / conversation reconstruction | Reconstruct full conversation state from event log alone. Useful for debugging and compliance audits. | High | Requires event log to be a superset of conversation state |
| Model pricing table (configurable) | Hardcoded prices go stale. Pluggable pricing table means users can update without waiting for a library release. | Low | Default table ships with library; override via config or runtime function |

### Anti-Features

Things that might be requested but should be deliberately excluded from `phoenix_ai_store`.

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| RAG / vector embeddings | "Store my documents alongside conversations" | Completely different concern: chunking, embedding models, vector DBs, retrieval strategies. Adding it couples two unrelated domains and massively increases surface area. | Separate library. Recommend `rag` (Bitcrowd) or `pgvector` direct integration. |
| Provider routing / failover | "If OpenAI fails, try Anthropic" | Belongs in PhoenixAI core where provider abstraction already lives. Duplicating it here creates version conflicts and diverging behavior. | PhoenixAI core (Teams already has multi-provider patterns). |
| Multi-agent workflow orchestration | "Run agents in DAGs/pipelines" | AgentSessionManager tried this and brought 16 dependencies. Scope creep that makes the library unusable for simple cases. | PhoenixAI core Pipelines and Teams. |
| Real-time UI / LiveView components | "Give me a chat UI component" | Application concern. Library authors can't anticipate every UI framework version. | User's Phoenix app. Example apps in the repo instead. |
| Automatic migration execution | "Just run migrations for me" | Breaks the user's migration ownership model. Unexpected schema changes at boot are dangerous. Oban deliberately avoided this. | `mix phoenix_ai_store.gen.migration` — user controls timing. |
| Semantic memory (cross-conversation fact extraction) | "Remember user preferences across conversations" | This is LangMem-territory — requires embeddings, vector search, memory consolidation algorithms. Too complex and RAG-adjacent. | LangMem or application-level user profile storage. |
| Built-in PII detection | "Auto-detect credit cards, SSNs in messages" | Requires NLP models or regex pattern libraries that are jurisdiction-specific. False positives are worse than no detection. | User-provided content filtering hook. Provide documented examples. |
| Blockchain immutability for audit log | "Prove the log wasn't tampered with" | Over-engineering. DB-level write protection and application-level append-only semantics are sufficient for 99% of compliance needs. | Postgres row-level security + application enforcement. |
| Workspace snapshots | "Export/import entire agent state" | Not relevant for API-based chat completions. Defined as out of scope in PRD. | Export of conversation JSON via existing query API. |

---

## Feature Dependencies

```
Store (Persistence)
  └─ Ecto Adapter ──────────────────────── requires: ecto, ecto_sql, postgrex/exqlite
  └─ InMemory Adapter ──────────────────── requires: nothing (ETS built-in)
  └─ Mix Migration Task ────────────────── requires: Ecto Adapter to be meaningful

Memory (Strategies)
  └─ Pinned Messages ───────────────────── requires: Store (reads conversation)
  └─ Sliding Window ────────────────────── requires: Pinned Messages (must respect pins)
  └─ Token-Aware Truncation ────────────── requires: Pinned Messages + token counter
  └─ Summarization ─────────────────────── requires: Sliding Window OR Token Truncation
                                             requires: PhoenixAI AI.chat/2
  └─ Strategy Pipeline ─────────────────── requires: at least one strategy

Guardrails (Policies)
  └─ Token Budget ──────────────────────── requires: Store (reads usage history)
  └─ Cost Budget ───────────────────────── requires: Cost Tracking
  └─ Tool Policy ───────────────────────── requires: Store (per-conversation config)
  └─ Rate Limiting ─────────────────────── requires: Store (per-user counters)
  └─ Content Filtering ─────────────────── requires: nothing (pure function hooks)
  └─ Policy Stacking ───────────────────── requires: at least one policy

Cost Tracking
  └─ Model Pricing Table ───────────────── requires: nothing (configurable)
  └─ Per-Conversation Cost ─────────────── requires: Store + PhoenixAI Usage struct (normalized)
  └─ Per-User Aggregation ──────────────── requires: Per-Conversation Cost
  └─ Cost Budget Guardrail ─────────────── requires: Per-Conversation Cost + Guardrails
  └─ Cost Reporting Queries ────────────── requires: Per-Conversation Cost + Ecto Adapter

Event Log (Audit Trail)
  └─ Append-Only Schema ────────────────── requires: Ecto Adapter
  └─ Redaction Support ─────────────────── requires: Append-Only Schema
  └─ Cursor Pagination ─────────────────── requires: Append-Only Schema + sequence numbers
  └─ Event Replay ──────────────────────── requires: All event types captured

Telemetry Handler (Automatic Capture)
  └─────────────────────────────────────── requires: ALL modules (routes events to each)
  └─────────────────────────────────────── requires: PhoenixAI telemetry events active

Critical path for v1:
  Store → Memory → Guardrails → Cost Tracking → Event Log

PhoenixAI dependency:
  Cost Tracking ────────────────────────── BLOCKED on: PhoenixAI normalized Usage struct
  Telemetry Handler ────────────────────── BLOCKED on: PhoenixAI telemetry events (available in v0.1.0)
```

---

## MVP Definition

### Launch With (v1.0)

Minimum feature set that makes the library worth adopting. Based on the "conversations persist and restore transparently" core value.

1. **Store behaviour** with `save_conversation/1`, `load_conversation/1`, `list_conversations/1`, `delete_conversation/1`
2. **Ecto adapter** — Postgres/SQLite schemas, `mix phoenix_ai_store.gen.migration`
3. **InMemory adapter** — ETS-backed, zero deps, for tests and dev
4. **Conversation struct** — `id`, `user_id`, `messages`, `metadata`, `inserted_at`, `updated_at`
5. **Sliding window** memory strategy — `keep_last: N`, respects pinned messages
6. **Token-aware truncation** — model-aware, respects pinned messages
7. **Pinned messages** — flag on message, respected by all strategies
8. **Token budget guardrail** — per-conversation max tokens, returns `{:error, %PolicyViolation{}}`
9. **Event log** — append-only, event types: `conversation_created`, `message_sent`, `response_received`, `policy_violation`
10. **Cost tracking (basic)** — per-conversation cost from `Response.usage`, model pricing table
11. **Telemetry events** — `[:phoenix_ai_store, :store, :save]`, `[:phoenix_ai_store, :policy, :violation]`, etc.
12. **NimbleOptions config** — validated at init

### Add After Validation (v1.x)

Features that require v1.0 adoption feedback before committing to design.

1. **Summarization memory strategy** — needs real usage patterns to tune trigger thresholds
2. **Policy stacking** — need to validate the composability API before freezing the behaviour contract
3. **Cost budget guardrail** — requires PhoenixAI normalized Usage struct (separate release)
4. **Rate limiting guardrail** — design depends on whether users want per-process or distributed counting
5. **Redaction support on event log** — needs to understand what PII patterns are common in practice
6. **Per-user cost aggregation** — query API design needs user feedback
7. **Tool policy** (allow/deny per conversation) — needs validation that per-conversation tool config is the right granularity
8. **Content filtering hooks** — pre/post hook API needs real usage patterns to get right
9. **Telemetry handler (automatic capture)** — convenience feature; validate explicit API is well-adopted first

### Future Consideration (v2+)

Features that would significantly increase scope or have unresolved design questions.

1. **Event replay / conversation reconstruction** — requires full event type coverage and significant test infrastructure
2. **Cursor-based event log pagination** for streaming replay — needs event volume data to justify complexity
3. **Composable strategy pipeline** — validate that chained strategies are actually needed before building the pipeline DSL
4. **Cost reporting queries** — Ecto query API design is complex; needs use case data
5. **Ash Framework adapter** (inspired by AgentSessionManager) — only if adoption warrants it
6. **S3 / binary artifact store** (AgentSessionManager pattern) — not relevant for API-based chat completions

---

## Feature Prioritization Matrix

| Feature | User Impact | Implementation Risk | Dependencies Resolved | v1 Priority |
|---------|-------------|--------------------|-----------------------|-------------|
| Store behaviour + Ecto adapter | Critical | Low | Yes | MUST HAVE |
| InMemory adapter | Critical (testing) | Low | Yes | MUST HAVE |
| Mix migration task | High | Low | Yes | MUST HAVE |
| Sliding window memory | High | Low | Yes | MUST HAVE |
| Token-aware truncation | High | Medium | Yes (need tokenizer) | MUST HAVE |
| Pinned messages | High | Low | Yes | MUST HAVE |
| Token budget guardrail | High | Medium | Yes | MUST HAVE |
| Conversation struct | High | Low | Yes | MUST HAVE |
| Event log (basic) | Medium | Medium | Yes | MUST HAVE |
| Cost tracking (basic) | Medium | Medium | Blocked (Usage struct) | MUST HAVE (with workaround) |
| Summarization strategy | High | High | Partial (needs AI call) | DEFER to v1.1 |
| Policy stacking | Medium | Medium | Yes | DEFER to v1.1 |
| Cost budget guardrail | High | Medium | Blocked (Usage struct) | DEFER to v1.1 |
| Rate limiting | Medium | Medium | Yes | DEFER to v1.1 |
| Redaction support | Medium | Medium | Yes | DEFER to v1.1 |
| Telemetry handler (auto) | Low | High | Yes | DEFER to v1.1 |
| Per-user cost aggregation | Medium | Medium | Yes | DEFER to v2 |
| Event replay | Low | High | No | DEFER to v2 |
| Tool policy | Medium | Medium | Yes | DEFER to v1.1 |
| Content filtering hooks | Medium | Low | Yes | DEFER to v1.1 |

---

## Competitor Feature Analysis

### AgentSessionManager (Elixir, v0.8.0)
**Verdict:** Closest competitor but wrong abstraction layer. Designed for CLI agent orchestration (Claude Code, Codex, Amp), not API-based chat completions.

| Feature | Has It | Notes |
|---------|--------|-------|
| Session/Run lifecycle state machine | Yes | Overly complex for simple chat — sessions contain runs contain events |
| 20+ normalized event types | Yes | Rich, but includes shell execution events not relevant here |
| Policy stacking (token/cost/tool) | Yes | Deterministic merge is the right pattern — adopt this |
| InMemory + Ecto + Ash + S3 adapters | Yes | Good adapter breadth, but 16 dependencies for basic use |
| Cost tracking | Yes | Model-aware calculation with pricing tables — adopt this pattern |
| EventRedactor (PII strip) | Yes | Useful pattern — adopt for v1.x |
| Concurrency limiter / FIFO queuing | Yes | Over-engineering for API-based chat |
| Conversation-level abstractions | No | Uses Session/Run, not Conversation/Message |
| Memory strategies (sliding/summarize) | No | Gap — no window management |
| Summarization memory | No | Gap — no AI-based context compression |
| NimbleOptions config | Unknown | Not observed in docs |
| Mix migration generator | No | Gap — migrations are manual |
| PhoenixAI integration | No | Different provider model entirely |

**Key insight:** AgentSessionManager's event model and policy stacking are excellent patterns worth adopting. Everything else is either over-complex or mis-matched to the API-based conversation use case.

### LangChain (Python) + LangMem SDK
**Verdict:** The reference implementation for memory strategies. Comprehensive but Python-only and increasingly opinionated about LangGraph.

| Feature | Has It | Notes |
|---------|--------|-------|
| ConversationBufferMemory (full history) | Yes | Baseline — simplest, no truncation |
| ConversationBufferWindowMemory (sliding) | Yes | Keep last K turns — matches our sliding window |
| ConversationTokenBufferMemory (token-aware) | Yes | Limit by token count — matches our token truncation |
| ConversationSummaryMemory (summarize) | Yes | Summarize full history — matches our summarization strategy |
| ConversationSummaryBufferMemory (hybrid) | Yes | Summary + recent verbatim — useful advanced pattern |
| Semantic memory (facts extraction) | Yes (LangMem) | Cross-conversation — out of scope for phoenix_ai_store |
| Episodic memory (past interactions) | Yes (LangMem) | Cross-conversation — out of scope |
| Procedural memory (behavior rules) | Yes (LangMem) | System prompt evolution — out of scope |
| Pluggable storage backends | Yes | Via LangGraph checkpointers (SqliteSaver, PostgresSaver) |
| Cost tracking | No (core) | Third-party tools like LangSmith |
| Guardrails | Limited | Via separate guardrails library |
| Audit log | No (core) | Via LangSmith tracing |
| Elixir port | Partial | brainlid/langchain has no persistence layer |

**Key insight:** LangChain for Elixir leaves persistence, cost tracking, guardrails, and audit logging entirely to the application. This is the gap `phoenix_ai_store` fills.

### Instructor Elixir (thmsmlr/instructor_ex)
**Verdict:** Not a direct competitor but the gold standard for Elixir library design patterns.

| Pattern | Instructor Does | phoenix_ai_store Should Do |
|---------|-----------------|---------------------------|
| Behaviour-first design | `Instructor.Validator` behaviour | `Store`, `Memory`, `Policy` behaviours |
| Adapter pattern for providers | `adapter: Instructor.Adapters.OpenAI` | `adapter: PhoenixAIStore.Adapters.Ecto` |
| Ecto for validation/schema | Native Ecto changesets | Ecto schemas for persistence (optional dep) |
| Pluggable retry logic | `max_retries:` option | N/A (different domain) |
| `use MyLib` macro | `use Instructor` | Consider for convenience config |
| Clean `{:ok, t} \| {:error, term}` | Yes, throughout | Yes, throughout |
| NimbleOptions | Not observed | YES — follow PhoenixAI convention |

**Key insight:** Follow Instructor's behaviour-first, adapter-pattern, Ecto-optional design philosophy exactly.

### Oban (optional Ecto dependency pattern)
**Verdict:** The canonical example of how to make Ecto optional in an Elixir library.

| Pattern | How Oban Does It | How phoenix_ai_store Should Do It |
|---------|-----------------|-----------------------------------|
| Optional Ecto dep | Listed under optional deps in mix.exs | Same — `{:ecto_sql, ">= 0.0.0", optional: true}` |
| Migration generator | `mix ecto.gen.migration add_oban_jobs_table` wrapping `Oban.Migrations.up()` | `mix phoenix_ai_store.gen.migration` wrapping internal migration modules |
| Migration versioning | `Oban.Migrations.up(version: 12)` | Version-stamped migration modules |
| User-controlled timing | User runs `mix ecto.migrate` | Same — never auto-execute |
| Runtime check | `Code.ensure_loaded?(Ecto)` before Ecto-specific code | Same pattern |

**Key insight:** Oban's migration generator is a usability requirement, not a nice-to-have. Users will expect exactly this pattern.

---

## Sources

- [AgentSessionManager GitHub](https://github.com/nshkrdotcom/agent_session_manager) — Feature inventory via README analysis. MEDIUM confidence (documentation may not reflect all implementation details).
- [LangChain ConversationBufferMemory docs](https://python.langchain.com/api_reference/langchain/memory/langchain.memory.buffer.ConversationBufferMemory.html) — Memory type taxonomy. HIGH confidence (official docs).
- [LangMem conceptual guide](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/) — Long-term memory types (semantic/episodic/procedural). HIGH confidence (official LangChain docs).
- [Instructor Elixir hexdocs](https://hexdocs.pm/instructor/0.0.4/introduction-to-instructor.html) — Behaviour-driven design patterns. HIGH confidence (official package docs).
- [Oban Migrations hexdocs](https://hexdocs.pm/oban/2.5.0/Oban.Migrations.html) — Optional Ecto + migration generator pattern. HIGH confidence (official package docs).
- [LangChain for Elixir hexdocs](https://hexdocs.pm/langchain/getting_started.html) — Gap analysis: no persistence layer. HIGH confidence (confirmed absence in official docs).
- [Amazon Bedrock Guardrails](https://aws.amazon.com/bedrock/guardrails/) — Industry-standard guardrail taxonomy. MEDIUM confidence (commercial product, patterns are transferable).
- [Context Window Management Strategies](https://apxml.com/courses/langchain-production-llm/chapter-3-advanced-memory-management/context-window-management) — Token truncation and window strategy patterns. MEDIUM confidence (educational source, consistent with official LangChain docs).
- [AI Audit Trail standards](https://www.swept.ai/ai-audit-trail) — Immutable log compliance requirements. LOW confidence (single vendor source, but consistent with EU Annex 11 patterns from multiple sources).
- [Pinned messages / never-evict patterns](https://dev.to/bspann/building-conversational-ai-memory-patterns-context-management-and-conversation-design-2i58) — Community patterns for protecting system messages. LOW confidence (community source; verified by multiple posts agreeing on the pattern).
