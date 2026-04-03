# Project Research Summary

**Project:** PhoenixAI Store
**Domain:** AI conversation persistence & governance (Elixir library)
**Researched:** 2026-04-03
**Confidence:** HIGH

## Executive Summary

PhoenixAI Store is a companion Elixir hex library that fills the gap LangChain for Elixir, AgentSessionManager, and PhoenixAI core all leave open: durable conversation persistence, context window management, cost governance, and an immutable audit trail — packaged as a single library with zero required dependencies beyond PhoenixAI itself. The closest prior art is AgentSessionManager (wrong abstraction: CLI-agent-oriented with 16 transitive deps) and LangChain's Python memory types (right patterns, no Elixir persistence layer). The recommended architecture takes the best from both: LangChain's sliding-window/summarization memory model combined with AgentSessionManager's policy-stacking governance model, delivered through Instructor Elixir's behaviour-driven adapter design and Oban's optional-Ecto dependency pattern.

The recommended build approach is a layered foundation-first strategy. Phase 1 establishes the storage backbone (Conversation struct, Adapter behaviour, InMemory ETS adapter, Ecto adapter, migration generator) — everything else depends on this layer being stable and correctly implementing the optional-Ecto compile-time pattern. Phases 2-4 build memory strategies, guardrails, and cost tracking in dependency order. The telemetry integration and public `converse/2` facade come last, composing all prior layers. This order is non-negotiable: the behaviour contracts set in Phase 1 will be the hardest to change later, and getting them wrong cascades into every adapter.

The primary risks are not implementation complexity but architectural missteps that are cheap to avoid early and expensive to fix later: the optional-Ecto compile-time guard (José Valim confirmed that `Code.ensure_loaded?` wrapping `use` macros does not work as expected), ETS table owner process death in the InMemory adapter, telemetry handler silent detachment causing audit log gaps, and using `Float` instead of `Decimal` for cost accumulation. A blocking upstream dependency also exists: PhoenixAI v0.1 passes raw provider usage maps; cost tracking requires a normalized `Usage` struct from PhoenixAI before it can be finalized. Document this dependency explicitly and ship a `{:error, :usage_not_normalized}` guard until the upstream release ships.

---

## Key Findings

### Recommended Stack

The library should keep its footprint minimal by treating all storage-layer dependencies as optional. Only three packages are required: `phoenix_ai` (peer dep), `nimble_options` (config validation and docs generation — already used by PhoenixAI so no extra cost), and `telemetry` (also already a PhoenixAI transitive dep). Ecto, ecto_sql, and DB drivers are declared `optional: true` and guarded by `Code.ensure_loaded?(Ecto)` around the entire Ecto adapter `defmodule` block (not inside it). The `hammer` rate-limiter and `tiktoken` token counter are also optional — users who need them add them; users who don't are unaffected.

All versions are verified against Hex.pm as of 2026-04-03. The Elixir >= 1.15 / OTP >= 26 floor matches PhoenixAI's own constraints, so no extra constraint is imposed on adopters.

**Core technologies:**
- `phoenix_ai ~> 0.1`: Peer dep providing Agent, Message, Response, Usage structs and telemetry events — the Store wraps it, never replaces it
- `nimble_options ~> 1.1`: Config schema validation at module load time (not per-call); also generates documentation from specs — already a PhoenixAI dep, zero marginal cost
- `telemetry ~> 1.3`: Instrumentation for every Store operation using `[:phoenix_ai_store, :action, :start/stop/exception]` spans — already a PhoenixAI transitive dep
- `ecto ~> 3.13` + `ecto_sql ~> 3.13` (optional): Postgres/SQLite adapter only; follow the Oban pattern exactly with `optional: true` in mix.exs
- `hammer ~> 7.3` (optional): Rate limiting guardrail; ETS backend ships built-in so no extra dep for InMemory users
- `tiktoken ~> 0.4` (optional): Accurate BPE token counting via Rust NIF; fall back to `div(byte_size(text), 4)` heuristic when absent

**What NOT to use:**
- `agent_session_manager`: Wrong abstraction layer (CLI-agent model, not API-based chat); 16 transitive deps
- Hard `ecto` dep in root: Violates the zero-dep promise for InMemory users
- `GenStage`/`Broadway` for event pipeline: Overkill; synchronous Ecto insert with optional async Task is sufficient
- Any provider client library: Store is provider-agnostic; all provider communication goes through PhoenixAI

See `.planning/research/STACK.md` for full dependency list with version rationale.

---

### Expected Features

Research surveyed LangChain (Python), LangMem SDK, AgentSessionManager (Elixir v0.8), Instructor Elixir, Oban, and Amazon Bedrock Guardrails to produce a comprehensive feature taxonomy.

**Must have (table stakes — v1.0):**
- Store behaviour: `save_conversation/1`, `load_conversation/1`, `list_conversations/1`, `delete_conversation/1` — missing any of these makes the library incomplete
- Ecto adapter (Postgres/SQLite) + InMemory adapter (ETS) — production apps need Ecto; test suites need InMemory; both are required for credibility
- `mix phoenix_ai_store.gen.migration` — Oban set the bar; Elixir developers will expect this exact UX; omitting it makes adoption painful
- Conversation struct with `id`, `user_id`, `messages`, `metadata`, `inserted_at`, `updated_at` — PhoenixAI's Conversation is a stub; the Store must define its own
- Sliding window memory strategy (`keep_last: N`) with pinned-message support — LangChain's most-used memory type; critical for preventing context overflow
- Token-aware truncation — model-aware; required to prevent hard API errors on long conversations
- Pinned messages (never-evict flag) — system prompts must survive truncation; without this, memory strategies are dangerous
- Token budget guardrail returning `{:error, %PolicyViolation{}}` — the most common production cost concern
- Append-only event log with `conversation_created`, `message_sent`, `response_received`, `policy_violation` event types
- Basic cost tracking (per-conversation cost from `Response.usage`, configurable model pricing table)
- Telemetry events on every Store operation following `[:phoenix_ai_store, :module, :event]` convention
- NimbleOptions config validation at init time

**Should have (competitive differentiators — v1.x after adoption feedback):**
- Summarization memory strategy — highest user impact but requires an AI call; async path must be built alongside sync implementation
- Policy stacking (multiple policies, deterministic merge) — adopted from AgentSessionManager's event model
- Cost budget guardrail (dollar-denominated, model-agnostic) — blocked on PhoenixAI normalized Usage struct
- Rate limiting guardrail (per-user request window) — design depends on single-node vs. cluster requirements; validate with users
- Redaction support on event log (configurable `redact_fn`) — GDPR/HIPAA requirement; needed before any production use with PII
- Tool policy (allow/deny per conversation) — fine-grained governance; validate granularity with real users first
- Content filtering hooks (pre/post) — user-provided functions; avoid built-in PII detection (jurisdiction-specific, false positives)
- Telemetry handler (auto-capture mode) — validate explicit API adoption before building convenience wrapper

**Defer (v2+):**
- Event replay / conversation reconstruction — requires full event type coverage and significant test infrastructure
- Composable strategy pipeline DSL — validate that chaining strategies is actually needed in practice
- Cost reporting queries (time-range, provider, model facets) — complex Ecto query API; needs use case data
- Cursor-based event log pagination for streaming replay — needs event volume data to justify
- Ash Framework adapter — only if adoption warrants it
- Per-user cost aggregation queries — needs billing integration use cases

**Anti-features (explicitly out of scope):**
RAG/vector embeddings, provider routing/failover, multi-agent workflow orchestration, real-time UI components, automatic migration execution, semantic cross-conversation memory, built-in PII detection, and blockchain immutability. See `.planning/research/FEATURES.md` for full rationale on each.

---

### Architecture Approach

The library is structured as a layered facade with three parallel behaviour trees (Storage, Memory, Guardrails) feeding into a central public API (`PhoenixAIStore.converse/2`). All Ecto-dependent modules are gated behind `Code.ensure_loaded?(Ecto)` compile-time guards wrapping the entire `defmodule` block. The InMemory adapter uses a supervised GenServer as ETS table owner — not the calling process — to prevent table destruction on process death. Two integration modes are supported and can coexist: explicit API (full control, pre-call guardrails) and telemetry handler (zero-code, post-call capture only). All cost arithmetic uses `Decimal`, not `Float`. Pricing tables are user-configurable config, never library constants.

**Major components:**
1. `PhoenixAIStore` (public API) — `converse/2`, `load/1`, `save/1`, `history/1`; orchestrates Memory, Guardrails, StorageAdapter, CostTracker, EventLog in sequence
2. `PhoenixAIStore.Adapter` (behaviour) — `save/1`, `load/1`, `list/1`, `delete/1`; implemented by Ecto and InMemory adapters; keep callback signatures minimal and stable
3. `PhoenixAIStore.Adapters.InMemory` — ETS-backed; supervised GenServer owns the table; `read_concurrency: true, write_concurrency: true`
4. `PhoenixAIStore.Adapters.Ecto` — Postgres/SQLite via user-provided Repo; stateless (no GenServer); compiles only when Ecto is present
5. `PhoenixAIStore.Memory.Strategy` (behaviour) — `apply(messages, opts) :: messages`; stateless transforms; strategies never write to DB
6. `PhoenixAIStore.Guardrails` / `Policy` (behaviour) — ordered policy stack; run pre-call; return `{:ok, :pass} | {:error, %PolicyViolation{}}`
7. `PhoenixAIStore.CostTracker` — parses `Response.usage`, looks up configurable pricing table, persists `CostRecord`; all arithmetic in `Decimal`
8. `PhoenixAIStore.EventLog` — append-only Ecto schema inserts; fire-and-forget via `Task.start`; paginate on `(inserted_at, id)` composite index, not UUID alone
9. `PhoenixAIStore.TelemetryHandler` — attaches to `[:phoenix_ai, ...]` events; defensive `try/rescue` wrapping entire handler body; supervised reattachment guard

**Request flow (explicit API):**
`load conversation` → `apply memory strategy` → `run guardrails pre-flight` → `call PhoenixAI` → `save updated conversation` → `record cost` → `append to event log` → `return response`

See `.planning/research/ARCHITECTURE.md` for full diagrams, data flow, schema definitions, and anti-patterns.

---

### Critical Pitfalls

The following five pitfalls are the most likely to cause hard-to-reverse architectural mistakes. All five manifest silently — no immediate test failure or compiler error — making them particularly dangerous.

1. **Optional Ecto compile-time trap** — `Code.ensure_loaded?(Ecto)` does NOT guard `use Ecto.Schema` at compile time; José Valim confirmed this is a fundamental language constraint. The correct pattern is to wrap the entire `defmodule` block in the `if Code.ensure_loaded?(Ecto)` check. CI must include a separate matrix job that compiles with `--no-optional-deps` to verify this actually works. Phase 1 is the only moment this is cheap to get right.

2. **ETS table owner process death** — The ETS table is silently destroyed when its owning process dies. For dev/test InMemory use, document this explicitly and own a dedicated GenServer as the table owner (not the calling process). Tests must use `on_exit` hooks to destroy tables between test runs to prevent state leakage.

3. **Token counting provider mismatch** — tiktoken produces OpenAI-accurate BPE counts but is off 15-25% for Anthropic Claude 3+ (different proprietary tokenizer). Memory strategy token counting must be provider-dispatched: tiktoken NIF for OpenAI, Anthropic Token Count API or conservative `chars / 3.5` + safety margin for Anthropic. Expose a `token_count_fn` option so users can inject accurate counting. Default to over-counting (truncate slightly early), never under-counting.

4. **Telemetry handler silent detachment** — A single unhandled exception detaches the handler permanently; telemetry logs a warning that is easily missed; Store captures nothing thereafter. Mitigation: wrap entire handler body in `try/rescue`; emit `[:phoenix_ai_store, :handler, :error]` on any exception; attach using `&Mod.fun/4` named captures (not anonymous functions); implement a supervised `HandlerGuardian` that polls `:telemetry.list_handlers/1` every 30s and reattaches missing handlers.

5. **Float arithmetic for cost accumulation** — IEEE 754 drift accumulates across many `cost_usd` additions and makes billing reports fail the 5% accuracy criterion. Use `Decimal` for all monetary values from schema definition through to query aggregates. Retrofitting is painful; set this correctly in Phase 4 schema design.

Additional critical pitfalls documented in `.planning/research/PITFALLS.md`:
- Behaviour contract over-specification in Phase 1 (keep callback signatures minimal)
- GenServer serialization bottleneck for storage writes (use stateless adapters with Ecto pool)
- Pricing table staleness (ship as user-configurable config, never library constants)
- `Response.usage` normalization dependency on PhoenixAI upstream

---

## Implications for Roadmap

Research identifies a clear 5-phase critical path with two additional polish/telemetry phases. The ordering is derived from hard component dependencies documented in ARCHITECTURE.md and FEATURES.md.

### Phase 1: Storage Foundation

**Rationale:** Every other component depends on the Conversation struct and Adapter behaviour being stable. The optional-Ecto compile-time pattern (the most dangerous pitfall) must be solved here, once, and never revisited. Behaviour callback signatures set here are the hardest thing to change after Phase 2+ build on them.

**Delivers:**
- `PhoenixAIStore.Conversation` struct (id, user_id, messages, metadata, timestamps)
- `PhoenixAIStore.Adapter` behaviour with minimal, stable callback signatures
- `PhoenixAIStore.Adapters.InMemory` — ETS-backed, supervised GenServer owner, `read_concurrency: true`
- `PhoenixAIStore.Adapters.Ecto` — Postgres/SQLite, `Code.ensure_loaded?(Ecto)` guard around entire defmodule
- `mix phoenix_ai_store.gen.migration` Mix task (Oban pattern)
- `PhoenixAIStore.Config` — NimbleOptions schema validation
- `PhoenixAIStore.Supervisor` — minimal; only starts InMemory GenServer

**Implements features:** Store behaviour, Ecto adapter, InMemory adapter, Mix migration task, Conversation struct, NimbleOptions config, `{:ok, t} | {:error, term}` return types

**Avoids:** Optional Ecto compile-time trap (Pitfall 1), ETS table owner death (Pitfall 2), behaviour over-specification (Pitfall 7), GenServer bottleneck (Pitfall 5)

**Research flag:** Standard patterns — Oban's optional Ecto approach, Elixir Adapter Pattern (Aaron Renner 2023), and Dataloader are all well-documented references. No deeper research needed.

---

### Phase 2: Memory Management

**Rationale:** Memory strategies depend on the Conversation struct from Phase 1 (they read the message list) but have no dependency on Guardrails, Cost Tracking, or EventLog. Building memory before guardrails allows the `converse/2` flow to be partially functional (load → apply memory → call AI → save) without policy enforcement, enabling early integration testing with PhoenixAI.

**Delivers:**
- `PhoenixAIStore.Memory.Strategy` behaviour (`apply(messages, opts) :: messages`)
- `PhoenixAIStore.Memory.Pinned` — never-evict flag respected by all strategies
- `PhoenixAIStore.Memory.SlidingWindow` — `keep_last: N`, preserves pinned messages
- `PhoenixAIStore.Memory.TokenTruncation` — provider-dispatched token counting (tiktoken + heuristic fallback)
- Strategy test coverage asserting provider dispatch is exercised (not just arithmetic)

**Implements features:** Sliding window memory, token-aware truncation, pinned messages

**Avoids:** Token counting provider mismatch (Pitfall 3) — provider dispatch must be validated in this phase

**Research flag:** Sliding window and token truncation have well-documented LangChain patterns. Token counting for Anthropic models needs verification — the Anthropic Token Count API endpoint behavior should be validated before finalizing the dispatch mechanism.

---

### Phase 3: Guardrails

**Rationale:** Guardrails depend on Phase 1 (they read conversation state for budget checks) and partially on Phase 2 (token count lookups). They do not depend on Cost Tracking (Phase 4) for the TokenBudget policy — that policy reads token usage from the conversation, not dollar costs. Building guardrails before cost tracking allows the CostBudget policy to be deferred to Phase 4 without blocking the phase.

**Delivers:**
- `PhoenixAIStore.Guardrails.Policy` behaviour (`check(context) :: :ok | {:error, reason}`)
- `PhoenixAIStore.Guardrails.PolicyViolation` struct (opaque at public API boundary)
- `PhoenixAIStore.Guardrails` orchestrator (ordered policy stack, returns first violation by default)
- `PhoenixAIStore.Guardrails.Policies.TokenBudget`
- `PhoenixAIStore.Guardrails.Policies.ToolPolicy`
- `PhoenixAIStore.Guardrails.Policies.ContentFilter` (hook-based, user-provided function)

**Implements features:** Token budget guardrail, tool policy, content filtering hooks (via hooks), policy violation errors with clear reason

**Avoids:** Policy violation leaking internal budget state (Pitfall from security section — opaque errors at public API), running guardrails post-call (anti-pattern: post-call cannot prevent cost)

**Research flag:** Standard patterns. Amazon Bedrock Guardrails and AgentSessionManager's policy stacking provide clear reference models. No deeper research needed for TokenBudget and ToolPolicy. ContentFilter hook API design may benefit from reviewing a few open-source examples to get the function signature right.

---

### Phase 4: Cost Tracking

**Rationale:** Cost tracking depends on Phase 1 (Ecto schemas for CostRecord) and is partially blocked on a PhoenixAI upstream dependency: `Response.usage` in v0.1 passes raw provider maps (different shapes per provider). A PhoenixAI release with a normalized `Usage` struct is required before this phase can be finalized. The CostBudget guardrail (deferred from Phase 3) completes here.

**Delivers:**
- `PhoenixAIStore.CostTracker.Pricing` — user-configurable pricing table (never hardcoded constants), with `pricing_updated_at` timestamp
- `PhoenixAIStore.CostTracker` — `record/3` using `Decimal` for all arithmetic
- `CostRecord` Ecto schema (`conversation_id`, `model`, `provider`, `input_tokens`, `output_tokens`, `cost_usd` as `:decimal`)
- `PhoenixAIStore.Guardrails.Policies.CostBudget` (completes Phase 3 guardrail set)
- `[:phoenix_ai_store, :cost, :recorded]` telemetry event
- `{:error, :usage_not_normalized}` guard for PhoenixAI v0.1 raw usage maps

**Implements features:** Cost tracking (basic), model pricing table (configurable), cost budget guardrail

**Avoids:** Float arithmetic drift (use `Decimal` from day one — Pitfall from technical debt section), pricing table staleness (Pitfall 4), silent 0-cost on missing model (return `{:error, :usage_not_normalized}`)

**Research flag:** The PhoenixAI normalized Usage struct is a hard blocker. Before planning this phase in detail, confirm whether the upstream release is available or has a documented ETA. If blocked, implement with a normalization shim that handles known provider shapes and document limitations prominently.

---

### Phase 5: Event Log

**Rationale:** The event log depends on Phase 1 Ecto schemas and benefits from Phase 4 being complete (cost events reference CostRecord IDs). It is not on the critical path to a usable `converse/2` (that works after Phase 3) but is required before any production use with compliance requirements.

**Delivers:**
- `PhoenixAIStore.EventLog` — append-only Ecto schema, async fire-and-forget via `Task.start`
- Event types: `conversation_created`, `message_sent`, `response_received`, `policy_violation`, `memory_trimmed`, `cost_recorded`
- Cursor-based pagination on `(inserted_at, id)` composite index (not UUID alone)
- Configurable `redact_fn` option (must be in place before any PII can enter the log)
- `event_schema_version` column for forward compatibility
- Unique index on `(conversation_id, provider_call_id)` for dedup on concurrent writes

**Implements features:** Append-only event log, redaction support, cursor pagination

**Avoids:** Synchronous inserts blocking conversation flow (async Task), UUID-only cursor producing wrong pagination order (composite `(inserted_at, id)` cursor), PII in raw payloads (configurable redact_fn), telemetry handler silent detachment (Pitfall 6) — the `TelemetryHandler` module is built here and must be bulletproof

**Research flag:** Async Elixir telemetry pattern (Christian Alexander 2024) and cursor-based pagination with Ecto (Appunite) provide solid references. The `HandlerGuardian` supervised reattachment pattern is not widely documented but is necessary — design this carefully.

---

### Phase 6: Public API Integration + Telemetry Handler

**Rationale:** This phase wires all prior layers into the `converse/2` public facade and implements the TelemetryHandler automatic integration mode. It comes last because it orchestrates every prior component and should not be written until each component's interface is stable.

**Delivers:**
- `PhoenixAIStore.converse/2` — full pipeline: load → memory → guardrails → AI call → save → cost → event log → return
- `PhoenixAIStore.TelemetryHandler` — attaches to `[:phoenix_ai, ...]` events; defensive handler body; supervised reattachment via `HandlerGuardian`
- Complete `[:phoenix_ai_store, ...]` telemetry event emission across all components
- Integration tests covering the full `converse/2` path with InMemory and Ecto adapters

**Implements features:** `converse/2` public API, telemetry handler (auto-capture mode), full telemetry event emission

**Avoids:** TelemetryHandler silent detachment (Pitfall 6), anonymous function handler performance penalty

**Research flag:** Needs careful integration testing with PhoenixAI's telemetry event shapes. Event metadata keys for `[:phoenix_ai, :chat, :stop]` should be validated against PhoenixAI v0.1 source before writing pattern matches. Use `Map.get/3` with defaults throughout, never direct pattern matching on metadata.

---

### Phase 7: Polish, Docs, and CI

**Rationale:** Library polish and documentation are first-class deliverables for a hex library. ExDoc, Dialyzer, Credo, and a CI matrix that verifies optional deps are truly optional.

**Delivers:**
- Complete `@moduledoc` and `@doc` for all public modules and callbacks
- Full `@spec` coverage; `mix dialyzer` passing in CI
- `mix credo --strict` passing in CI
- CI matrix job: `mix compile --no-optional-deps --warnings-as-errors` (verifies optional Ecto guard works for real)
- CI matrix job: test suite without Ecto in deps (separate mix env)
- `CHANGELOG.md` and hex package metadata
- Usage guide and integration examples in ExDoc

**Research flag:** Standard patterns. No deeper research needed.

---

### Phase Ordering Rationale

- **Phase 1 must come first.** The Adapter behaviour callback signatures are the most load-bearing decision in the entire library. Every subsequent phase implements or depends on them. The optional-Ecto compile-time pattern must be correct from the start; retrofitting it after Phase 2+ code exists is risky.
- **Phase 2 (Memory) before Phase 3 (Guardrails).** Memory strategies are stateless transforms on the message list; they have no dependency on Guardrails or Cost. Guardrails need to know token counts (from Phase 2's TokenTruncation strategy) for the TokenBudget policy. Building memory first keeps the dependency direction clean.
- **Phase 3 (Guardrails) before Phase 4 (Cost).** The CostBudget policy depends on CostTracker, but TokenBudget and ToolPolicy do not. Delivering a working guardrails layer in Phase 3 without the cost dep keeps Phase 3 shippable independently, and avoids holding up the policy infrastructure behind the PhoenixAI Usage struct blocker.
- **Phase 4 (Cost) is the most uncertain phase** due to the PhoenixAI Usage struct upstream dependency. Flag for validation before detailed planning. If blocked, a shim approach can unblock Phase 4 progress while waiting for upstream.
- **Phase 5 (Event Log) is not on the critical path** for a functional `converse/2` but is required for compliance. It can be built in parallel with Phase 3 or 4 if team capacity allows (it only depends on Phase 1 Ecto schemas).
- **Phase 6 (Integration) comes last** because it composes all layers. Writing `converse/2` before each component's interface is stable leads to rework.

---

### Research Flags

**Phases needing deeper research during planning:**

- **Phase 2 (Memory):** Anthropic token counting dispatch — validate the Anthropic Token Count API endpoint behavior and whether a local approximation is sufficiently accurate before committing to the token counting interface design.
- **Phase 4 (Cost Tracking):** PhoenixAI Usage struct normalization — confirm upstream status before detailed planning. If the normalized struct is not available, design the shim approach before writing any cost calculation code.
- **Phase 5 (Event Log):** `HandlerGuardian` supervised reattachment — this pattern is referenced in the Elixir Forum but has no canonical reference implementation. Design review recommended before implementation.
- **Phase 6 (Integration):** PhoenixAI telemetry event metadata shapes — validate against PhoenixAI v0.1 source to confirm all `[:phoenix_ai, ...]` event metadata keys before writing the TelemetryHandler.

**Phases with standard patterns (skip research-phase):**

- **Phase 1 (Storage Foundation):** Oban optional Ecto pattern, ETS GenServer ownership, Elixir Adapter Pattern — all well-documented with canonical reference implementations.
- **Phase 3 (Guardrails):** Policy behaviour pattern is standard; TokenBudget and ToolPolicy have clear models in AgentSessionManager.
- **Phase 7 (Polish):** ExDoc, Dialyzer, Credo — standard hex library tooling with no novel decisions.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against Hex.pm; all patterns verified against official Elixir docs and production libraries (Oban, Dataloader, PhoenixAI). No speculative choices. |
| Features | HIGH (table stakes) / MEDIUM (differentiators) | Table stakes verified against multiple official sources (LangChain docs, Oban hexdocs, Instructor hexdocs). Differentiator design (policy stacking API, cost budget guardrail) is based on AgentSessionManager analysis (MEDIUM — docs may not reflect full implementation) and Amazon Bedrock taxonomy (MEDIUM — patterns are transferable but not Elixir-specific). |
| Architecture | HIGH | Adapter pattern, optional Ecto, GenServer ETS ownership, NimbleOptions schema, telemetry span convention — all verified against official sources and confirmed production libraries. Async telemetry GenServer batch pattern is MEDIUM (single high-quality source, consistent with official telemetry docs). |
| Pitfalls | HIGH | Critical pitfalls 1-5 verified against official Elixir language source (José Valim GitHub issue), official ETS docs, official telemetry docs, and Elixir Forum community consensus. Token counting mismatch (MEDIUM — verified against Anthropic API behavior via third-party blog, consistent with known Anthropic tokenizer opacity). |

**Overall confidence: HIGH**

The research corpus is primarily official documentation, production library source (Oban, Instructor, PhoenixAI), and core language team confirmations. Speculative findings are flagged and isolated to differentiator feature design and the Anthropic token counting gap.

---

### Gaps to Address

- **PhoenixAI normalized Usage struct (blocker):** Cost tracking cannot be finalized until PhoenixAI ships a `Usage` struct that normalizes provider responses. Before planning Phase 4 in detail, confirm whether this is available or has a committed timeline. If unavailable, scope Phase 4 as "cost tracking with normalization shim" with a clear upgrade path documented.

- **Anthropic token counting accuracy:** The exact accuracy of `chars / 3.5` as a Claude token count approximation needs validation. This affects when memory strategy truncation fires for Anthropic-backed conversations. During Phase 2 planning, prototype the approximation against a set of real Claude conversations to measure error margin before committing to the threshold design.

- **HandlerGuardian pattern:** No canonical reference implementation exists for a supervised process that polls and reattaches detached telemetry handlers. During Phase 5 planning, design and review this component explicitly — the pattern is well-understood conceptually but the implementation details (polling interval, reattach idempotency, handler identity tracking) need worked examples.

- **InMemory adapter write semantics under concurrency:** For v1, ETS direct insert (last-write-wins) is documented as acceptable. However, if the InMemory adapter is used in production (not just dev/test), concurrent writes to the same conversation could lose messages. During Phase 1 planning, decide whether to accept this limitation with documentation or implement a per-conversation write serialization using a process dictionary / Registry-registered per-conversation GenServer. Document the chosen approach explicitly.

- **`mix phoenix_ai_store.gen.migration` idempotency:** The Mix task must check for existing migration files before generating to prevent duplicate-content migrations. Validate during Phase 1 that the idempotency check is in the acceptance criteria.

---

## Sources

### Primary (HIGH confidence)

- NimbleOptions v1.1.1 (Hex.pm) — config schema validation patterns
- Telemetry v1.4.1 (Hex.pm + hexdocs) — span event convention, attach/detach behavior
- Ecto v3.13.5 / ecto_sql v3.13.5 (Hex.pm) — schema and adapter patterns
- PhoenixAI v0.1.0 (hexdocs.pm/phoenix_ai) — `manage_history: false` integration point, telemetry events, Usage struct status
- Oban v2.21.1 (hexdocs.pm/oban) — optional Ecto pattern, migration generator, repo injection
- Instructor Elixir v0.0.4 (hexdocs.pm/instructor) — behaviour-first adapter design
- Elixir Adapter Pattern — Aaron Renner (2023) — behaviour/adapter implementation walkthrough
- `elixir-lang/elixir#8970` (GitHub, José Valim) — `Code.ensure_loaded?` wrapping `use` macro compile-time limitation
- Elixir Forum: Optional dependency guide — `Code.ensure_loaded?` community consensus
- Elixir Forum: Detached telemetry handlers — silent detachment behavior confirmation
- LangChain Python memory docs (python.langchain.com) — memory strategy taxonomy
- LangMem conceptual guide (langchain-ai.github.io/langmem) — cross-conversation memory types
- Hammer v7.3.0 (Hex.pm) — rate limiting backend options
- Tiktoken v0.4.2 (Hex.pm) — BPE token counting
- Hashrocket TIL: ETS table deleted when owning process dies — ETS owner death behavior

### Secondary (MEDIUM confidence)

- AgentSessionManager v0.8.0 (GitHub README) — event model, policy stacking patterns (documentation may not reflect full implementation)
- Amazon Bedrock Guardrails (aws.amazon.com) — guardrail taxonomy (commercial, patterns are transferable)
- Counting Claude Tokens Without a Tokenizer (GoPenAI blog) — Anthropic tokenizer opacity and approximation strategies
- AI Price Index: LLM Costs Dropped 300x (tokencost.app) — pricing table staleness justification
- Async Elixir Telemetry — Christian Alexander (2024) — async handler GenServer batch pattern
- Appunite: Cursor-based pagination with Ecto — `(inserted_at, id)` composite cursor pattern
- ETS vs GenServer State (Elixir Forum) — ETS-as-owned-table concurrent access pattern

### Tertiary (LOW confidence)

- AI Audit Trail standards (swept.ai) — immutable log compliance requirements (single vendor source; consistent with EU Annex 11 patterns)
- Pinned messages / never-evict patterns (dev.to community post) — community consensus on protecting system messages; verified by multiple posts agreeing on pattern
- LLM Chat History Summarization best practices (mem0.ai blog) — summarization trigger threshold guidance; needs real usage data to validate thresholds

---

*Research completed: 2026-04-03*
*Ready for roadmap: yes*
