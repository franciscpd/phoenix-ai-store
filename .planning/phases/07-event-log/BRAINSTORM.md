# Phase 7: Event Log — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Requirements:** EVNT-01, EVNT-02, EVNT-03, EVNT-04, EVNT-05

## Summary

Thin-layer append-only event log that automatically records significant actions through inline facade logging. Events are immutable, support cursor-based pagination, and configurable redaction for PII compliance. Fire-and-forget error handling — event logging never blocks main operations.

## Architecture

```
Facade fn → main operation → maybe_log_event → EventLog.log/3 → redact_fn → adapter.log_event
                                                                            → telemetry emit
```

No GenServer, no buffering. Synchronous write through adapter, wrapped in try/rescue for fire-and-forget semantics. Cursor pagination via `EventLog.list/2` is a separate query path.

## Module Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/event_log/event.ex` | Create | Event struct |
| `lib/phoenix_ai/store/event_log.ex` | Create | Orchestrator (log/3, list/2, cursor encode/decode) |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Add EventStore sub-behaviour |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement EventStore |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement EventStore |
| `lib/phoenix_ai/store/schemas/event.ex` | Create | Ecto schema |
| `priv/templates/events_migration.exs.eex` | Create | Migration template |
| `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` | Modify | Add --events flag |
| `lib/phoenix_ai/store/config.ex` | Modify | Add event_log section |
| `lib/phoenix_ai/store.ex` | Modify | Add log_event/2, list_events/2, inline logging |

## Event Struct

```elixir
defmodule PhoenixAI.Store.EventLog.Event do
  @type t :: %__MODULE__{
    id: String.t() | nil,
    conversation_id: String.t() | nil,
    user_id: String.t() | nil,
    type: atom(),
    data: map(),
    metadata: map(),
    inserted_at: DateTime.t() | nil
  }

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :type,
    :inserted_at,
    data: %{},
    metadata: %{}
  ]
end
```

No `updated_at` — events are immutable.

### Core Event Types

| Type Atom | Triggered By | Data Payload |
|-----------|-------------|--------------|
| `:conversation_created` | `save_conversation/2` | conversation_id, user_id, title |
| `:message_sent` | `add_message/3` | conversation_id, role, content, token_count |
| `:response_received` | Phase 8 TelemetryHandler | conversation_id, model, content, usage |
| `:tool_called` | Phase 8 TelemetryHandler | conversation_id, tool_name, arguments |
| `:tool_result` | Phase 8 TelemetryHandler | conversation_id, tool_name, result |
| `:policy_violation` | `check_guardrails/3` | policy, reason, scope, metadata |
| `:cost_recorded` | `record_cost/3` | conversation_id, provider, model, total_cost |
| `:memory_trimmed` | `apply_memory/3` | conversation_id, strategy, before_count, after_count |

Phase 7 implements 5 types inline (conversation_created, message_sent, policy_violation, cost_recorded, memory_trimmed). Phase 8 adds remaining 3 via TelemetryHandler.

## EventStore Sub-Behaviour

```elixir
defmodule EventStore do
  @callback log_event(Event.t(), keyword()) ::
              {:ok, Event.t()} | {:error, term()}

  @callback list_events(filters :: keyword(), keyword()) ::
              {:ok, %{events: [Event.t()], next_cursor: String.t() | nil}}

  @callback count_events(filters :: keyword(), keyword()) ::
              {:ok, non_neg_integer()}
end
```

**Append-only:** No update or delete callbacks. Immutability enforced at API level.

### list_events Filters

| Filter | Type | Description |
|--------|------|-------------|
| `:cursor` | String.t() | Opaque Base64 cursor, start after this event |
| `:limit` | integer | Max results (default 50) |
| `:conversation_id` | String.t() | Filter by conversation |
| `:user_id` | String.t() | Filter by user |
| `:type` | atom | Filter by event type |
| `:after` | DateTime.t() | Events with inserted_at >= value |
| `:before` | DateTime.t() | Events with inserted_at <= value |

Returns `%{events: [Event.t()], next_cursor: String.t() | nil}`. `next_cursor` is `nil` when fewer events than `limit` are returned (last page).

## Cursor-Based Pagination

### Encoding

```elixir
def encode_cursor(%Event{inserted_at: ts, id: id}) do
  Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
end

def decode_cursor(cursor_string) do
  cursor_string
  |> Base.url_decode64!(padding: false)
  |> String.split("|", parts: 2)
  |> then(fn [ts_str, id] ->
    {:ok, ts, _} = DateTime.from_iso8601(ts_str)
    {ts, id}
  end)
end
```

### Ecto Query

```sql
WHERE (inserted_at, id) > ($cursor_ts, $cursor_id)
ORDER BY inserted_at ASC, id ASC
LIMIT $limit
```

Composite index `(inserted_at, id)` ensures this is efficient.

### ETS Implementation

Sort all events by `{inserted_at, id}`, drop while `<= cursor`, take `limit`.

## Redaction

Configurable `redact_fn` of type `(Event.t()) -> Event.t()`. Runs in the EventLog orchestrator before the adapter call.

```elixir
# Config:
event_log: [
  enabled: true,
  redact_fn: &MyApp.Redactor.redact/1
]

# Example redactor:
def redact(%Event{type: :message_sent, data: data} = event) do
  %{event | data: Map.put(data, :content, "[REDACTED]")}
end
def redact(event), do: event
```

When `redact_fn` is `nil` (default), events pass through unmodified.

## Inline Logging (Fire-and-Forget)

### Error Handling

Event logging failures never block main operations:

```elixir
defp maybe_log_event(type, data, opts) do
  {_adapter, _adapter_opts, config} = resolve_adapter(opts)

  if get_in(config, [:event_log, :enabled]) do
    try do
      EventLog.log(type, data, opts)
    rescue
      e -> Logger.warning("Event log failed: #{inspect(e)}")
    end
  end

  :ok
end
```

### Facade Integration Points

| Facade Function | When | Event Type |
|----------------|------|------------|
| `save_conversation/2` | After successful save | `:conversation_created` |
| `add_message/3` | After successful add | `:message_sent` |
| `check_guardrails/3` | On policy violation (error path) | `:policy_violation` |
| `record_cost/3` | After successful record | `:cost_recorded` |
| `apply_memory/3` | After successful pipeline run | `:memory_trimmed` |

## Ecto Schema & Migration

### Table: `phoenix_ai_store_events`

| Column | Type | Notes |
|--------|------|-------|
| `id` | `:binary_id` | PK, UUID v7 |
| `conversation_id` | `:binary_id` | Indexed, nullable (some events are global) |
| `user_id` | `:string` | Indexed |
| `type` | `:string` | Atom stored as string |
| `data` | `:map` | jsonb |
| `metadata` | `:map` | jsonb |
| `inserted_at` | `:utc_datetime_usec` | Indexed, no updated_at |

### Indexes

- `conversation_id`
- `user_id`
- `inserted_at`
- `(inserted_at, id)` composite — cursor pagination
- `(conversation_id, inserted_at)` composite — per-conversation queries

### Append-Only Enforcement (Postgres)

Migration includes:
```sql
CREATE RULE no_update_events AS ON UPDATE TO phoenix_ai_store_events DO INSTEAD NOTHING;
CREATE RULE no_delete_events AS ON DELETE TO phoenix_ai_store_events DO INSTEAD NOTHING;
```

### Migration Generator

`mix phoenix_ai_store.gen.migration --events` for existing installs.

## Store Facade API

```elixir
# Explicit event logging
Store.log_event(%Event{type: :custom, data: %{...}}, store: :my_store)
# → {:ok, %Event{}}

# Cursor-based query
Store.list_events([conversation_id: "...", limit: 20], store: :my_store)
# → {:ok, %{events: [...], next_cursor: "base64..."}}

# Next page
Store.list_events([cursor: next_cursor, limit: 20], store: :my_store)
# → {:ok, %{events: [...], next_cursor: nil}}  # last page

# Count
Store.count_events([conversation_id: "..."], store: :my_store)
# → {:ok, 42}
```

## Config Extension

```elixir
event_log: [
  type: :keyword_list,
  default: [],
  keys: [
    enabled: [type: :boolean, default: false],
    redact_fn: [type: {:or, [{:fun, 1}, nil]}, default: nil]
  ]
]
```

## Requirements Coverage

| Requirement | Covered By |
|-------------|------------|
| EVNT-01 (core event types) | 5 types inline (Phase 7) + 3 via TelemetryHandler (Phase 8) |
| EVNT-02 (append-only, immutable) | No update/delete callbacks + Postgres RULE |
| EVNT-03 (cursor-based pagination) | list_events with Base64 composite cursor |
| EVNT-04 (configurable redaction) | redact_fn in config, runs pre-persistence |
| EVNT-05 (Ecto schema with indexes) | Events table with 5 indexes |
