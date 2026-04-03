# Pitfalls Research

**Domain:** AI conversation persistence & governance (Elixir library)
**Researched:** 2026-04-03
**Confidence:** HIGH (Elixir-specific pitfalls verified via official docs, Elixir Forum threads, and official telemetry/Ecto sources; AI-domain pitfalls verified via multiple independent sources)

---

## Critical Pitfalls

### Pitfall 1: The Optional Ecto Dependency Compile-Time Trap

**What goes wrong:**
Modules that wrap `use Ecto.Schema` or `use Ecto.Repo` inside `if Code.ensure_loaded?(Ecto)` blocks fail to compile in host applications that don't have Ecto installed. The guard appears to work in the library's own test suite (where Ecto is always present) but breaks for users who only install the InMemory adapter.

**Why it happens:**
Elixir's compiler expands `use` macros at compile time, before the `if` condition is ever evaluated at runtime. The `Code.ensure_loaded?` check is a runtime guard; it does not prevent the compiler from attempting to resolve the `use` at expansion time. José Valim confirmed this is a fundamental language constraint: "That will never work because macros (and therefore require) are expanded before we execute 'if'." Source: [elixir-lang/elixir#8970](https://github.com/elixir-lang/elixir/issues/8970).

**How to avoid:**
Put all Ecto-dependent code in a dedicated module file that is only compiled when Ecto is present. Use `Code.ensure_loaded?/1` as a guard around the entire `defmodule` block, not around `use` statements inside a module. Follow the Dataloader pattern:

```elixir
# lib/phoenix_ai_store/adapters/ecto_adapter.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAIStore.Adapters.EctoAdapter do
    @behaviour PhoenixAIStore.StoreBehaviour
    # Ecto-specific implementation
  end
end
```

In `mix.exs`, declare Ecto as optional:

```elixir
{:ecto_sql, "~> 3.10", optional: true},
{:postgrex, ">= 0.0.0", optional: true}
```

**Warning signs:**
- Library's own tests pass, but a user opens an issue saying the library doesn't compile in a fresh project without Ecto
- Dialyzer warns about unreachable clauses inside `if Code.ensure_loaded?` blocks

**Phase to address:** Phase 1 (Conversation Persistence / Storage Backends). Must be the foundation — every subsequent adapter follows this pattern.

---

### Pitfall 2: The ETS Table Owner Process Death

**What goes wrong:**
The InMemory (ETS-backed) adapter stores all conversation state in an ETS table. If the process that owns the ETS table crashes, the table is **immediately and silently destroyed** along with all in-memory conversations. Supervisors restart the owning process, but the table is gone — no crash report for the data loss.

**Why it happens:**
ETS tables are owned by the process that called `:ets.new/2`. If that process exits for any reason (including normal shutdown), the BEAM destroys the table. This is documented behavior, not a bug, but it is consistently missed by library authors.

**How to avoid:**
Use the heir/give_away pattern. A dedicated lightweight `TableManager` process creates the ETS table, sets itself as the heir, then gives the table away to the worker process:

```elixir
defmodule PhoenixAIStore.Adapters.InMemory.TableManager do
  use GenServer

  def init(_) do
    table = :ets.new(:phoenix_ai_store_conversations, [:named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end
end
```

Alternatively, name the table and use a supervisor-owned GenServer as owner so the table outlives individual worker crashes. For dev/test use-cases (the target for InMemory), document that table data does not survive the owning process death — this is acceptable behavior to document explicitly.

**Warning signs:**
- Tests pass individually but fail when run in randomized order (state leaking between tests)
- In IEx sessions, conversations "disappear" after a function-clause crash in the adapter process

**Phase to address:** Phase 1 (InMemory adapter implementation).

---

### Pitfall 3: Token Counting Provider Mismatch — Tiktoken for Claude

**What goes wrong:**
Using OpenAI's tiktoken library (or any cl100k_base BPE approximation) to count tokens for Anthropic Claude models produces inaccurate counts — potentially off by 15-25% depending on content. This causes memory strategy thresholds to fire at the wrong point: conversations get truncated too early or overflow the actual context window.

**Why it happens:**
Anthropic Claude 3+ uses its own proprietary tokenizer. Unlike OpenAI, Anthropic does not ship a standalone local tokenizer for Claude 3+. The only way to get accurate Claude 3+ token counts is via Anthropic's Token Count API (a free endpoint on the Messages API). Any cross-provider approximation is structurally inaccurate. Source: [Counting Claude Tokens Without a Tokenizer](https://blog.gopenai.com/counting-claude-tokens-without-a-tokenizer-e767f2b6e632).

**How to avoid:**
Design the `MemoryStrategy` to be provider-aware. The token counting implementation must be dispatched per-provider:
- **OpenAI models**: Use a local tiktoken NIF or character-based approximation (100 chars ≈ 25 tokens is a common approximation)
- **Anthropic models**: Call the Anthropic Token Count API endpoint, or use the conservative `(char_count / 3.5)` approximation and add a configurable safety margin
- Expose a `token_count_fn` option so users can inject accurate counting for their provider
- Default to a safe over-count (not under-count) — truncating slightly early is better than overflowing the context window

**Warning signs:**
- Cost tracking numbers diverge from actual provider bills by more than 5% consistently
- Conversations with high Unicode density or code blocks trigger context overflow errors despite appearing within threshold

**Phase to address:** Phase 2 (Memory Management). Must be validated before token-aware truncation is implemented.

---

### Pitfall 4: Cost Pricing Table Staleness

**What goes wrong:**
Hardcoded model pricing tables become stale within months. LLM pricing collapsed 90-97% between 2023 and 2026; models like GPT-4 went from $60/M tokens to under $2/M tokens. A library with a 6-month-old pricing config makes cost guardrails meaningless — budgets fire at the wrong thresholds or never fire at all.

**Why it happens:**
Providers change prices without notice (sometimes mid-week), introduce tiered/cached pricing, deprecate model IDs, and release new models that are completely absent from any static table. Source: [AI Price Index: LLM Costs Dropped 300x](https://tokencost.app/blog/ai-price-index).

**How to avoid:**
- Ship pricing tables as **user-configurable data**, not library constants. The library provides a reasonable default table as a starting point but makes overriding trivial:
  ```elixir
  config :phoenix_ai_store, :pricing,
    "gpt-4o" => %{input: 2.50, output: 10.00},   # per 1M tokens
    "claude-3-5-sonnet-20241022" => %{input: 3.00, output: 15.00}
  ```
- Document that pricing tables **must** be verified against provider dashboards before relying on cost budgets
- Add a `pricing_updated_at` timestamp to the config so users can see when the bundled defaults were last verified
- For Phase 4 (Cost Tracking) success criterion of "matches actual billing within 5%", the test suite must mock provider prices rather than hardcoding them

**Warning signs:**
- A provider announces a price change but library version hasn't been updated
- Cost reports show 0 cost for new model variants (missing from pricing table — silent `nil` multiplication)

**Phase to address:** Phase 4 (Cost Tracking). Document limitations prominently in the module docs.

---

### Pitfall 5: GenServer Serialization of Conversation Writes

**What goes wrong:**
A single GenServer processes all storage operations sequentially. Under load, every `save_conversation/1` call queues behind every other call, creating a concurrency bottleneck that negates the BEAM's concurrency advantages. In production with hundreds of concurrent conversations, p99 write latency grows unbounded.

**Why it happens:**
GenServer processes one message at a time. This is intentional for state consistency, but it becomes a bottleneck when used as a serialization gate for database writes that do not actually require sequential ordering. Source: [Hacker News — GenServer concurrency bottleneck](https://news.ycombinator.com/item?id=24399326).

**How to avoid:**
Do not use a single central GenServer for storage operations. The Store behaviour should be implemented by stateless modules where each call opens a DB connection from the pool directly. Use the Ecto Repo's built-in connection pooling (DBConnection + Postgrex) which handles concurrency correctly. For the InMemory adapter, use ETS with `read_concurrency: true` and `write_concurrency: true` flags — ETS allows concurrent reads natively and handles concurrent writes more efficiently than message-passing to a single GenServer.

Reserve GenServers for cases where you genuinely need serialized state: rate limiter counters, per-user budget accumulators (if tracking in-process), and the TableManager for ETS ownership.

**Warning signs:**
- Load tests show throughput plateauing far below DB capacity
- GenServer mailbox grows during traffic spikes (observable via `:erlang.process_info/2` with `:message_queue_len`)

**Phase to address:** Phase 1 architecture decision. Set the pattern early — retrofitting is expensive.

---

### Pitfall 6: Telemetry Handler Silent Detachment

**What goes wrong:**
The telemetry-based automatic event capture handler crashes once (e.g., due to a malformed event payload or a pattern match error), gets detached silently by the telemetry library, and **never reattaches**. From that point on, the Store captures no events — no audit log, no cost records, no guardrail checks. Users see no error; everything appears to work until they query the audit log and find it empty.

**Why it happens:**
The telemetry library intentionally removes handlers that raise exceptions to protect the emitting process's performance. Handlers run inline in the emitting process — a crash in the handler would crash the caller. Automatic reattachment could cause infinite crash loops. Telemetry logs a warning, but that warning is easily lost in log noise. Source: [Elixir Forum — detached telemetry handlers](https://elixirforum.com/t/how-to-deal-with-detached-telemetry-handlers-caused-by-errors/56069).

**How to avoid:**
- Write telemetry handlers defensively: wrap the entire handler body in `try/rescue`, return `:ok` on any error path, and emit a `[:phoenix_ai_store, :handler, :error]` telemetry event instead of raising
- Attach handlers using module-qualified function captures (`&PhoenixAIStore.TelemetryHandler.handle/4`), never inline anonymous functions — anonymous functions have worse performance and create capture identity issues that cause duplicate-attachment warnings
- Add a health-check that periodically verifies handlers are still attached (e.g., by listing attached handlers via `:telemetry.list_handlers/1` and re-attaching missing ones from a supervised process)

```elixir
# WRONG — will detach on first pattern match failure
:telemetry.attach("handler", [:phoenix_ai, :chat, :stop], fn event, measurements, meta, config ->
  %{response: response} = meta  # crashes if :response is missing
  ...
end, nil)

# CORRECT
:telemetry.attach("handler", [:phoenix_ai, :chat, :stop],
  &PhoenixAIStore.TelemetryHandler.handle_chat_stop/4, nil)
```

**Warning signs:**
- Audit log has entries up to a timestamp then goes silent
- Cost records stop accumulating mid-session
- No errors in the application log, but `[:phoenix_ai_store, :handler, :error]` events are emitted

**Phase to address:** Phase 1 (architecture) + Phase 5 (Telemetry handler implementation). Design the handler module to be bulletproof before shipping.

---

### Pitfall 7: Behaviour Contract Over-Specification Freezing the Public API

**What goes wrong:**
The `StoreBehaviour` callback signatures encode too many implementation details (e.g., requiring specific option keys, returning adapter-specific error tuples). When a new adapter needs a different option or a new storage requirement emerges (e.g., soft delete), changing the behaviour breaks every existing adapter.

**Why it happens:**
Early library design often encodes the first adapter's quirks directly into the behaviour interface. The Ecto adapter's need for a `Repo` module becomes a callback parameter; the InMemory adapter doesn't need it but must accept it anyway. Over time, adapters accumulate workarounds for a misfit interface.

**How to avoid:**
- Keep callback signatures minimal and stable. Pass configuration via the adapter's `init/1` options, not per-call parameters
- Return `{:ok, result}` / `{:error, reason}` consistently — never adapter-specific structs in the error tuple
- Use `@optional_callbacks` for extension points (e.g., `stream_events/2`) that not all adapters will implement
- Prefer wide option maps over positional arguments for all callbacks that may gain new parameters

```elixir
# GOOD — stable signature, options absorb future additions
@callback load_conversation(id :: binary(), opts :: keyword()) ::
  {:ok, Conversation.t()} | {:error, :not_found} | {:error, term()}

# RISKY — couples the behaviour to specific option shape
@callback load_conversation(id :: binary(), repo :: module(), preloads :: list()) ::
  {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
```

**Warning signs:**
- Adding a second adapter requires changing the behaviour module
- Behaviour callbacks reference Ecto-specific types (e.g., `Ecto.Changeset.t()`)

**Phase to address:** Phase 1. Behaviour design is load-bearing — everything else implements it.

---

## Technical Debt Patterns

| Pattern | How It Accumulates | Why It Hurts Later | Prevention |
|---------|-------------------|-------------------|------------|
| Hardcoded model IDs in memory strategies | First implementation targets GPT-4 and Claude 3 Sonnet | Fails silently for new models; users file bugs instead of configuring | Accept model ID as a strategy parameter, not a constant |
| `Float` arithmetic for cost accumulation | `0.1 + 0.2 != 0.3` in IEEE 754 | Billing reports show rounding drift; fails the 5% accuracy criterion | Use `Decimal` for all monetary calculations; Ecto's `:decimal` column type |
| Mixing event capture with event storage | Telemetry handler writes directly to DB | Handler latency grows with DB load; handler detaches under DB pressure | Capture to an in-process buffer (e.g., `:queue` or a Process mailbox), drain asynchronously |
| Treating `Response.usage` as normalized | PhoenixAI v0.1 passes raw provider maps | Cost calculation code must handle every provider's shape individually | Block cost tracking on PhoenixAI's `Usage` struct normalization; document the dependency explicitly |
| Synchronous summarization in memory strategy | Easiest to implement | Summarization doubles the latency of the affected LLM call (one call for summarization + one for actual response) | Run summarization as a background `Task`; apply the summary on the next conversation load |
| Accumulating cost in the event log table | Convenient — the event is already there | Aggregate queries across millions of events become slow; violates CQRS | Maintain a separate `cost_records` table for summaries; event log is append-only source of truth |

---

## Integration Gotchas

| Integration Point | Gotcha | Consequence | Mitigation |
|------------------|--------|-------------|------------|
| `PhoenixAI.Agent` with `manage_history: false` | Agent resets to `messages: []` on restart — Store must re-inject messages on every Agent start | Conversation history silently disappears after any Agent crash/restart | Document and test the "load → inject → run → persist" loop explicitly; Agent restart detection |
| PhoenixAI telemetry event metadata shape | `[:phoenix_ai, :chat, :stop]` metadata keys are not yet normalized across providers (v0.1) | Telemetry handler pattern matching on specific keys crashes on unrecognized provider shapes | Use `Map.get/3` with defaults, not pattern matching; validate metadata shape in tests with each provider |
| `Response.usage` provider format differences | OpenAI, Anthropic, and OpenRouter all return different usage map structures | Cost calculation silently returns 0 or crashes when encountering an unknown format | Normalize `usage` in a dedicated parser; return `{:error, :usage_not_normalized}` rather than silently 0-costing |
| Ecto sandbox in tests for InMemory adapter tests | Tests that test both adapters in the same suite can leak state if ETS tables are not reset between tests | Flaky tests; false positives where InMemory returns data from a previous test | Use `on_exit` hooks to destroy ETS tables; or use a unique table name per test via `start_supervised!` |
| Peer dependency version pinning | `phoenix_ai >= 0.2.0` (for Usage struct) but `mix.exs` forgets to specify the minimum version | Library compiles against old phoenix_ai but crashes at runtime on struct access | Pin exact minimum version in `mix.exs`; add a runtime version check in `Application.start/2` |
| Mix task migration generation running twice | `mix phoenix_ai_store.gen.migration` run twice generates two migration files with the same logical content | Conflicting migrations; duplicate table creation errors | Check for existing migration files before generating; emit a clear error "migration already exists" |

---

## Performance Traps

| Area | Trap | Scale at Which It Bites | Fix |
|------|------|------------------------|-----|
| Event log INSERT on every message | Every `save_conversation` writes multiple rows synchronously | ~1,000 conversations/min | Buffer events in a `Task` or use an Oban job for async persistence |
| UUID primary keys + cursor pagination | UUIDs are not monotonically ordered; `WHERE id > cursor` produces wrong results | Any pagination query | Paginate on `(inserted_at, id)` composite index, not `id` alone |
| Conversation listing with full message preload | `list_conversations/1` preloads all messages for each conversation | 50+ conversations, each with 100+ messages | Never preload messages in list queries; load messages only in `load_conversation/1` |
| ETS `read_concurrency: false` default | `:ets.new/2` defaults to exclusive reads | 10+ concurrent readers on the same table | Always set `read_concurrency: true` for the InMemory adapter |
| Synchronous cost calculation on every response | Cost calc runs in the calling process, holding it blocked | High-frequency tool-calling pipelines | Calculate cost in a detached `Task.start/1`; emit telemetry, don't block the caller |
| Full conversation reload before every strategy application | Memory strategy loads entire conversation from DB to count tokens | Long conversations (200+ messages) | Cache the token count in the conversation metadata; invalidate on new message only |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing raw LLM responses in event log without redaction | PII, credentials, or sensitive data in system prompts ends up in the audit log and any log aggregator | Implement a configurable `redact_fn` option on the event log; default to redacting nothing but make it easy to add redaction |
| Logging full message content in telemetry events | Telemetry subscribers (e.g., AppSignal, Datadog) receive sensitive conversation content | Emit only metadata (message_id, token_count, role) in telemetry; never emit message body |
| Policy violation errors exposing internal budget state | `{:error, %PolicyViolation{remaining_budget: 0.0003, user_limit: 5.0}}` leaks financial data to callers | Return opaque `{:error, :budget_exceeded}` at the public API; log details internally only |
| ETS InMemory adapter accessible cross-process via named table | Named public ETS tables are accessible to any process in the node | Use `protected` access mode (default) — owner process writes, all other processes read; or `private` for test isolation |
| Cost records without per-user scoping at query time | `list_costs_for_user/1` is accidentally bypassable via `list_costs/0` in admin paths | Ensure all cost queries require a scope (user_id or conversation_id); make the unscoped query private |

---

## "Looks Done But Isn't" Checklist

These are completion traps where a feature appears implemented but has hidden gaps:

- [ ] **InMemory adapter passes tests but ETS table dies with its owner process** — "works in tests" because tests create and own the table themselves
- [ ] **Token counting "works" for GPT-4 but silently uses tiktoken for Claude** — no test asserts the counting strategy is provider-dispatched
- [ ] **Cost tracking accumulates but never validates against actual provider invoices** — the 5% accuracy criterion requires integration tests with real (or mock) provider responses, not just arithmetic tests
- [ ] **Guardrails block at the right threshold in unit tests but fail under concurrent load** — per-user rate limiting state stored in a GenServer that becomes a bottleneck, causing limits to be bypassed under concurrency
- [ ] **Telemetry handler attached but never verified to stay attached** — no test simulates handler detachment and reattachment; silent data loss in production
- [ ] **`mix phoenix_ai_store.gen.migration` generates valid SQL but breaks if run a second time** — idempotency not tested
- [ ] **Memory strategy applies but does not persist the trimming decision to the event log** — `memory_trimmed` event type exists in the spec but is never emitted
- [ ] **Summarization strategy implemented but blocking** — summarization fires synchronously on the conversation call path, doubling latency; the async path is never built
- [ ] **Cursor pagination returns correct results for ascending order but wrong results when paginating backwards** — bidirectional pagination requires separate index coverage
- [ ] **Ecto adapter optional dependency guard works in library CI (Ecto present) but never tested without Ecto** — CI must have a separate test suite that excludes Ecto from deps

---

## Recovery Strategies

| Failure Mode | Recovery Strategy | Urgency |
|-------------|-------------------|---------|
| ETS table destroyed (InMemory adapter) | Restart the owning process; accept data loss as documented behavior for InMemory; this is why InMemory is dev/test only | Low (expected) |
| Telemetry handler detached | Implement a supervised `HandlerGuardian` GenServer that polls `:telemetry.list_handlers/1` every 30s and reattaches missing handlers | High (silent data loss) |
| Pricing table drift causing cost overruns | Emit `[:phoenix_ai_store, :pricing, :stale]` warning events when the loaded pricing config is older than a configurable threshold (default: 30 days) | Medium |
| Memory strategy over-truncation due to token miscounting | Add a `token_count_margin: 0.9` option (default to 90% of limit) to leave a safety buffer; log when margin is triggered | Medium |
| Audit log event schema version mismatch after library upgrade | Version the event schema in the `event_schema_version` column; run migrations before reading old events | High (silent data corruption) |
| Concurrent writes creating duplicate cost records | Use database-level constraints (unique index on `(conversation_id, provider_call_id)`); return `:ok` on conflict (upsert semantics) | High |
| Provider usage struct normalization missing for new model | Return `{:error, :usage_not_available}` from cost calculation; emit a `[:phoenix_ai_store, :cost, :skipped]` telemetry event | Medium |

---

## Pitfall-to-Phase Mapping

| Phase | Topic | Primary Pitfall | Mitigation Priority |
|-------|-------|----------------|---------------------|
| Phase 1: Storage Backends | Optional Ecto dependency | Compile-time trap with `Code.ensure_loaded?` wrapping `use` | CRITICAL — must be correct before any other code is written |
| Phase 1: Storage Backends | InMemory ETS adapter | ETS table owner process death | HIGH — document data loss behavior; use heir pattern or accept and document |
| Phase 1: Storage Backends | StoreBehaviour contract | Over-specification freezing the API | HIGH — review callback signatures against both adapters before finalizing |
| Phase 1: Storage Backends | GenServer bottleneck | Centralizing writes through a single process | HIGH — use stateless adapters with pool-backed DB access from day one |
| Phase 2: Memory Management | Token counting | Provider-specific tokenizer mismatch (tiktoken vs Claude API) | CRITICAL — must be provider-dispatched; wrong here breaks all threshold logic |
| Phase 2: Memory Management | Summarization strategy | Synchronous summarization doubling call latency | MEDIUM — async path must be built alongside the sync implementation |
| Phase 3: Guardrails | Rate limiting | Distributed state inconsistency for per-user limits | MEDIUM — document single-node consistency guarantee; flag cluster limitations |
| Phase 3: Guardrails | Policy violation errors | Leaking internal budget state in error tuples | HIGH — opaque errors at public API boundary |
| Phase 4: Cost Tracking | Pricing tables | Stale hardcoded prices | CRITICAL — ship pricing as user-configurable config, not library constants |
| Phase 4: Cost Tracking | Decimal precision | Float arithmetic drift | HIGH — use `Decimal` from day one; retrofitting is painful |
| Phase 4: Cost Tracking | Usage struct normalization | `Response.usage` raw provider maps in PhoenixAI v0.1 | CRITICAL — block this phase on PhoenixAI Usage struct normalization |
| Phase 5: Event Log | Telemetry handler | Silent detachment causing event capture gap | HIGH — bulletproof handlers + supervised reattachment |
| Phase 5: Event Log | Write performance | Synchronous inserts blocking conversation flow | HIGH — async event persistence from day one |
| Phase 5: Event Log | Cursor pagination | UUID primary keys not sortable for pagination | MEDIUM — use `(inserted_at, id)` composite cursor from schema design |
| Phase 5: Event Log | Redaction | PII in raw event payloads | HIGH — configurable redaction must be implemented before any production use |
| All phases | Telemetry | Anonymous function handlers with performance penalty | LOW — use `&Mod.fun/4` captures consistently |

---

## Sources

- [Elixir Forum: Optional dependency guide](https://elixirforum.com/t/is-there-a-guide-for-relying-on-optional-dependencies-in-a-library/37318) — HIGH confidence
- [elixir-lang/elixir#8970: Code.ensure_loaded? wrapping use doesn't work](https://github.com/elixir-lang/elixir/issues/8970) — HIGH confidence (core team confirmation)
- [Elixir Forum: How to test optional dependency is truly optional](https://elixirforum.com/t/how-to-test-whether-an-optional-dependency-is-truly-optional/42833) — HIGH confidence
- [Hashrocket TIL: ETS table deleted when owning process dies](https://til.hashrocket.com/posts/oz0krqlv4e-ets-table-gets-deleted-when-owning-process-dies) — HIGH confidence
- [niahoo/blanket: ETS table survival library](https://github.com/niahoo/blanket) — HIGH confidence (reference implementation)
- [Telemetry v1.4.1 official docs](https://hexdocs.pm/telemetry/telemetry.html) — HIGH confidence
- [Elixir Forum: Detached telemetry handlers caused by errors](https://elixirforum.com/t/how-to-deal-with-detached-telemetry-handlers-caused-by-errors/56069) — HIGH confidence
- [Elixir Forum: Telemetry attach warnings — anonymous function handlers](https://elixirforum.com/t/telemetry-attach-warnings-function-passed-as-a-handler-with-id/46278) — HIGH confidence
- [Counting Claude Tokens Without a Tokenizer (GoPenAI)](https://blog.gopenai.com/counting-claude-tokens-without-a-tokenizer-e767f2b6e632) — MEDIUM confidence (third-party blog, verified against Anthropic API behavior)
- [AgentOps-AI/tokencost: Token price estimates](https://github.com/AgentOps-AI/tokencost) — MEDIUM confidence
- [AI Price Index: LLM Costs Dropped 300x (2023-2026)](https://tokencost.app/blog/ai-price-index) — HIGH confidence (observable fact)
- [Building a Scalable Audit Logging Pipeline in Elixir (DEV.to)](https://dev.to/darnahsan/building-a-scalable-audit-logging-pipeline-in-elixir-handling-millions-of-events-without-breaking-2l31) — MEDIUM confidence
- [Hacker News: GenServer concurrency bottleneck discussion](https://news.ycombinator.com/item?id=24399326) — HIGH confidence (widely validated pattern)
- [AppSignal: Building a Distributed Rate Limiter in Elixir with HashRing](https://blog.appsignal.com/2025/02/04/building-a-distributed-rate-limiter-in-elixir-with-hashring.html) — HIGH confidence
- [Appunite: Cursor-based pagination with Ecto](https://tech.appunite.com/posts/using-cursor-based-pagination-to-fetch-large-amounts-of-data-using-ecto-in-elixir) — HIGH confidence
- [pawelurbanek.com: UUID Primary Key in Phoenix with Ecto](https://pawelurbanek.com/elixir-phoenix-uuid) — MEDIUM confidence
- [Best practices for cost-efficient context management (OpenAI community)](https://community.openai.com/t/best-practices-for-cost-efficient-high-quality-context-management-in-long-ai-chats/1373996) — MEDIUM confidence
- [LLM Chat History Summarization best practices (mem0.ai)](https://mem0.ai/blog/llm-chat-history-summarization-guide-2025) — MEDIUM confidence
- [Oban mix.exs optional dependency pattern](https://github.com/sorentwo/oban/blob/master/mix.exs) — HIGH confidence (reference implementation)
