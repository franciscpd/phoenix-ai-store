# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] - 2026-04-07

### Added

- `list_cost_records/2` — filter-based cost record querying with cursor pagination
- `count_cost_records/2` — count cost records matching filters without loading records
- `PhoenixAI.Store.Cursor` — shared cursor encode/decode module with defensive error handling
- `--upgrade` flag on `mix phoenix_ai_store.gen.migration` for existing installations
- Composite `(recorded_at, id)` index on cost_records for cursor pagination performance
- Provider filter normalization in facade (accepts both atom and string)

### Changed

- **Breaking:** `get_cost_records(conversation_id, opts)` replaced by `list_cost_records(filters, opts)` — conversation_id is now an optional filter
- **Breaking:** Return type changed from `{:ok, [CostRecord.t()]}` to `{:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}`
- **Breaking:** `CostStore` behaviour callback signature updated — custom adapters must implement `list_cost_records/2` and `count_cost_records/2`
- EventLog cursor helpers migrated to shared `Cursor` module (no public API change)
- Invalid cursors now return `{:error, :invalid_cursor}` instead of crashing

### Migration Guide

Replace `Store.get_cost_records(conversation_id, opts)` with:
```elixir
Store.list_cost_records([conversation_id: conversation_id], opts)
```

For existing installations, run:
```
mix phoenix_ai_store.gen.migration --upgrade
mix ecto.migrate
```

## [0.2.0] - 2026-04-06

### Added

- Streaming support in `converse/3` via `on_chunk` callback and `to` PID options
- Streaming observability — telemetry span metadata and event log capture

## [0.1.0] - 2026-04-05

### Added

- Conversation persistence with ETS and Ecto adapters
- Memory strategies: sliding window, token-aware truncation, pinned messages
- Long-term memory: cross-conversation facts and user profile summaries
- Guardrails: token budget, cost budget, and Hammer rate limiting
- Cost tracking with Decimal arithmetic and pluggable pricing providers
- Append-only event log with cursor pagination and configurable redaction
- `converse/3` single-function pipeline (load → memory → guardrails → AI → save → track)
- `Store.track/1` ergonomic event capture API
- TelemetryHandler + HandlerGuardian for automatic PhoenixAI event capture
- Full telemetry instrumentation on all Store operations
- Mix task: `mix phoenix_ai_store.gen.migration`
