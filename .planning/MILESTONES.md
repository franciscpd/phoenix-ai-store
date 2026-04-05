# Milestones

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
