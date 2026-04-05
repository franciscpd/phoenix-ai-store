# Roadmap: PhoenixAI Store

## Overview

PhoenixAI Store is built in eight phases derived from its seven requirement categories. Phase 1 establishes the storage backbone — the Adapter behaviour, Conversation struct, InMemory and Ecto adapters, and the migration generator — because every subsequent phase reads or writes through this layer. Memory strategies come next (Phase 3) to unblock the partial `converse/2` path early. Long-term memory (Phase 4) extends the memory layer with cross-conversation facts and profile summaries. Guardrails (Phase 5) enforce pre-call policies, with cost budget enforcement deferred to Phase 6 where Cost Tracking provides the necessary CostRecord data. The Event Log (Phase 7) closes the compliance requirement. Phase 8 wires everything into the public `converse/2` facade and the TelemetryHandler automatic integration mode. Phases 2 through 8 each deliver a coherent, independently verifiable capability that can be tested against PhoenixAI before the next phase begins.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Storage Foundation** - Conversation struct, Adapter behaviour, InMemory + Ecto adapters, migration generator, NimbleOptions config
- [ ] **Phase 2: Storage Queries & Metadata** - Pagination, filtering, and metadata retrieval for conversations
- [ ] **Phase 3: Memory Strategies** - Sliding window, token-aware truncation, pinned messages, strategy composition, Agent integration
- [ ] **Phase 4: Long-Term Memory** - Cross-conversation facts extraction, user profile summary, automatic injection
- [ ] **Phase 5: Guardrails** - Policy behaviour, token budget, tool policy, content filter, jailbreak detection, pre-call enforcement
- [ ] **Phase 6: Cost Tracking** - Pricing tables, per-conversation and per-user cost accumulation, cost budget guardrail, Decimal arithmetic
- [ ] **Phase 7: Event Log** - Append-only Ecto-backed event log, redaction, cursor-based pagination
- [ ] **Phase 8: Public API & Telemetry Integration** - `converse/2` facade, TelemetryHandler, HandlerGuardian, full telemetry emission
- [ ] **Phase 9: Documentation, CI & Publication** - ExDoc documentation, GitHub Actions CI, hex.publish readiness, README, CHANGELOG, LICENSE

## Phase Details

### Phase 1: Storage Foundation
**Goal**: The core storage contract is in place — developers can persist and restore conversations using either the InMemory ETS adapter or the Ecto adapter, generate Ecto migrations, and configure the library with validated options
**Depends on**: Nothing (first phase)
**Requirements**: STOR-01, STOR-02, STOR-03, STOR-04, STOR-05, INTG-05
**Success Criteria** (what must be TRUE):
  1. A developer implementing the `PhoenixAIStore.Adapter` behaviour with all four callbacks (`save/1`, `load/1`, `list/1`, `delete/1`) can plug in a custom storage backend without modifying library code
  2. A developer using the Ecto adapter can persist and load a Conversation (with id, user_id, messages, metadata, timestamps) to Postgres or SQLite via their own Repo module
  3. A developer without Ecto in their deps can use the InMemory ETS adapter — the library compiles cleanly with `--no-optional-deps`
  4. Running `mix phoenix_ai_store.gen.migration` generates a migration file; running it a second time does not duplicate the file
  5. Calling `PhoenixAIStore.configure/1` with invalid options returns a clear NimbleOptions validation error at init time, not at call time
**Plans**: TBD

### Phase 2: Storage Queries & Metadata
**Goal**: Developers can query the conversation store — listing with pagination and filtering, and attaching arbitrary metadata to conversations
**Depends on**: Phase 1
**Requirements**: STOR-06, STOR-07
**Success Criteria** (what must be TRUE):
  1. A developer can call `list_conversations/1` with `user_id`, `tags`, and date range filters and receive paginated results
  2. A developer can attach and later retrieve custom metadata fields (tags, agent config, custom key-value pairs) on a Conversation without modifying the struct definition
**Plans**: TBD

### Phase 3: Memory Strategies
**Goal**: Developers can apply memory strategies to a conversation's message list before passing it to PhoenixAI, keeping conversations within context window limits while preserving pinned messages
**Depends on**: Phase 1
**Requirements**: MEM-01, MEM-02, MEM-03, MEM-04, MEM-05, MEM-06, MEM-07
**Success Criteria** (what must be TRUE):
  1. A developer can apply `SlidingWindow` to a conversation and receive the last N messages, with all pinned messages present regardless of position
  2. A developer can apply `TokenTruncation` with a model and provider specified and receive a message list that fits within the configured token budget, never under-counting (over-truncates slightly rather than sending too many tokens)
  3. A developer implementing the `PhoenixAIStore.Memory.Strategy` behaviour can plug in a custom strategy that composes with built-in strategies
  4. A developer can chain multiple strategies (`Pinned` + `SlidingWindow` + `Summarization`) and have them applied in declared order
  5. The output of any memory strategy can be passed directly to PhoenixAI Agent via `messages:` with `manage_history: false` and the Agent processes it without error
**Plans**: TBD

### Phase 4: Long-Term Memory
**Goal**: The system can extract and maintain cross-conversation user facts and profile summaries, automatically injecting them as context before each AI call
**Depends on**: Phase 1, Phase 3
**Requirements**: LTM-01, LTM-02, LTM-03, LTM-04, LTM-05
**Success Criteria** (what must be TRUE):
  1. After a conversation, the system extracts key-value facts (e.g., user preferences, personal data) and stores them persistently, accessible across future conversations for the same user
  2. A developer can manually add, update, or delete individual user facts via an explicit API call
  3. The system generates and updates a user profile summary using AI across multiple conversations; calling the update again refines the existing summary rather than replacing it blindly
  4. Before an AI call, long-term memory (facts and profile summary) is injected automatically as context without requiring the developer to manually construct the messages
  5. A developer implementing `PhoenixAIStore.LongTermMemory.Extractor` behaviour can replace the default extraction logic with a custom implementation
**Plans**: TBD

### Phase 5: Guardrails
**Goal**: Developers can define an ordered stack of policies that runs before each AI call — enforcing token budgets, tool allowlists/denylists, content filtering, and jailbreak/prompt injection detection — with violations surfaced as structured errors
**Depends on**: Phase 1, Phase 3
**Requirements**: GUARD-01, GUARD-03, GUARD-04, GUARD-05, GUARD-06, GUARD-07, GUARD-08, GUARD-09, GUARD-10
**Success Criteria** (what must be TRUE):
  1. A developer can configure a token budget per conversation or per user; when exceeded, the pre-call check returns `{:error, %PolicyViolation{}}` and the AI call is never made
  2. A developer can define a tool allowlist or denylist per conversation; a request using a disallowed tool is rejected before the API call with a structured `PolicyViolation` identifying the offending policy
  3. A developer can attach pre- and post-call content filtering hooks (user-provided functions); a hook returning `{:error, reason}` stops the request with a `PolicyViolation`
  4. A developer implementing the `PhoenixAIStore.Guardrails.Policy` behaviour can add a custom policy that participates in the stacked evaluation, with the first violation winning
  5. A message containing a known jailbreak or prompt injection pattern is detected by the built-in heuristics and returns a `PolicyViolation` before the AI call; a developer can replace the detection logic via the `JailbreakDetector` behaviour
**Plans**: TBD

### Phase 6: Cost Tracking
**Goal**: The system tracks and reports token consumption and dollar costs per conversation and per user, using configurable pricing tables and Decimal arithmetic, with a cost budget guardrail that blocks calls before they exceed limits
**Depends on**: Phase 1, Phase 5
**Requirements**: COST-01, COST-02, COST-03, COST-04, COST-05, COST-06, COST-07, COST-08, GUARD-02
**Success Criteria** (what must be TRUE):
  1. A developer can configure input and output token prices per provider/model in application config; the pricing table is never hardcoded in the library
  2. After a conversation turn, the system records a `CostRecord` (linked to the conversation) using `Decimal` arithmetic — querying the same record twice returns exactly the same value with no floating-point drift
  3. A developer can query total cost by conversation, by user, by provider, by model, and by time range in a single API call
  4. A `[:phoenix_ai_store, :cost, :recorded]` telemetry event is emitted after each cost record is written, enabling real-time cost monitoring
  5. A developer can configure a cost budget per conversation or per user; when exceeded, the pre-call guardrail returns `{:error, %PolicyViolation{}}` and the AI call is never made
  6. When PhoenixAI passes a raw (non-normalized) provider usage map, cost tracking returns `{:error, :usage_not_normalized}` rather than silently computing 0 cost
**Plans**: TBD

### Phase 7: Event Log
**Goal**: Every significant action in the system is durably recorded in an append-only event log with configurable redaction, enabling compliance audits and debugging
**Depends on**: Phase 1, Phase 6
**Requirements**: EVNT-01, EVNT-02, EVNT-03, EVNT-04, EVNT-05
**Success Criteria** (what must be TRUE):
  1. The system automatically records all core event types (`conversation_created`, `message_sent`, `response_received`, `tool_called`, `tool_result`, `policy_violation`, `cost_recorded`, `memory_trimmed`) without any extra developer code beyond enabling the event log
  2. No existing event record can be modified or deleted via any public API — write operations are insert-only
  3. A developer can paginate through events using cursor-based pagination on `(inserted_at, id)` and receive results in correct chronological order regardless of UUID ordering
  4. A developer can configure a `redact_fn` that strips or masks sensitive fields before any event is persisted; a conversation with PII in messages does not write raw PII to the event log when a redaction function is configured
**Plans**: TBD

### Phase 8: Public API & Telemetry Integration
**Goal**: The full `converse/2` pipeline is available as a single-function entry point, and developers can attach a supervised TelemetryHandler to capture events automatically without any explicit API calls
**Depends on**: Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 6, Phase 7
**Requirements**: INTG-01, INTG-02, INTG-03, INTG-04, INTG-06
**Success Criteria** (what must be TRUE):
  1. A developer can call `PhoenixAIStore.converse(agent, message, opts)` and have it transparently execute the full pipeline: load conversation → apply memory strategy → run guardrail pre-flight → call PhoenixAI → save updated conversation → record cost → append event log → return response
  2. A developer can call `Store.track/1` explicitly to record any event without going through `converse/2`, using the explicit API as the primary integration path
  3. A developer who adds `PhoenixAIStore.TelemetryHandler` to their supervision tree automatically captures all `[:phoenix_ai, ...]` events without writing any explicit tracking calls; if the handler crashes, a `HandlerGuardian` process reattaches it within 30 seconds
  4. Cost tracking works correctly with PhoenixAI's normalized `Usage` struct; passing a normalized struct produces an accurate `CostRecord` with no `:usage_not_normalized` errors
  5. Every Store operation emits a `[:phoenix_ai_store, ...]` telemetry event following PhoenixAI naming conventions, observable via `:telemetry.attach/4`
**Plans**: TBD

### Phase 9: Documentation, CI & Publication
**Goal**: The library is fully documented with ExDoc, has CI via GitHub Actions, and is ready to publish on Hex.pm — README, CHANGELOG, LICENSE, and `mix hex.publish` all work cleanly
**Depends on**: Phase 1, Phase 2, Phase 3, Phase 4, Phase 5, Phase 6, Phase 7, Phase 8
**Requirements**: DOC-01
**Success Criteria** (what must be TRUE):
  1. Running `mix docs` generates complete ExDoc documentation with no warnings — every public module has `@moduledoc`, every public function has `@doc` and `@spec`
  2. A "Getting Started" guide walks a new developer from `mix deps.get` to a working `converse/3` call in under 5 minutes, covering both ETS and Ecto adapters
  3. GitHub Actions CI runs `mix test`, `mix credo`, `mix dialyzer`, and `mix docs` on push — matrix of Elixir 1.15+ and OTP 26+
  4. `mix hex.publish --dry-run` succeeds with no errors — package metadata, description, licenses, and links are all valid
  5. README.md on Hex shows a clear value proposition, installation instructions, and quick usage example
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Storage Foundation | Done | Complete | 2026-03-29 |
| 2. Storage Queries & Metadata | Done | Complete | 2026-03-30 |
| 3. Memory Strategies | Done | Complete | 2026-03-31 |
| 4. Long-Term Memory | Done | Complete | 2026-04-01 |
| 5. Guardrails | Done | Complete | 2026-04-03 |
| 6. Cost Tracking | Done | Complete | 2026-04-04 |
| 7. Event Log | Done | Complete | 2026-04-05 |
| 8. Public API & Telemetry Integration | Done | Complete | 2026-04-05 |
| 9. Documentation, CI & Publication | 0/TBD | Not started | - |
