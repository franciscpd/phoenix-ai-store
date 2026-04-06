# Phase 10: Streaming Support - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Add streaming callback support to `converse/3` so consumers can receive AI response tokens in real-time via `on_chunk` callback or `to` PID options, routing to `AI.stream/2` instead of `AI.chat/2` when streaming options are present. Pipeline steps 1-4 (load, save user msg, prepare, guardrails) and 6-7 (save assistant msg, post-process) are unchanged. Only `call_ai/2` gets conditional routing logic.

</domain>

<decisions>
## Implementation Decisions

### Option Validation
- **D-01:** Use guard clauses (`is_function/1`, `is_pid/1`) in `call_ai/2` for routing — consistent with the existing `converse/3` pattern that uses `Keyword.get/3` without NimbleOptions
- **D-02:** Return `{:error, :conflicting_streaming_options}` when both `on_chunk` and `to` are passed — force the user to choose one mode, no silent precedence

### Streaming Routing
- **D-03:** Add `on_chunk` and `to` to the context map in `store.ex` converse/3 via `Keyword.get(opts, :on_chunk)` and `Keyword.get(opts, :to)`
- **D-04:** In `call_ai/2`, check `is_function(context[:on_chunk])` → `AI.stream/2` with `:on_chunk` opt, else check `is_pid(context[:to])` → `AI.stream/2` with `:to` opt, else `AI.chat/2`
- **D-05:** `AI.stream/2` returns `{:ok, %Response{}}` after stream completes — same shape as `AI.chat/2`, so pipeline steps 6-7 need zero changes

### Telemetry & Event Log
- **D-06:** Add `streaming: true/false` to the context map (derived from presence of `on_chunk` or `to`). The telemetry span in `store.ex` reads from context to include in span metadata
- **D-07:** `maybe_log_event/3` includes `streaming: true/false` in the EventLog metadata for the `:response_received` event

### Testing Strategy
- **D-08:** Use Mox to mock `AI.stream/2` — already used in the project. Mock returns `{:ok, %Response{}}` and simulates chunk dispatch via the `on_chunk` callback or `to` PID
- **D-09:** Three test scenarios: (1) on_chunk callback receives chunks, (2) to PID receives messages, (3) no streaming opts = identical to v0.1.0 behavior
- **D-10:** Test the conflict case — both on_chunk and to → `{:error, :conflicting_streaming_options}`

### Claude's Discretion
- Exact placement of the conflict check (early in converse/3 vs inside call_ai/2)
- Whether to add a `streaming?/1` helper or inline the check
- Test fixture structure for mock responses

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD (primary spec)
- `../phoenix-ai-store-streaming-support.md` — Full PRD: problem, goal, current architecture, required changes, behavior examples, test cases, scope boundaries

### Store implementation
- `lib/phoenix_ai/store.ex` §580-605 — `converse/3` function, context map construction, telemetry span
- `lib/phoenix_ai/store/converse_pipeline.ex` §148-155 — `call_ai/2` injection point (currently always `AI.chat/2`)
- `lib/phoenix_ai/store/converse_pipeline.ex` §219-231 — `maybe_log_event/3` for EventLog metadata

### PhoenixAI streaming (peer dep)
- PhoenixAI `AI.stream/2` — returns `{:ok, %Response{}}` on completion, supports `on_chunk` and `to` options
- PhoenixAI `StreamChunk` struct — the chunk type dispatched during streaming

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AI.stream/2` in PhoenixAI — complete streaming implementation with SSE parsing, chunk dispatch, response accumulation
- `StreamChunk` struct — already defined in PhoenixAI, no new structs needed
- `Mox` test infrastructure — already configured in project for mocking AI module

### Established Patterns
- `converse/3` context map pattern — all options extracted via `Keyword.get/3` into a flat map, passed through pipeline
- `call_ai/2` receives `(messages, context)` — the routing decision lives entirely here
- `maybe_*` pattern for optional features — `maybe_log_event`, `maybe_record_cost`, `maybe_extract_facts`
- Telemetry span wraps entire `converse/3` with metadata map

### Integration Points
- `store.ex:585-600` — context map construction (add `on_chunk`, `to`, `streaming` fields)
- `converse_pipeline.ex:149-155` — `call_ai/2` (add conditional routing)
- `converse_pipeline.ex:229` — `EventLog.log/3` call (add streaming metadata)
- `store.ex:581` — telemetry span metadata (add streaming flag)

</code_context>

<specifics>
## Specific Ideas

- PRD specifies exact `cond` structure for `call_ai/2` — follow it closely
- `AI.stream/2` callback options match PhoenixAI's `@stream_schema` — `on_chunk: fun/1`, `to: pid`
- Test pattern from PRD: use ETS table to collect chunks in on_chunk test, `assert_received` for to PID test

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-streaming-support*
*Context gathered: 2026-04-05*
