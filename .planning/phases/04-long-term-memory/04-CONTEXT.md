# Phase 4: Long-Term Memory - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver cross-conversation long-term memory: key-value fact extraction and storage per user, AI-generated profile summaries, and automatic injection of facts + profile as pinned system messages before memory strategies run. Extraction is configurable (manual, per-turn, on-close) with sync/async modes. The Extractor behaviour allows custom extraction logic.

</domain>

<decisions>
## Implementation Decisions

### Fact Storage Model
- **D-01:** Facts use a **key-value simple model**: `{user_id, key, value}` — no namespaces, no versioning. Key is a string, value is a string. Developer converts types when needed.
- **D-02:** Facts are stored via **new callbacks on the existing Adapter behaviour** — `save_fact/2`, `get_facts/2`, `delete_fact/2`, `list_facts/2`. Both InMemory (ETS) and Ecto adapters get implementations. Follows the same pattern as conversation callbacks.
- **D-03:** Save is **upsert semantic** — if a fact with the same `{user_id, key}` already exists, the value is silently overwritten. Matches `save_conversation` pattern (D-09 from Phase 1).
- **D-04:** **Configurable max facts per user** via NimbleOptions — protects against runaway extraction. Default TBD (e.g., 100). When limit is reached, save_fact returns `{:error, :limit_exceeded}`.

### Extraction Trigger & Timing
- **D-05:** Extraction trigger is **configurable with 3 modes**:
  - `:manual` (default) — developer calls `extract_facts/2` explicitly. Zero cost unless invoked.
  - `:per_turn` — automatic after each conversation turn in the `converse/2` pipeline.
  - `:on_close` — automatic when conversation is finalized.
  Configurable via NimbleOptions: `extraction_trigger: :manual | :per_turn | :on_close`. Can be enabled/disabled globally.
- **D-06:** Extraction execution is **configurable sync or async** — `extraction_mode: :sync | :async`. Sync blocks until facts are extracted (predictable). Async dispatches via Task.Supervisor and returns immediately (performant, but facts may not be ready for next turn).
- **D-07:** Extraction scope is **incremental** — only processes messages since last extraction. A cursor (last extracted message ID or timestamp) is tracked per conversation. Avoids re-extracting known facts and saves tokens on long conversations.

### Profile Summary
- **D-08:** Profile is a **hybrid model** — text-free summary (primary, injected into AI calls) + structured metadata (tags, expertise_level, etc. — queryable). Stored per user.
- **D-09:** Profile refinement uses **AI with current profile + new facts** — the prompt includes the existing profile text and recently extracted facts. AI updates the profile incorporating new information rather than replacing blindly.
- **D-10:** Profile update is a **separate operation** from fact extraction — `update_profile/2` is its own API call. Developer controls frequency independently (e.g., extract facts every turn, update profile every 10 conversations).

### Context Injection
- **D-11:** Facts + profile are injected **before memory strategies run**, as **pinned system messages** — leverages the pinned mechanism from Phase 3. Memory strategies see them but never evict them.
- **D-12:** Injection format: **one system message with all facts** (formatted as key-value list) + **one system message with profile summary**. Two messages total, both pinned. Minimizes token overhead.
- **D-13:** Injection is **opt-in via config** — `inject_long_term_memory: true` in config or as option in `apply_memory/3`. Default: `false`. No surprises for developers who don't use LTM.

### Extractor Behaviour
- **D-14:** Default extractor calls AI with a prompt that includes the new messages and asks for key-value facts in a structured format. Developer can replace via `PhoenixAI.Store.LongTermMemory.Extractor` behaviour.

### Claude's Discretion
- Exact Adapter callback signatures for facts (return types, option schemas)
- Fact struct field names and types beyond {user_id, key, value}
- Profile struct internal representation
- Extraction and profile update prompt templates
- Default max_facts_per_user value
- How the cursor for incremental extraction is stored (field on conversation vs separate tracking)
- Task.Supervisor configuration for async mode
- Ecto migration additions for facts and profiles tables

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (Phases 1 & 3)
- `lib/phoenix_ai/store/adapter.ex` — Adapter behaviour (new fact callbacks will be added here)
- `lib/phoenix_ai/store/adapters/ets.ex` — ETS adapter (needs fact storage implementation)
- `lib/phoenix_ai/store/adapters/ecto.ex` — Ecto adapter (needs fact storage implementation)
- `lib/phoenix_ai/store/message.ex` — Message struct with `pinned` field (injection creates pinned messages)
- `lib/phoenix_ai/store/memory/pipeline.ex` — Pipeline orchestrator (injection happens before this runs)
- `lib/phoenix_ai/store/memory/strategy.ex` — Strategy behaviour (facts/profile enter as pinned messages before strategies)
- `lib/phoenix_ai/store.ex` — Public API facade (new LTM functions added here)
- `lib/phoenix_ai/store/config.ex` — NimbleOptions config (new LTM options added here)
- `lib/phoenix_ai/store/memory/strategies/summarization.ex` — Summarization strategy (pattern for AI-calling operations)

### PhoenixAI Peer Dependency
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/agent.ex` — Agent with `manage_history: false` + `messages:` pattern
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/message.ex` — PhoenixAI.Message struct

### Planning
- `.planning/REQUIREMENTS.md` — LTM-01 through LTM-05 requirements
- `.planning/phases/01-storage-foundation/01-CONTEXT.md` — Phase 1 decisions (Adapter pattern, upsert semantic, UUID v7)
- `.planning/phases/03-memory-strategies/03-CONTEXT.md` — Phase 3 decisions (Strategy behaviour, pinned messages, Pipeline)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Store.Adapter` behaviour — pattern for adding new callbacks (save_fact, get_facts, etc.)
- `PhoenixAI.Store.Memory.Strategies.Summarization` — pattern for strategy that calls AI synchronously (reuse for extraction and profile update)
- `PhoenixAI.Store.Memory.Pipeline` — orchestrator that applies strategies in order (injection point: before pipeline runs)
- `PhoenixAI.Store.Message` struct with `pinned: true` — ready-made mechanism for "never evict" messages
- `PhoenixAI.Store.Config` with NimbleOptions — extend with LTM-specific options

### Established Patterns
- Behaviours with `@callback` for all pluggable components (Adapter, Strategy, TokenCounter)
- `{:ok, result} | {:error, term}` return types consistently
- NimbleOptions validation at init time, not call time
- Upsert semantic for save operations (conversations, now facts)
- Supervised GenServer for ETS table ownership

### Integration Points
- `PhoenixAI.Store.apply_memory/3` — the facade function where injection happens (add facts + profile before calling Pipeline)
- `PhoenixAI.Store.Adapter` — extend with fact CRUD callbacks
- `Mix.Tasks.PhoenixAiStore.Gen.Migration` — extend migration template with facts and profiles tables
- Telemetry events — new spans for `[:phoenix_ai_store, :extract_facts, ...]` and `[:phoenix_ai_store, :update_profile, ...]`

</code_context>

<specifics>
## Specific Ideas

- Facts as pinned system messages: format like "User context:\n- preferred_language: pt-BR\n- expertise: Elixir\n- timezone: America/Sao_Paulo"
- Profile as separate pinned system message: the hybrid text + metadata, with the text portion injected
- Incremental extraction cursor: track `last_extracted_message_id` per conversation to know where to resume
- The Summarization strategy from Phase 3 is a good template for AI-calling patterns — reuse the provider/model config approach (use cheap model for extraction, expensive for conversation)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-long-term-memory*
*Context gathered: 2026-04-04*
