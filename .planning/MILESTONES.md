# Milestones

## v0.3.0 — Dashboard Queries

**Shipped:** 2026-04-07
**Phases:** 2 | **Commits:** 28 | **Tests:** 421
**Lib:** 5,679 LOC | **Tests:** 4,974 LOC

### Delivered

Filter-based cost record querying with cursor pagination — consumers can build dashboard views without requiring a conversation_id. Breaking change to CostStore behaviour with clean migration path.

### Key Accomplishments

1. `list_cost_records/2` — unified filter-based API replacing `get_cost_records` (breaking change)
2. `count_cost_records/2` — count matching records without loading full structs
3. `PhoenixAI.Store.Cursor` — shared cursor module with defensive error handling (used by EventLog + CostStore)
4. Cursor-based pagination on cost records matching the `list_events` pattern
5. Provider filter normalization in facade (string→atom via `String.to_existing_atom/1`)
6. `--upgrade` flag on mix task for existing installations with versioned upgrade templates

### Requirements

10/10 v0.3.0 requirements satisfied (COST×4, ADPT×4, MIGR×2)

### Archive

- [Roadmap](milestones/v0.3.0-ROADMAP.md)
- [Requirements](milestones/v0.3.0-REQUIREMENTS.md)
- [Audit](milestones/v0.3.0-MILESTONE-AUDIT.md)

---

## v0.2.0 — Streaming Support

**Shipped:** 2026-04-06
**Phases:** 1 | **Commits:** 15 | **Tests:** 383
**Lib:** 5,400 LOC | **Tests:** 4,831 LOC

### Delivered

Streaming callback support for `converse/3` — consumers can receive AI response tokens in real-time via `on_chunk` callback or `to` PID options, with zero breaking changes.

### Key Accomplishments

1. `on_chunk` callback streaming — dispatch `%StreamChunk{}` to a function during AI generation
2. `to` PID streaming — send `{:phoenix_ai, {:chunk, chunk}}` messages for LiveView integration
3. Conflict validation — `{:error, :conflicting_streaming_options}` when both modes passed
4. Telemetry observability — `streaming: true/false` in span metadata for monitoring
5. Event log audit trail — streaming mode captured in `:response_received` event data

### Requirements

12/12 v0.2.0 requirements satisfied (STRM×4, COMPAT×2, OBS×2, DOCS×4)

### Archive

- [Roadmap](milestones/v0.2.0-ROADMAP.md)
- [Requirements](milestones/v0.2.0-REQUIREMENTS.md)
- [Audit](milestones/v0.2.0-MILESTONE-AUDIT.md)

---

## v0.1.0 — Initial Release

**Shipped:** 2026-04-05
**Phases:** 9 | **Commits:** 139 | **Tests:** 376
**Lib:** 5,350 LOC | **Tests:** 4,616 LOC

### Delivered

Persistence, memory management, guardrails, cost tracking, and an audit event log for PhoenixAI conversations — ready to publish on Hex.pm.

### Key Accomplishments

1. Adapter-based storage architecture (ETS + Ecto) with 5 optional sub-behaviours
2. Memory strategies: sliding window, token truncation, summarization, with pipeline composition
3. Long-term memory: cross-conversation facts and AI-generated user profiles
4. Guardrails: token budget (3 scopes) and cost budget with Hammer rate limiting
5. Cost tracking with Decimal arithmetic and pluggable pricing providers
6. Append-only event log with cursor pagination and configurable PII redaction
7. `converse/3` single-function pipeline orchestrating all subsystems
8. TelemetryHandler + HandlerGuardian for automatic event capture
9. Complete ExDoc documentation (4 guides), GitHub Actions CI, hex.publish ready

### Requirements

48/48 v1 requirements satisfied (STOR×7, MEM×7, LTM×5, GUARD×10, COST×8, EVNT×5, INTG×6)

### Archive

- [Roadmap](milestones/v0.1.0-ROADMAP.md)
- [Requirements](milestones/v0.1.0-REQUIREMENTS.md)
- [Audit](milestones/v0.1.0-MILESTONE-AUDIT.md)
