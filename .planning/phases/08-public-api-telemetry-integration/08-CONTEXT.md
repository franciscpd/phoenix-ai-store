# Phase 8: Public API & Telemetry Integration - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire everything together: `converse/2` as the single-function pipeline entry point (load → memory → guardrails → AI call → save → cost → event log → return), `Store.track/1` as ergonomic explicit event capture, and `TelemetryHandler` + `HandlerGuardian` for automatic event capture from PhoenixAI telemetry events.

</domain>

<decisions>
## Implementation Decisions

### converse/2 Pipeline
- **D-01:** `converse/2` is a new function in `PhoenixAI.Store` that runs the full pipeline as a **dedicated orchestration** — resolves adapter once, passes context through all steps. Does NOT compose existing facade functions (avoids 7+ redundant GenServer calls).
- **D-02:** The AI call uses `AI.chat/2` directly (not Agent GenServer). The store resolves `provider`, `model`, `api_key` from config or opts. Stateless — no Agent PID required.
- **D-03:** Pipeline steps in order: (1) load conversation, (2) apply memory strategy, (3) run guardrail pre-flight, (4) call `AI.chat/2`, (5) save new messages (user + assistant), (6) record cost, (7) log events, (8) return response. Each step has clear error handling — failures at steps 1-3 abort, step 4 errors return the AI error, steps 5-7 are fire-and-forget (never block the response).
- **D-04:** Signature: `converse(conversation_id, message, opts)` where `message` is a string (user message content). Returns `{:ok, %PhoenixAI.Response{}} | {:error, term()}`. Opts include `:store`, `:provider`, `:model`, `:api_key`, `:system` (system prompt), `:tools`, `:memory_pipeline`, `:guardrails`, `:user_id`.

### Store.track/1
- **D-05:** `track/1` is a simplified wrapper around `log_event/2`. Accepts a map: `%{type: atom, data: map, conversation_id: string | nil, user_id: string | nil, store: atom}`. Builds an `%Event{}` and delegates to EventLog.
- **D-06:** `log_event/2` remains public for users who want full control over the Event struct. `track/1` is the recommended ergonomic API.

### TelemetryHandler
- **D-07:** `PhoenixAI.Store.TelemetryHandler` is a **plain module** with handler functions (not a GenServer). Attaches to `[:phoenix_ai, :chat, :stop]`, `[:phoenix_ai, :tool_call, :stop]`, and `[:phoenix_ai, :stream, :stop]` via `:telemetry.attach_many/4`.
- **D-08:** Handler functions are **module-qualified captures** (`&TelemetryHandler.handle_chat_stop/4`) to avoid silent detachment on anonymous function garbage collection.
- **D-09:** Handler persistence is **async fire-and-forget** via `Task.start/1` to avoid blocking the PhoenixAI caller process.
- **D-10:** Conversation context (conversation_id, user_id) is read from **process metadata** (`Logger.metadata()` or process dictionary). The developer sets `Logger.metadata(phoenix_ai_store: %{conversation_id: id, user_id: uid})` before calling AI. The handler reads this to associate events with conversations. If not set, events are logged without conversation context (still useful for global metrics).

### HandlerGuardian
- **D-11:** `PhoenixAI.Store.HandlerGuardian` is a supervised **GenServer** that periodically polls `:telemetry.list_handlers/1` to verify TelemetryHandler is still attached. If detached, reattaches within 30 seconds.
- **D-12:** Polling interval: 30 seconds (configurable). Uses `Process.send_after/3` for the poll loop. On init, attaches handlers immediately.
- **D-13:** Idempotent reattachment — checks handler ID before attaching to avoid duplicates. Handler ID is a deterministic atom (e.g., `:phoenix_ai_store_telemetry_handler`).
- **D-14:** Started as a child of the user's supervision tree: `{PhoenixAI.Store.HandlerGuardian, store: :my_store}`. Not started automatically by `Store.start_link/1` — opt-in.

### Telemetry Conventions
- **D-15:** All Store operations already emit `[:phoenix_ai_store, :*, :start|:stop|:exception]` spans. Phase 8 verifies completeness and ensures naming follows PhoenixAI conventions.
- **D-16:** The `converse/2` pipeline emits a top-level `[:phoenix_ai_store, :converse, :start|:stop|:exception]` span wrapping the entire pipeline, in addition to individual step telemetry.

### Claude's Discretion
- Exact opts mapping from `converse/2` opts to `AI.chat/2` opts
- Error handling details for each pipeline step
- TelemetryHandler handler function signatures
- HandlerGuardian GenServer state structure
- Whether `converse/2` should extract facts (LTM) automatically
- Process metadata key name and structure

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (Phases 1-7)
- `lib/phoenix_ai/store.ex` — Facade with all existing functions (~630 lines)
- `lib/phoenix_ai/store/config.ex` — NimbleOptions schema
- `lib/phoenix_ai/store/event_log.ex` — EventLog orchestrator
- `lib/phoenix_ai/store/event_log/event.ex` — Event struct
- `lib/phoenix_ai/store/cost_tracking.ex` — CostTracking.record/3
- `lib/phoenix_ai/store/memory/pipeline.ex` — Memory pipeline
- `lib/phoenix_ai/store/guardrails/token_budget.ex` — TokenBudget policy pattern
- `lib/phoenix_ai/store/guardrails/cost_budget.ex` — CostBudget policy pattern
- `lib/phoenix_ai/store/long_term_memory.ex` — LTM orchestrator (extract_facts pattern)

### PhoenixAI Peer Dependency (v0.3.1)
- `deps/phoenix_ai/lib/ai.ex` — `AI.chat/2`, telemetry events emitted
- `deps/phoenix_ai/lib/phoenix_ai/agent.ex` — Agent GenServer (for reference, not used)
- `deps/phoenix_ai/lib/phoenix_ai/response.ex` — Response struct (provider, model, usage)
- `deps/phoenix_ai/lib/phoenix_ai/usage.ex` — Usage struct
- `deps/phoenix_ai/lib/phoenix_ai/tool_loop.ex` — Tool call telemetry events

### Planning
- `.planning/REQUIREMENTS.md` — INTG-01, INTG-02, INTG-03, INTG-04, INTG-06

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- All facade functions in store.ex — compose into converse/2 pipeline
- `resolve_adapter/1` — adapter resolution pattern (reuse in converse/2 single-resolve)
- `maybe_log_event/3` — fire-and-forget pattern (reuse in TelemetryHandler)
- `EventLog.log/3` — event persistence (used by both track/1 and TelemetryHandler)
- `CostTracking.record/3` — cost recording (used by converse/2 and TelemetryHandler)
- Existing telemetry spans in all facade functions

### Established Patterns
- All opts use `:store` key for store instance resolution
- Fire-and-forget: try/rescue, Logger.warning on failure
- NimbleOptions for config validation
- Telemetry spans via `:telemetry.span/3`
- Adapter sub-behaviours with function_exported? checks

### Integration Points
- `converse/2` — new top-level function composing all subsystems
- `track/1` — new ergonomic event capture API
- `TelemetryHandler` — attaches to PhoenixAI events, persists via existing Store functions
- `HandlerGuardian` — supervised GenServer, started by user

</code_context>

<specifics>
## Specific Ideas

- `converse/2` should be the "happy path" function — load, think, save, track. For advanced users who need step-by-step control, the individual facade functions remain available.
- The TelemetryHandler captures the 3 remaining event types from Phase 7 (response_received, tool_called, tool_result) that weren't inline.
- HandlerGuardian should log a warning when reattaching: "TelemetryHandler was detached, reattaching..."

</specifics>

<deferred>
## Deferred Ideas

- Streaming support in converse/2 (AI.stream vs AI.chat) — future version
- Automatic LTM fact extraction in converse/2 pipeline — can be added later as a pipeline step
- Distributed HandlerGuardian across cluster nodes — future version

</deferred>

---

*Phase: 08-public-api-telemetry-integration*
*Context gathered: 2026-04-05*
