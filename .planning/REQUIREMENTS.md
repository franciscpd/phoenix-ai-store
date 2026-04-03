# Requirements: PhoenixAI Store

**Defined:** 2026-04-03
**Core Value:** Conversations persist and restore transparently across process restarts, with memory strategies keeping them within context window limits

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Storage

- [ ] **STOR-01**: Developer can implement custom storage backend via Store behaviour (save/load/list/delete_conversation callbacks)
- [ ] **STOR-02**: Developer can persist conversations to Postgres or SQLite via Ecto adapter
- [ ] **STOR-03**: Developer can use ETS-backed InMemory adapter for testing and development
- [ ] **STOR-04**: Developer can generate Ecto migrations via `mix phoenix_ai_store.gen.migration`
- [ ] **STOR-05**: Conversation struct owns persistence-specific fields (id, user_id, timestamps, metadata, tags)
- [ ] **STOR-06**: Developer can list conversations with pagination and filtering (by user_id, tags, date range)
- [ ] **STOR-07**: Developer can store and retrieve conversation metadata (tags, agent config, custom fields)

### Memory Management

- [ ] **MEM-01**: Developer can apply sliding window strategy to keep last N messages
- [ ] **MEM-02**: Developer can apply token-aware truncation based on provider/model token limits
- [ ] **MEM-03**: Developer can pin messages as never-evictable (e.g., system prompt)
- [ ] **MEM-04**: Developer can apply summarization strategy that uses AI to condense older messages
- [ ] **MEM-05**: Developer can implement custom memory strategies via Strategy behaviour
- [ ] **MEM-06**: Developer can compose multiple strategies (e.g., pinned + sliding window + summarization)
- [ ] **MEM-07**: Memory strategies integrate with Agent's `manage_history: false` + `messages:` pattern

### Long-Term Memory

- [ ] **LTM-01**: System can extract and store key-value facts from conversations (user preferences, personal data)
- [ ] **LTM-02**: Developer can manually add/update/delete user facts
- [ ] **LTM-03**: System can generate and update a user profile summary using AI across conversations
- [ ] **LTM-04**: Long-term memory (facts + profile) is automatically injected as context before each AI call
- [ ] **LTM-05**: Developer can implement custom long-term memory extraction via behaviour

### Guardrails

- [ ] **GUARD-01**: Developer can enforce token budget per conversation, per user, and per time window
- [ ] **GUARD-02**: Developer can enforce cost budget per conversation, per user, and per time window
- [ ] **GUARD-03**: Developer can define tool allow/deny policies per conversation or globally
- [ ] **GUARD-04**: Developer can add pre/post content filtering hooks for message validation
- [ ] **GUARD-05**: Developer can implement custom policies via Policy behaviour
- [ ] **GUARD-06**: Policies are stackable and composable (deterministic evaluation, first violation wins)
- [ ] **GUARD-07**: Policy violations return `{:error, %PolicyViolation{}}` with clear reason and policy reference
- [ ] **GUARD-08**: Built-in jailbreak and prompt injection detection with default heuristics
- [ ] **GUARD-09**: Developer can replace default jailbreak/prompt injection detection via behaviour
- [ ] **GUARD-10**: Guardrails run pre-call to prevent cost before API call is made

### Cost Tracking

- [ ] **COST-01**: Developer can configure model pricing tables (input/output token prices per provider/model)
- [ ] **COST-02**: System tracks per-conversation cost accumulated from Response.usage data
- [ ] **COST-03**: System tracks per-user cost aggregated across conversations
- [ ] **COST-04**: System emits telemetry events for real-time cost monitoring
- [ ] **COST-05**: Developer can query costs by time range, provider, model, user, and conversation
- [ ] **COST-06**: Cost records are persisted in Ecto schema linked to conversations
- [ ] **COST-07**: Cost tracking integrates with guardrails for automatic budget enforcement
- [ ] **COST-08**: All cost arithmetic uses Decimal (not Float) for precision

### Event Log

- [ ] **EVNT-01**: System logs core event types: conversation_created, message_sent, response_received, tool_called, tool_result, policy_violation, cost_recorded, memory_trimmed
- [ ] **EVNT-02**: Event log is append-only and immutable (never modified or deleted)
- [ ] **EVNT-03**: Developer can paginate events with cursor-based pagination
- [ ] **EVNT-04**: Developer can configure redaction rules to strip sensitive data before persistence
- [ ] **EVNT-05**: Events are stored in Ecto schema with indexed timestamps and conversation references

### Integration

- [ ] **INTG-01**: Developer can capture events via explicit API (Store.track/1) as primary interface
- [ ] **INTG-02**: Developer can attach telemetry handler as automatic alternative for event capture
- [ ] **INTG-03**: Telemetry handler includes supervised guardian process for automatic reattachment on failure
- [ ] **INTG-04**: Library works with PhoenixAI's normalized Usage struct for cost data
- [ ] **INTG-05**: All configuration uses NimbleOptions for validation
- [ ] **INTG-06**: All operations emit telemetry events following PhoenixAI conventions

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Memory Management

- **MEM-V2-01**: Rate-limited summarization with configurable thresholds
- **MEM-V2-02**: Semantic memory with vector embeddings (RAG-style retrieval)

### Guardrails

- **GUARD-V2-01**: Rate limiting per time window (requests per minute/hour)
- **GUARD-V2-02**: Distributed rate limiting across cluster nodes

### Cost Tracking

- **COST-V2-01**: Cost forecasting and trend analysis
- **COST-V2-02**: Provider-specific pricing auto-update from API

### Event Log

- **EVNT-V2-01**: Event streaming via Phoenix PubSub
- **EVNT-V2-02**: Event replay for conversation reconstruction

## Out of Scope

| Feature | Reason |
|---------|--------|
| RAG / Vector embeddings | Separate concern, requires vector DB — different library |
| Provider routing / failover | Belongs in PhoenixAI core |
| Multi-agent workflow orchestration | Belongs in PhoenixAI core (Teams) |
| Workspace snapshots | Not relevant for API-based interactions |
| Real-time UI / rendering | Application concern |
| Automatic migration execution | Users control migration timing via mix task |
| Distributed rate limiting (v1) | v1 is single-node; cluster support deferred to v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STOR-01 | Phase 1 | Pending |
| STOR-02 | Phase 1 | Pending |
| STOR-03 | Phase 1 | Pending |
| STOR-04 | Phase 1 | Pending |
| STOR-05 | Phase 1 | Pending |
| STOR-06 | Phase 2 | Pending |
| STOR-07 | Phase 2 | Pending |
| MEM-01 | Phase 3 | Pending |
| MEM-02 | Phase 3 | Pending |
| MEM-03 | Phase 3 | Pending |
| MEM-04 | Phase 3 | Pending |
| MEM-05 | Phase 3 | Pending |
| MEM-06 | Phase 3 | Pending |
| MEM-07 | Phase 3 | Pending |
| LTM-01 | Phase 4 | Pending |
| LTM-02 | Phase 4 | Pending |
| LTM-03 | Phase 4 | Pending |
| LTM-04 | Phase 4 | Pending |
| LTM-05 | Phase 4 | Pending |
| GUARD-01 | Phase 5 | Pending |
| GUARD-02 | Phase 6 | Pending |
| GUARD-03 | Phase 5 | Pending |
| GUARD-04 | Phase 5 | Pending |
| GUARD-05 | Phase 5 | Pending |
| GUARD-06 | Phase 5 | Pending |
| GUARD-07 | Phase 5 | Pending |
| GUARD-08 | Phase 5 | Pending |
| GUARD-09 | Phase 5 | Pending |
| GUARD-10 | Phase 5 | Pending |
| COST-01 | Phase 6 | Pending |
| COST-02 | Phase 6 | Pending |
| COST-03 | Phase 6 | Pending |
| COST-04 | Phase 6 | Pending |
| COST-05 | Phase 6 | Pending |
| COST-06 | Phase 6 | Pending |
| COST-07 | Phase 6 | Pending |
| COST-08 | Phase 6 | Pending |
| EVNT-01 | Phase 7 | Pending |
| EVNT-02 | Phase 7 | Pending |
| EVNT-03 | Phase 7 | Pending |
| EVNT-04 | Phase 7 | Pending |
| EVNT-05 | Phase 7 | Pending |
| INTG-01 | Phase 8 | Pending |
| INTG-02 | Phase 8 | Pending |
| INTG-03 | Phase 8 | Pending |
| INTG-04 | Phase 8 | Pending |
| INTG-05 | Phase 1 | Pending |
| INTG-06 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 48 total (STOR×7, MEM×7, LTM×5, GUARD×10, COST×8, EVNT×5, INTG×6)
- Mapped to phases: 48
- Unmapped: 0

**Note:** The original traceability table listed "46 total" but the enumerated requirements count to 48. All 48 are mapped above.

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after roadmap creation — all requirements mapped*
