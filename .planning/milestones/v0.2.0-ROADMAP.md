# Roadmap: PhoenixAI Store

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-9 (shipped 2026-04-05)
- 🚧 **v0.2.0 Streaming Support** — Phase 10 (in progress)

## Phases

<details>
<summary>✅ v0.1.0 Initial Release (Phases 1-9) — SHIPPED 2026-04-05</summary>

- [x] Phase 1: Storage Foundation — completed 2026-03-29
- [x] Phase 2: Storage Queries & Metadata — completed 2026-03-30
- [x] Phase 3: Memory Strategies — completed 2026-03-31
- [x] Phase 4: Long-Term Memory — completed 2026-04-01
- [x] Phase 5: Guardrails — completed 2026-04-03
- [x] Phase 6: Cost Tracking — completed 2026-04-04
- [x] Phase 7: Event Log — completed 2026-04-05
- [x] Phase 8: Public API & Telemetry Integration — completed 2026-04-05
- [x] Phase 9: Documentation, CI & Publication — completed 2026-04-05

48/48 requirements satisfied. 376 tests, 0 failures. 5,350 LOC.

See [full roadmap archive](milestones/v0.1.0-ROADMAP.md) for phase details.

</details>

### 🚧 v0.2.0 Streaming Support (In Progress)

**Milestone Goal:** Add streaming callback support to `converse/3` so consumers can receive AI response tokens in real-time via `on_chunk` callback or `to` PID options, while preserving full backward compatibility with v0.1.0.

## Phase Details

### Phase 10: Streaming Support
**Goal**: Users can stream AI response tokens in real-time through `converse/3` using either a callback function or a PID target, with no behavior change for existing non-streaming callers
**Depends on**: Phase 9 (v0.1.0 complete)
**Requirements**: STRM-01, STRM-02, STRM-03, STRM-04, COMPAT-01, COMPAT-02, OBS-01, OBS-02, DOCS-01, DOCS-02, DOCS-03, DOCS-04
**Success Criteria** (what must be TRUE):
  1. User can pass `on_chunk: fn chunk -> ... end` to `converse/3` and receive `%StreamChunk{}` structs as the AI generates tokens
  2. User can pass `to: pid` to `converse/3` and receive `{:phoenix_ai, {:chunk, chunk}}` messages in a process
  3. Calling `converse/3` without streaming options returns the same `{:ok, response}` result as v0.1.0 with identical pipeline behavior
  4. Telemetry spans for `converse` events include a `streaming: true | false` metadata key observable by attached handlers
  5. Event log entries written during a streaming `converse/3` call include `streaming: true` in their metadata map
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation | v0.1.0 | — | Complete | 2026-03-29 |
| 2. Storage Queries & Metadata | v0.1.0 | — | Complete | 2026-03-30 |
| 3. Memory Strategies | v0.1.0 | — | Complete | 2026-03-31 |
| 4. Long-Term Memory | v0.1.0 | — | Complete | 2026-04-01 |
| 5. Guardrails | v0.1.0 | — | Complete | 2026-04-03 |
| 6. Cost Tracking | v0.1.0 | — | Complete | 2026-04-04 |
| 7. Event Log | v0.1.0 | — | Complete | 2026-04-05 |
| 8. Public API & Telemetry Integration | v0.1.0 | — | Complete | 2026-04-05 |
| 9. Documentation, CI & Publication | v0.1.0 | — | Complete | 2026-04-05 |
| 10. Streaming Support | v0.2.0 | 0/TBD | Not started | - |
