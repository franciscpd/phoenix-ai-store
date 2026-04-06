# Streaming Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `on_chunk` callback and `to` PID options to `converse/3`, routing to `AI.stream/2` when present.

**Architecture:** Inline minimal — a `cond` in `call_ai/2`, a conflict check in `validate_context/1`, 3 new fields in the context map. No new modules. `AI.stream/2` returns `{:ok, %Response{}}` same shape as `AI.chat/2`, so pipeline steps 6-7 need zero changes.

**Tech Stack:** Elixir, PhoenixAI (`AI.stream/2`, `StreamChunk`), TestProvider, `:telemetry`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/store.ex` | Modify | Add `on_chunk`, `to`, `streaming` to context map; update telemetry span metadata; update `@doc` |
| `lib/phoenix_ai/store/converse_pipeline.ex` | Modify | Add conflict check in `validate_context/1`; replace `call_ai/2` with conditional routing; add streaming metadata to event log |
| `test/phoenix_ai/store/converse_integration_test.exs` | Modify | Add streaming test cases (on_chunk, to PID, conflict, telemetry, event log) |

---

### Task 1: Conflict Validation — Test + Implementation

**Files:**
- Modify: `test/phoenix_ai/store/converse_integration_test.exs`
- Modify: `lib/phoenix_ai/store.ex:585-600` (context map)
- Modify: `lib/phoenix_ai/store/converse_pipeline.ex:50-56` (validate_context)

- [ ] **Step 1: Write the failing test for conflict detection**

Add this test inside the existing `describe "converse/3 via facade"` block at the end of `test/phoenix_ai/store/converse_integration_test.exs`:

```elixir
test "returns error when both on_chunk and to are given", %{store: store, conv_id: conv_id} do
  assert {:error, :conflicting_streaming_options} =
           Store.converse(conv_id, "Hello",
             provider: :test,
             model: "test-model",
             api_key: "test-key",
             store: store,
             on_chunk: fn _chunk -> :ok end,
             to: self()
           )
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: FAIL — the test will either pass with `{:ok, %Response{}}` (since `on_chunk` and `to` are currently ignored) or error because they aren't handled.

- [ ] **Step 3: Add on_chunk, to, streaming fields to context map in store.ex**

In `lib/phoenix_ai/store.ex`, find the context map inside `converse/3` (line ~585-600). Add three new fields after the `store` field:

```elixir
      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: Keyword.get(opts, :provider, converse_defaults[:provider]),
        model: Keyword.get(opts, :model, converse_defaults[:model]),
        api_key: Keyword.get(opts, :api_key, converse_defaults[:api_key]),
        system: Keyword.get(opts, :system, converse_defaults[:system]),
        tools: Keyword.get(opts, :tools),
        memory_pipeline: Keyword.get(opts, :memory_pipeline),
        guardrails: Keyword.get(opts, :guardrails),
        user_id: Keyword.get(opts, :user_id),
        extract_facts:
          Keyword.get(opts, :extract_facts, converse_defaults[:extract_facts] || false),
        store: Keyword.get(opts, :store, :phoenix_ai_store_default),
        on_chunk: Keyword.get(opts, :on_chunk),
        to: Keyword.get(opts, :to),
        streaming:
          not is_nil(Keyword.get(opts, :on_chunk)) or not is_nil(Keyword.get(opts, :to))
      }
```

- [ ] **Step 4: Add conflict check in validate_context/1**

In `lib/phoenix_ai/store/converse_pipeline.ex`, replace `validate_context/1` (lines 50-56):

```elixir
defp validate_context(context) do
  cond do
    is_nil(context[:provider]) -> {:error, {:missing_option, :provider}}
    is_nil(context[:model]) -> {:error, {:missing_option, :model}}
    is_function(context[:on_chunk]) and is_pid(context[:to]) ->
      {:error, :conflicting_streaming_options}
    true -> :ok
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: ALL PASS (including the new conflict test and all existing tests)

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store.ex lib/phoenix_ai/store/converse_pipeline.ex test/phoenix_ai/store/converse_integration_test.exs
git commit -m "feat(converse): add streaming options to context map and conflict validation"
```

---

### Task 2: on_chunk Streaming — Test + Routing

**Files:**
- Modify: `test/phoenix_ai/store/converse_integration_test.exs`
- Modify: `lib/phoenix_ai/store/converse_pipeline.ex:149-155` (call_ai)

- [ ] **Step 1: Write the failing test for on_chunk callback**

Add this test inside `describe "converse/3 via facade"`:

```elixir
test "dispatches chunks via on_chunk callback during streaming", %{
  store: store,
  conv_id: conv_id
} do
  set_responses([
    {:ok,
     %PhoenixAI.Response{
       content: "Hi!",
       usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 3, total_tokens: 8}
     }}
  ])

  test_pid = self()

  {:ok, response} =
    Store.converse(conv_id, "Hello",
      provider: :test,
      model: "test-model",
      api_key: "test-key",
      store: store,
      on_chunk: fn chunk -> send(test_pid, {:test_chunk, chunk}) end
    )

  assert response.content == "Hi!"

  # TestProvider.stream/3 splits "Hi!" into graphemes: "H", "i", "!"
  assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "H"}}
  assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "i"}}
  assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "!"}}
  # Final chunk with finish_reason
  assert_received {:test_chunk, %PhoenixAI.StreamChunk{finish_reason: "stop"}}
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs:"on_chunk" --seed 0 2>&1 | tail -20`

Expected: FAIL — `call_ai/2` currently always calls `AI.chat/2`, so no chunks are dispatched and `assert_received` fails.

- [ ] **Step 3: Replace call_ai/2 with conditional routing**

In `lib/phoenix_ai/store/converse_pipeline.ex`, replace `call_ai/2` (lines 148-155):

```elixir
# Step 5: Call AI (streaming or blocking)
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

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: ALL PASS (on_chunk test passes, existing tests still pass since the `true` branch preserves `AI.chat` behavior)

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/converse_pipeline.ex test/phoenix_ai/store/converse_integration_test.exs
git commit -m "feat(converse): route to AI.stream/2 when on_chunk callback provided"
```

---

### Task 3: to PID Streaming — Test

**Files:**
- Modify: `test/phoenix_ai/store/converse_integration_test.exs`

- [ ] **Step 1: Write the test for :to PID streaming**

Add this test inside `describe "converse/3 via facade"`:

```elixir
test "sends chunks to PID via :to option", %{store: store, conv_id: conv_id} do
  set_responses([
    {:ok,
     %PhoenixAI.Response{
       content: "Ok",
       usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
     }}
  ])

  {:ok, response} =
    Store.converse(conv_id, "Hello",
      provider: :test,
      model: "test-model",
      api_key: "test-key",
      store: store,
      to: self()
    )

  assert response.content == "Ok"

  # AI.stream/2 with :to wraps chunks in {:phoenix_ai, {:chunk, chunk}}
  assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "O"}}}
  assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "k"}}}
  assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{finish_reason: "stop"}}}
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: ALL PASS — the routing logic for `:to` was already implemented in Task 2's `call_ai/2` `cond`.

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/store/converse_integration_test.exs
git commit -m "test(converse): verify :to PID streaming dispatches chunks"
```

---

### Task 4: Telemetry Metadata — Test + Implementation

**Files:**
- Modify: `test/phoenix_ai/store/converse_integration_test.exs`
- Modify: `lib/phoenix_ai/store.ex:603` (telemetry span return)

- [ ] **Step 1: Write the failing test for telemetry metadata**

Add a new `describe "converse/3 streaming telemetry"` block in the test file:

```elixir
describe "converse/3 streaming telemetry" do
  test "includes streaming: true in telemetry span metadata when on_chunk given", %{
    store: store,
    conv_id: conv_id
  } do
    ref = make_ref()

    :telemetry.attach(
      "test-streaming-meta-#{inspect(ref)}",
      [:phoenix_ai_store, :converse, :stop],
      fn _event, _measurements, metadata, test_pid ->
        send(test_pid, {:telemetry_meta, metadata})
      end,
      self()
    )

    set_responses([
      {:ok,
       %PhoenixAI.Response{
         content: "Hi",
         usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
       }}
    ])

    {:ok, _} =
      Store.converse(conv_id, "Hello",
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        store: store,
        on_chunk: fn _chunk -> :ok end
      )

    assert_received {:telemetry_meta, metadata}
    assert metadata.streaming == true

    :telemetry.detach("test-streaming-meta-#{inspect(ref)}")
  end

  test "includes streaming: false in telemetry span metadata when no streaming opts", %{
    store: store,
    conv_id: conv_id
  } do
    ref = make_ref()

    :telemetry.attach(
      "test-no-streaming-meta-#{inspect(ref)}",
      [:phoenix_ai_store, :converse, :stop],
      fn _event, _measurements, metadata, test_pid ->
        send(test_pid, {:telemetry_meta, metadata})
      end,
      self()
    )

    set_responses([
      {:ok,
       %PhoenixAI.Response{
         content: "Hi",
         usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
       }}
    ])

    {:ok, _} =
      Store.converse(conv_id, "Hello",
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        store: store
      )

    assert_received {:telemetry_meta, metadata}
    assert metadata.streaming == false

    :telemetry.detach("test-no-streaming-meta-#{inspect(ref)}")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs:"streaming telemetry" --seed 0 2>&1 | tail -20`

Expected: FAIL — currently `{result, %{}}` returns empty metadata, so `metadata.streaming` doesn't exist.

- [ ] **Step 3: Update telemetry span return to include streaming metadata**

In `lib/phoenix_ai/store.ex`, find line 603 inside `converse/3`:

Replace:
```elixir
      {result, %{}}
```

With:
```elixir
      {result, %{streaming: context.streaming}}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store.ex test/phoenix_ai/store/converse_integration_test.exs
git commit -m "feat(converse): include streaming flag in telemetry span metadata"
```

---

### Task 5: Event Log Metadata — Test + Implementation

**Files:**
- Modify: `test/phoenix_ai/store/converse_integration_test.exs`
- Modify: `lib/phoenix_ai/store/converse_pipeline.ex:229` (maybe_log_event)

- [ ] **Step 1: Write the failing test for event log metadata**

Add a new `describe "converse/3 streaming event log"` block:

```elixir
describe "converse/3 streaming event log" do
  test "event log includes streaming: true in metadata when streaming", %{
    store: store,
    conv_id: conv_id
  } do
    set_responses([
      {:ok,
       %PhoenixAI.Response{
         content: "Streamed",
         usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 3, total_tokens: 8}
       }}
    ])

    {:ok, _} =
      Store.converse(conv_id, "Hello",
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        store: store,
        on_chunk: fn _chunk -> :ok end
      )

    # Allow async post-processing task to complete
    Process.sleep(100)

    {:ok, %{events: events}} = Store.list_events([], store: store)

    response_event =
      Enum.find(events, &(&1.type == :response_received))

    assert response_event
    assert response_event.data.streaming == true
  end

  test "event log includes streaming: false in metadata when not streaming", %{
    store: store,
    conv_id: conv_id
  } do
    set_responses([
      {:ok,
       %PhoenixAI.Response{
         content: "Blocked",
         usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 3, total_tokens: 8}
       }}
    ])

    {:ok, _} =
      Store.converse(conv_id, "Hello",
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        store: store
      )

    # Allow async post-processing task to complete
    Process.sleep(100)

    {:ok, %{events: events}} = Store.list_events([], store: store)

    response_event =
      Enum.find(events, &(&1.type == :response_received))

    assert response_event
    assert response_event.data.streaming == false
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs:"streaming event log" --seed 0 2>&1 | tail -20`

Expected: FAIL — `EventLog.log(:response_received, %{}, event_opts)` passes empty metadata, so `response_event.data.streaming` is nil/missing.

- [ ] **Step 3: Add streaming flag to event log metadata**

In `lib/phoenix_ai/store/converse_pipeline.ex`, find line 229 in `maybe_log_event/3`:

Replace:
```elixir
      EventLog.log(:response_received, %{}, event_opts)
```

With:
```elixir
      EventLog.log(:response_received, %{streaming: context[:streaming] || false}, event_opts)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --seed 0 2>&1 | tail -20`

Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/converse_pipeline.ex test/phoenix_ai/store/converse_integration_test.exs
git commit -m "feat(converse): include streaming flag in event log metadata"
```

---

### Task 6: Documentation Update

**Files:**
- Modify: `lib/phoenix_ai/store.ex` (`@doc` for converse/3)

- [ ] **Step 1: Update converse/3 @doc with streaming options**

In `lib/phoenix_ai/store.ex`, find the `@doc` block for `converse/3` (starts at line ~550). Add the streaming options after the existing options list and add a streaming example section.

Find the line:
```elixir
    * `:extract_facts` — whether to auto-extract LTM facts (default from config)
```

Add after it:
```elixir
    * `:on_chunk` — callback function receiving `%PhoenixAI.StreamChunk{}` structs during
      streaming. When provided, routes to `AI.stream/2` instead of `AI.chat/2`.
      Mutually exclusive with `:to`.
    * `:to` — PID to receive `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages during
      streaming. When provided, routes to `AI.stream/2` instead of `AI.chat/2`.
      Mutually exclusive with `:on_chunk`.
```

Find the line:
```elixir
    8. Extracting LTM facts (if enabled)
```

Add after it:
```elixir

  ## Streaming

  Pass `:on_chunk` or `:to` to receive tokens in real-time. The full pipeline
  (load, save, memory, guardrails, cost tracking, event log) runs identically —
  only the AI call step changes from `AI.chat/2` to `AI.stream/2`.

  Returns `{:ok, %Response{}}` after the stream completes, same as non-streaming.

  ### Examples

      # Callback-based streaming
      PhoenixAI.Store.converse(conv_id, "Hello",
        store: :my_store,
        provider: :openai,
        model: "gpt-4o",
        on_chunk: fn %PhoenixAI.StreamChunk{delta: text} ->
          send(my_liveview, {:ai_chunk, text})
        end
      )

      # PID-based streaming (e.g., from a LiveView)
      PhoenixAI.Store.converse(conv_id, "Hello",
        store: :my_store,
        provider: :openai,
        model: "gpt-4o",
        to: self()
      )
      # Caller receives {:phoenix_ai, {:chunk, %StreamChunk{}}} messages
```

- [ ] **Step 2: Run full test suite to confirm nothing broke**

Run: `mix test --seed 0 2>&1 | tail -10`

Expected: ALL PASS

- [ ] **Step 3: Run formatter and credo**

Run: `mix format && mix credo --strict 2>&1 | tail -10`

Expected: Clean

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store.ex
git commit -m "docs(converse): document on_chunk and to streaming options"
```

---

### Task 7: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `mix test 2>&1 | tail -15`

Expected: ALL PASS, 0 failures

- [ ] **Step 2: Run dialyzer**

Run: `mix dialyzer 2>&1 | tail -10`

Expected: No new warnings

- [ ] **Step 3: Run credo**

Run: `mix credo --strict 2>&1 | tail -10`

Expected: Clean

- [ ] **Step 4: Verify line count delta**

Run: `git diff --stat HEAD~6 2>&1`

Expected: ~25-35 lines of production code across 2 files, ~120-150 lines of test code in 1 file.
