# Requirements: PhoenixAI Store

**Defined:** 2026-04-05
**Core Value:** Conversations persist and restore transparently across process restarts, with memory strategies keeping them within context window limits

## v0.2.0 Requirements

Requirements for streaming support release. Each maps to roadmap phases.

### Streaming API

- [ ] **STRM-01**: User can pass `on_chunk` callback to `converse/3` to receive `%StreamChunk{}` in real-time
- [ ] **STRM-02**: User can pass `to` PID to `converse/3` to receive `{:phoenix_ai, {:chunk, chunk}}` messages
- [ ] **STRM-03**: `call_ai/2` routes to `AI.stream/2` when streaming opts present, `AI.chat/2` otherwise
- [ ] **STRM-04**: `@converse_schema` validates `on_chunk` (function/1 or nil) and `to` (pid or nil)

### Compatibility

- [ ] **COMPAT-01**: `converse/3` without streaming options behaves identically to v0.1.0
- [ ] **COMPAT-02**: Pipeline steps 1-4 and 6-7 are unmodified regardless of streaming mode

### Observability

- [ ] **OBS-01**: Telemetry span metadata includes `streaming: true/false` for converse events
- [ ] **OBS-02**: Event log entries capture streaming mode in metadata

### Testing & Docs

- [ ] **DOCS-01**: `converse/3` `@doc` updated with streaming options and examples
- [ ] **DOCS-02**: Tests cover `on_chunk` callback mode
- [ ] **DOCS-03**: Tests cover `to` PID mode
- [ ] **DOCS-04**: Tests verify backward compatibility (no streaming opts)

## Future Requirements

None deferred — scope is intentionally minimal for this milestone.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Partial message persistence during streaming | Save only the final response — streaming is a transport concern, not persistence |
| Streaming-specific guardrails (mid-stream checks) | Guardrails check before AI call, not during — architectural decision |
| Streaming-specific memory pipeline changes | Memory pipeline runs before AI call — unaffected by streaming |
| New StreamChunk fields or modifications | PhoenixAI owns this struct — not a Store concern |
| Provider-level streaming changes | Already fully implemented in PhoenixAI |
| Async/non-blocking converse mode | Different feature — streaming still blocks the caller until complete |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STRM-01 | — | Pending |
| STRM-02 | — | Pending |
| STRM-03 | — | Pending |
| STRM-04 | — | Pending |
| COMPAT-01 | — | Pending |
| COMPAT-02 | — | Pending |
| OBS-01 | — | Pending |
| OBS-02 | — | Pending |
| DOCS-01 | — | Pending |
| DOCS-02 | — | Pending |
| DOCS-03 | — | Pending |
| DOCS-04 | — | Pending |

**Coverage:**
- v0.2.0 requirements: 12 total
- Mapped to phases: 0
- Unmapped: 12 ⚠️

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after initial definition*
