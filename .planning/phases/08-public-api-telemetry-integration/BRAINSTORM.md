# Phase 8: Public API & Telemetry Integration — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Requirements:** INTG-01, INTG-02, INTG-03, INTG-04, INTG-06

## Summary

Wire everything together: `converse/3` as the single-function pipeline (load → memory → guardrails → AI → save → cost → events → return), `Store.track/1` as ergonomic event capture, and `TelemetryHandler` + `HandlerGuardian` for automatic PhoenixAI event capture.

## Architecture

```
converse/3 → ConversePipeline.run/3 → [load → memory → guardrails → AI.chat → save → cost → events]
                                                                                    ↑ fire-and-forget
TelemetryHandler ← [:phoenix_ai, :chat, :stop] → Task.start → Store.record_cost + Store.log_event
HandlerGuardian → polls every 30s → reattaches TelemetryHandler if detached
```

## Module Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/converse_pipeline.ex` | Create | Full pipeline orchestration |
| `lib/phoenix_ai/store/telemetry_handler.ex` | Create | PhoenixAI event handler functions |
| `lib/phoenix_ai/store/handler_guardian.ex` | Create | Supervised reattachment GenServer |
| `lib/phoenix_ai/store.ex` | Modify | Add converse/3, track/1 |
| `lib/phoenix_ai/store/config.ex` | Modify | Add converse + telemetry config |

## ConversePipeline

### Module: `PhoenixAI.Store.ConversePipeline`

Single public function `run/3`:

```elixir
@spec run(String.t(), String.t(), map()) ::
        {:ok, PhoenixAI.Response.t()} | {:error, term()}
def run(conversation_id, message, context)
```

### Pipeline Steps

| Step | Function | Failure Behavior |
|------|----------|-----------------|
| 1. Load conversation | `load_conversation/2` | Abort with `{:error, :not_found}` |
| 2. Save user message | `save_user_message/3` | Abort with error |
| 3. Apply memory strategy | `prepare_messages/2` | Abort with error |
| 4. Run guardrails | `run_guardrails/2` | Abort with `{:error, %PolicyViolation{}}` |
| 5. Call AI | `call_ai/2` | Abort with AI error |
| 6. Save assistant message | `save_assistant_message/3` | Abort with error |
| 7. Record cost | `maybe_record_cost/3` | Fire-and-forget (log warning) |
| 8. Log events | `maybe_log_events/3` | Fire-and-forget (log warning) |
| 9. Extract LTM facts | `maybe_extract_facts/2` | Fire-and-forget (log warning) |

Steps 1-6 are in a `with` chain — first error aborts. Steps 7-9 are post-processing wrapped in `try/rescue`.

### Context Map

```elixir
%{
  adapter: module,
  adapter_opts: keyword,
  config: keyword,
  # From opts:
  provider: atom,
  model: String.t(),
  api_key: String.t(),
  system: String.t() | nil,
  tools: [module] | nil,
  memory_pipeline: Pipeline.t() | nil,
  guardrails: [policy_entry] | nil,
  user_id: String.t() | nil,
  extract_facts: boolean
}
```

### AI Call

Uses `AI.chat/2` directly:

```elixir
defp call_ai(messages, context) do
  opts = [
    provider: context.provider,
    model: context.model,
    api_key: context.api_key
  ]
  |> maybe_add(:system, context[:system])
  |> maybe_add(:tools, context[:tools])

  AI.chat(messages, opts)
end
```

### Message Flow

1. Load existing messages from adapter
2. Add user message to adapter (persists immediately)
3. Get all messages → apply memory pipeline → convert to PhoenixAI.Message
4. Optionally inject LTM context
5. Run guardrails against prepared messages
6. Call AI.chat with prepared messages
7. Save assistant response as new message
8. Return `%Response{}`

## Store.track/1

Ergonomic wrapper around `log_event/2`:

```elixir
@spec track(map()) :: {:ok, Event.t()} | {:error, term()}
def track(params) when is_map(params) do
  event = %Event{
    type: Map.fetch!(params, :type),
    data: Map.get(params, :data, %{}),
    conversation_id: Map.get(params, :conversation_id),
    user_id: Map.get(params, :user_id)
  }

  store = Map.get(params, :store, :phoenix_ai_store_default)
  log_event(event, store: store)
end
```

## TelemetryHandler

### Module: `PhoenixAI.Store.TelemetryHandler`

Plain module (not GenServer) with handler functions.

### Attachment

```elixir
@handler_id :phoenix_ai_store_telemetry_handler

def attach(opts \\ []) do
  events = [
    [:phoenix_ai, :chat, :stop],
    [:phoenix_ai, :tool_call, :stop]
  ]

  :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, opts)
end

def detach do
  :telemetry.detach(@handler_id)
end
```

### Event Handling

```elixir
def handle_event([:phoenix_ai, :chat, :stop], _measurements, metadata, opts) do
  ctx = get_conversation_context()
  store_opts = Keyword.merge(opts, store: opts[:store] || :phoenix_ai_store_default)

  Task.start(fn ->
    # Record cost if usage available
    if metadata[:usage] && ctx[:conversation_id] do
      response = %PhoenixAI.Response{
        provider: metadata[:provider],
        model: metadata[:model],
        usage: metadata[:usage]
      }

      Store.record_cost(ctx[:conversation_id], response,
        Keyword.merge(store_opts, user_id: ctx[:user_id]))
    end

    # Log :response_received event
    Store.log_event(%Event{
      type: :response_received,
      conversation_id: ctx[:conversation_id],
      user_id: ctx[:user_id],
      data: %{
        provider: metadata[:provider],
        model: metadata[:model]
      }
    }, store_opts)
  end)
end

def handle_event([:phoenix_ai, :tool_call, :stop], _measurements, metadata, opts) do
  ctx = get_conversation_context()
  store_opts = Keyword.merge(opts, store: opts[:store] || :phoenix_ai_store_default)

  Task.start(fn ->
    Store.log_event(%Event{
      type: :tool_called,
      conversation_id: ctx[:conversation_id],
      user_id: ctx[:user_id],
      data: %{tool: metadata[:tool]}
    }, store_opts)
  end)
end
```

### Context Propagation

Developer sets process metadata before AI calls:

```elixir
Logger.metadata(phoenix_ai_store: %{
  conversation_id: conv.id,
  user_id: current_user.id
})
```

Handler reads via:

```elixir
defp get_conversation_context do
  Logger.metadata()[:phoenix_ai_store] || %{}
end
```

## HandlerGuardian

### Module: `PhoenixAI.Store.HandlerGuardian`

Supervised GenServer that ensures TelemetryHandler stays attached.

```elixir
defmodule PhoenixAI.Store.HandlerGuardian do
  use GenServer

  @default_interval 30_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    handler_opts = Keyword.get(opts, :handler_opts, [])
    interval = Keyword.get(opts, :interval, @default_interval)

    TelemetryHandler.attach(handler_opts)
    schedule_check(interval)

    {:ok, %{handler_opts: handler_opts, interval: interval}}
  end

  @impl true
  def handle_info(:check_handlers, state) do
    handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
    handler_id = TelemetryHandler.handler_id()

    unless Enum.any?(handlers, &(&1.id == handler_id)) do
      Logger.warning("PhoenixAI.Store.TelemetryHandler detached, reattaching...")
      TelemetryHandler.attach(state.handler_opts)
    end

    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_handlers, interval)
  end
end
```

### Supervision

User adds to their supervision tree (opt-in):

```elixir
children = [
  {PhoenixAI.Store, name: :my_store, adapter: ETS},
  {PhoenixAI.Store.HandlerGuardian,
    handler_opts: [store: :my_store],
    interval: 30_000}
]
```

## Config Extension

```elixir
# In NimbleOptions @schema:
converse: [
  type: :keyword_list,
  default: [],
  keys: [
    provider: [type: :atom, doc: "Default AI provider."],
    model: [type: :string, doc: "Default model."],
    api_key: [type: :string, doc: "Default API key."],
    system: [type: :string, doc: "Default system prompt."],
    extract_facts: [type: :boolean, default: false, doc: "Auto-extract LTM facts after converse."]
  ]
]
```

## Telemetry Events

### New events from Phase 8:

| Event | Source |
|-------|--------|
| `[:phoenix_ai_store, :converse, :start\|:stop\|:exception]` | ConversePipeline |

### Existing events (verified complete):

| Event | Source | Phase |
|-------|--------|-------|
| `[:phoenix_ai_store, :conversation, :save\|:load\|:list\|:delete\|:count\|:exists]` | Store facade | 1 |
| `[:phoenix_ai_store, :message, :add\|:get]` | Store facade | 1 |
| `[:phoenix_ai_store, :memory, :apply]` | Store facade | 3 |
| `[:phoenix_ai_store, :guardrails, :check]` | Store facade | 5 |
| `[:phoenix_ai_store, :cost, :record\|:get\|:sum\|:recorded]` | Store facade + CostTracking | 6 |
| `[:phoenix_ai_store, :event, :log\|:list\|:count]` | Store facade | 7 |

## Requirements Coverage

| Requirement | Covered By |
|-------------|------------|
| INTG-01 (explicit API: track/1) | Store.track/1 wrapper |
| INTG-02 (telemetry handler) | TelemetryHandler with attach/detach |
| INTG-03 (handler guardian) | HandlerGuardian GenServer, 30s polling |
| INTG-04 (normalized Usage) | ConversePipeline uses Response.usage directly |
| INTG-06 (telemetry events) | All operations emit [:phoenix_ai_store, ...] spans |
