# Telemetry & Events

PhoenixAI.Store emits telemetry spans for every operation and provides an append-only
event log for auditing AI conversations.

## Telemetry Events

All events follow the `[:phoenix_ai_store, :action, :start | :stop | :exception]`
span convention from `:telemetry.span/3`.

### Conversation Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :conversation, :save]` | `save_conversation/2` |
| `[:phoenix_ai_store, :conversation, :load]` | `load_conversation/2` |
| `[:phoenix_ai_store, :conversation, :list]` | `list_conversations/2` |
| `[:phoenix_ai_store, :conversation, :delete]` | `delete_conversation/2` |
| `[:phoenix_ai_store, :conversation, :count]` | `count_conversations/2` |
| `[:phoenix_ai_store, :conversation, :exists]` | `conversation_exists?/2` |

### Message Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :message, :add]` | `add_message/3` |
| `[:phoenix_ai_store, :message, :get]` | `get_messages/2` |

### Memory Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :memory, :apply]` | `apply_memory/3` |

### Guardrail Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :guardrails, :check]` | `check_guardrails/3` |

### Cost Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :cost, :record]` | `record_cost/3` |
| `[:phoenix_ai_store, :cost, :list_records]` | `list_cost_records/2` |
| `[:phoenix_ai_store, :cost, :count_records]` | `count_cost_records/2` |
| `[:phoenix_ai_store, :cost, :sum]` | `sum_cost/2` |
| `[:phoenix_ai_store, :cost, :recorded]` | Inside `CostTracking.record/3` after a successful persist |

### Event Log Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :event, :log]` | Inside `EventLog.log/3` |
| `[:phoenix_ai_store, :event, :log_event]` | `log_event/2` |
| `[:phoenix_ai_store, :event, :list]` | `list_events/2` |
| `[:phoenix_ai_store, :event, :count]` | `count_events/2` |

### Long-Term Memory Operations

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :fact, :save]` | `save_fact/2` |
| `[:phoenix_ai_store, :fact, :get]` | `get_facts/2` |
| `[:phoenix_ai_store, :fact, :delete]` | `delete_fact/3` |
| `[:phoenix_ai_store, :extract_facts]` | `extract_facts/2` |
| `[:phoenix_ai_store, :profile, :save]` | `save_profile/2` |
| `[:phoenix_ai_store, :profile, :get]` | `get_profile/2` |
| `[:phoenix_ai_store, :profile, :delete]` | `delete_profile/2` |
| `[:phoenix_ai_store, :profile, :update]` | `update_profile/2` |

### Top-Level Converse Span

| Event | When emitted |
|---|---|
| `[:phoenix_ai_store, :converse]` | `converse/3` — wraps the entire turn |

### Attaching Custom Handlers

```elixir
:telemetry.attach(
  "my-app-store-handler",
  [:phoenix_ai_store, :converse, :stop],
  fn event, measurements, metadata, _config ->
    Logger.info("Converse completed in #{measurements.duration}ns")
  end,
  nil
)
```

All `:stop` events include a `:duration` measurement (in native time units). Use
`System.convert_time_unit(measurements.duration, :native, :millisecond)` to convert.

## TelemetryHandler

`PhoenixAI.Store.TelemetryHandler` listens to PhoenixAI's upstream telemetry events
(`[:phoenix_ai, :chat, :stop]` and `[:phoenix_ai, :tool_call, :stop]`) and
asynchronously records cost and logs events through the Store.

This is the automatic integration mode: attach the handler once and every `AI.chat/2`
call made within a conversation context is automatically tracked.

### Attaching and Detaching

```elixir
# Attach (idempotent — safe to call multiple times)
PhoenixAI.Store.TelemetryHandler.attach()

# Detach
PhoenixAI.Store.TelemetryHandler.detach()
```

### Context Propagation via Logger Metadata

The handler reads `Logger.metadata()[:phoenix_ai_store]` to attribute events to the
correct conversation. Set this metadata before calling `AI.chat/2`:

```elixir
Logger.metadata(phoenix_ai_store: %{
  conversation_id: conv.id,
  user_id: "user-123",
  store: :my_store
})

{:ok, response} = AI.chat(messages, provider: :openai, model: "gpt-4o")
# TelemetryHandler sees the chat:stop event and records cost + logs the response
```

When using `Store.converse/3`, context is set automatically — you do not need to set
Logger metadata manually.

## HandlerGuardian

`PhoenixAI.Store.HandlerGuardian` is a supervised GenServer that ensures the telemetry
handler stays attached across node events, hot code reloads, and crashes.

On init it calls `TelemetryHandler.attach/1`. It then polls at a configurable interval
and reattaches the handler if it has been detached.

### Supervision Tree Setup

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyApp.Repo,
      {PhoenixAI.Store,
       name: :my_store,
       adapter: PhoenixAI.Store.Adapters.Ecto,
       repo: MyApp.Repo},

      # Keep the telemetry handler alive
      {PhoenixAI.Store.HandlerGuardian,
       name: :my_store_guardian,
       interval: 30_000}   # check every 30 seconds (default)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Options:
- `:name` (required) — GenServer name
- `:interval` — check interval in milliseconds (default: `30_000`)
- `:handler_opts` — options forwarded to `TelemetryHandler.attach/1` (default: `[]`)

## Store.track/1 — Explicit Event Capture

`Store.track/1` records a custom event through the event log using a plain map:

```elixir
PhoenixAI.Store.track(%{
  type: :user_feedback,
  data: %{rating: 5, comment: "Very helpful!"},
  conversation_id: conv.id,
  user_id: "user-123",
  store: :my_store
})
```

Required keys:
- `:type` — event type atom

Optional keys:
- `:data` — event data map (default: `%{}`)
- `:conversation_id` — conversation to associate the event with
- `:user_id` — user to associate the event with
- `:store` — store instance name (default: `:phoenix_ai_store_default`)

## Event Log

The event log is an append-only audit trail. Events are never updated or deleted, even
when their associated conversation is deleted. This makes it suitable for compliance,
debugging, and cost attribution.

### Built-in Event Types

The Store automatically logs these events when the event log is enabled:

| Type | Logged when |
|---|---|
| `:conversation_created` | `save_conversation/2` creates a new conversation |
| `:message_sent` | `add_message/3` persists a new message |
| `:memory_trimmed` | `apply_memory/3` reduces the message list |
| `:policy_violation` | `check_guardrails/3` halts with a violation |
| `:cost_recorded` | `record_cost/3` persists a cost record |

### Enabling the Event Log

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.Ecto,
 repo: MyApp.Repo,
 event_log: [
   enabled: true,
   redact_fn: nil   # optional (Event.t() -> Event.t())
 ]}
```

Requires the events migration:

```bash
mix phoenix_ai_store.gen.migration --events
mix ecto.migrate
```

### Logging Custom Events with `log_event/2`

Build an `%Event{}` and log it directly:

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.EventLog.Event

event = %Event{
  type: :agent_handoff,
  data: %{from_agent: "triage", to_agent: "billing"},
  conversation_id: conv.id,
  user_id: "user-123"
}

{:ok, logged_event} = Store.log_event(event, store: :my_store)
```

### Listing Events

`Store.list_events/2` returns a cursor-paginated result:

```elixir
{:ok, %{events: events, next_cursor: cursor}} =
  Store.list_events([conversation_id: conv.id, limit: 25], store: :my_store)

# Fetch the next page
{:ok, %{events: more_events, next_cursor: next}} =
  Store.list_events([conversation_id: conv.id, limit: 25, cursor: cursor], store: :my_store)
```

Supported filters:
- `:conversation_id` — filter by conversation
- `:user_id` — filter by user
- `:type` — filter by event type atom
- `:after` — include events with `inserted_at >= dt`
- `:before` — include events with `inserted_at <= dt`
- `:limit` — page size
- `:cursor` — opaque cursor from a previous `list_events/2` call

When `next_cursor` is `nil`, you are on the last page.

### Counting Events

```elixir
{:ok, count} =
  Store.count_events([user_id: "user-123", type: :policy_violation], store: :my_store)
```

### Redaction

Provide a `:redact_fn` to strip or mask sensitive data before persistence:

```elixir
defmodule MyApp.EventRedactor do
  def redact(%PhoenixAI.Store.EventLog.Event{type: :message_sent} = event) do
    %{event | data: Map.delete(event.data, :content)}
  end

  def redact(event), do: event
end

{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.Ecto,
 repo: MyApp.Repo,
 event_log: [
   enabled: true,
   redact_fn: &MyApp.EventRedactor.redact/1
 ]}
```

The `redact_fn` is called inside `EventLog.log/3` before the event is handed to the
adapter. The redacted form is what gets persisted.

## Cost Tracking

`Store.record_cost/3` records the cost of a single AI provider call. It resolves
pricing via a pricing provider module, computes costs with exact `Decimal` arithmetic,
and persists a `%CostRecord{}` through the adapter.

### Basic Usage

```elixir
{:ok, response} = AI.chat(messages, provider: :openai, model: "gpt-4o")

{:ok, cost_record} =
  PhoenixAI.Store.record_cost(conv.id, response,
    store: :my_store,
    user_id: "user-123"
  )

IO.puts("Cost: $#{Decimal.to_string(cost_record.total_cost)}")
```

`record_cost/3` requires `response.usage` to be a normalized `%PhoenixAI.Usage{}`
struct. PhoenixAI normalizes usage automatically as of version 0.2.

### Enabling Cost Tracking

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.Ecto,
 repo: MyApp.Repo,
 cost_tracking: [
   enabled: true,
   pricing_provider: PhoenixAI.Store.CostTracking.PricingProvider.Static
 ]}
```

Requires the cost migration:

```bash
mix phoenix_ai_store.gen.migration --cost
mix ecto.migrate
```

When `cost_tracking: [enabled: true]`, `Store.converse/3` calls `record_cost/3`
automatically after each successful AI response.

### Querying Costs

```elixir
# All cost records for a conversation
{:ok, %{records: records}} =
  Store.list_cost_records([conversation_id: conv.id], store: :my_store)

# All cost records globally (dashboard view)
{:ok, %{records: all_records, next_cursor: cursor}} =
  Store.list_cost_records([limit: 50], store: :my_store)

# Count records matching filters
{:ok, count} =
  Store.count_cost_records([user_id: "user-123"], store: :my_store)

# Aggregate cost by user this month
{:ok, total} =
  Store.sum_cost(
    [user_id: "user-123", after: ~U[2026-04-01 00:00:00Z]],
    store: :my_store
  )

IO.puts("Monthly spend: $#{Decimal.to_string(total)}")
```

Filters supported by `list_cost_records/2`, `count_cost_records/2`, and `sum_cost/2`:
- `:user_id` — filter by user
- `:conversation_id` — filter by conversation
- `:provider` — filter by provider atom (e.g. `:openai`)
- `:model` — filter by model string (e.g. `"gpt-4o"`)
- `:after` — include records with `recorded_at >= dt`
- `:before` — include records with `recorded_at <= dt`

### Pricing Providers

The default pricing provider is `PhoenixAI.Store.CostTracking.PricingProvider.Static`,
which has a built-in table of per-token prices for common models.

Implement the `PricingProvider` behaviour to use custom pricing:

```elixir
defmodule MyApp.CustomPricing do
  @behaviour PhoenixAI.Store.CostTracking.PricingProvider

  @impl true
  def price_for(:openai, "gpt-4o") do
    # Returns {input_price_per_token, output_price_per_token} as Decimal
    {:ok, {Decimal.new("0.000005"), Decimal.new("0.000015")}}
  end

  def price_for(_provider, _model), do: {:error, :unknown_model}
end
```

Configure the custom provider:

```elixir
{PhoenixAI.Store,
 name: :my_store,
 cost_tracking: [
   enabled: true,
   pricing_provider: MyApp.CustomPricing
 ]}
```

Or override per-call:

```elixir
{:ok, record} =
  Store.record_cost(conv.id, response,
    store: :my_store,
    pricing_provider: MyApp.CustomPricing
  )
```

## See Also

- [Getting Started](getting-started.html) — initial setup
- [Adapters](adapters.html) — which adapters support the event log and cost store
- [Memory & Guardrails](memory-and-guardrails.html) — policy violations appear in the event log
