# Phase 10: Streaming Support — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Approach:** Inline Minimal (~25 LOC production code)

## Summary

Add `on_chunk` callback and `to` PID options to `converse/3`, routing to `AI.stream/2` instead of `AI.chat/2` when streaming options are present. The rest of the pipeline (load, save, memory, guardrails, cost, events) remains unchanged.

## Architecture

### Approach Selected: Inline Minimal

No new modules, no new abstractions. A `cond` in `call_ai/2` and a conflict check in `validate_context/1`.

**Alternatives considered:**
- **Helper Module** (`StreamRouter`) — Over-engineering for ~10 lines of routing logic
- **Behaviour-based** (`AIClient` + `ChatClient` + `StreamClient`) — Absurdly over-engineered for the scope

## Changes

### 1. `lib/phoenix_ai/store.ex` — converse/3

**Context map** (lines 585-600): Add 3 fields:

```elixir
on_chunk: Keyword.get(opts, :on_chunk),
to: Keyword.get(opts, :to),
streaming: not is_nil(Keyword.get(opts, :on_chunk)) or not is_nil(Keyword.get(opts, :to))
```

`streaming` is a derived boolean — avoids recalculating in multiple places.

**Telemetry span** (line 603): Change `{result, %{}}` to:

```elixir
{result, %{streaming: context.streaming}}
```

**@doc**: Add `:on_chunk` and `:to` to the Options section with examples.

### 2. `lib/phoenix_ai/store/converse_pipeline.ex`

**`validate_context/1`** (lines 50-56): Add conflict check:

```elixir
is_function(context[:on_chunk]) and is_pid(context[:to]) ->
  {:error, :conflicting_streaming_options}
```

This runs before any pipeline step — fail-fast, consistent with existing `:provider`/`:model` validation.

**`call_ai/2`** (lines 149-155): Replace with conditional routing:

```elixir
defp call_ai(messages, context) do
  base_opts =
    [provider: context.provider, model: context.model, api_key: context.api_key]
    |> maybe_add_tools(context[:tools])

  cond do
    is_function(context[:on_chunk]) ->
      AI.stream(messages, Keyword.put(base_opts, :on_chunk, context.on_chunk))

    is_pid(context[:to]) ->
      AI.stream(messages, Keyword.put(base_opts, :to, context.to))

    true ->
      AI.chat(messages, base_opts)
  end
end
```

**`maybe_log_event/3`** (line 229): Include streaming flag in event metadata:

```elixir
EventLog.log(:response_received, %{streaming: context[:streaming] || false}, event_opts)
```

### 3. No Other Changes

- Steps 1-4 (load conversation, save user message, prepare messages, check guardrails) — **unchanged**
- Step 6 (save assistant message) — **unchanged** — `AI.stream/2` returns `{:ok, %Response{}}` same shape as `AI.chat/2`
- Step 7 (post-process: cost, events, facts) — only `maybe_log_event` adds metadata, rest **unchanged**

## Testing Strategy

Use `TestProvider` (already has `stream/3` with `String.graphemes` simulation) inside `converse_integration_test.exs` for consistency with existing converse tests.

### Test Cases

| # | Scenario | Assertion |
|---|----------|-----------|
| 1 | `on_chunk` callback | Callback receives `%StreamChunk{}` during streaming, `{:ok, response}` returned |
| 2 | `to` PID | Process receives `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages |
| 3 | No streaming opts | Existing tests pass unchanged — backward compatible |
| 4 | Both `on_chunk` + `to` | Returns `{:error, :conflicting_streaming_options}` before pipeline runs |
| 5 | Telemetry metadata | Span stop event includes `%{streaming: true}` |
| 6 | Event log metadata | `:response_received` event includes `%{streaming: true}` in metadata |

### Test Infrastructure

- `TestProvider.stream/3` already exists — simulates streaming by splitting content into graphemes
- `TestProvider.put_responses/2` — same setup as existing converse tests
- `:telemetry.attach/4` + `assert_received` for telemetry verification
- No Mox needed — TestProvider provides sufficient isolation

## Data Flow

```
converse/3 (store.ex)
  |— Build context map (+ on_chunk, to, streaming fields)
  |— :telemetry.span with streaming metadata
  |
  v
ConversePipeline.run/3
  |— validate_context/1  <-- NEW: conflict check (on_chunk + to = error)
  |— Step 1: load_conversation
  |— Step 2: save_user_message
  |— Step 3: prepare_messages (memory + system prompt)
  |— Step 4: check_guardrails
  |— Step 5: call_ai/2    <-- CHANGED: cond routing to AI.stream or AI.chat
  |— Step 6: save_assistant_message (unchanged — Response shape is identical)
  |— Step 7: post_process
  |    |— maybe_record_cost (unchanged)
  |    |— maybe_log_event   <-- CHANGED: includes streaming in metadata
  |    |— maybe_extract_facts (unchanged)
  v
{:ok, %Response{}}  (identical return regardless of streaming mode)
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Guard clauses, not NimbleOptions | `converse/3` uses `Keyword.get/3` — consistency over correctness theater |
| Conflict check in `validate_context/1` | Fail-fast before pipeline runs, alongside existing :provider/:model checks |
| `{:error, :conflicting_streaming_options}` | Explicit error, no silent precedence between on_chunk and to |
| Derived `streaming` boolean in context | Avoids recalculating `not is_nil(on_chunk) or not is_nil(to)` in multiple places |
| TestProvider, not Mox | Existing converse tests use TestProvider; TestProvider.stream/3 already exists |
| Inline minimal approach | YAGNI — extract to module only if future streaming modes emerge |

## Out of Scope

- Partial message persistence during streaming (save only final response)
- Streaming-specific guardrails (check before, not during)
- Streaming-specific memory pipeline changes
- New StreamChunk fields (PhoenixAI owns this)
- Provider-level changes (already complete)
- Async/non-blocking converse mode (different feature)

---

*Phase: 10-streaming-support*
*Design approved: 2026-04-05*
