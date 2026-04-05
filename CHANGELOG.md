# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
