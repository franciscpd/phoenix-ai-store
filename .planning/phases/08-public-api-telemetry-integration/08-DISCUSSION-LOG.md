# Phase 8: Public API & Telemetry Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-04-05
**Phase:** 08-public-api-telemetry-integration
**Mode:** discuss (interactive)
**Areas analyzed:** converse/2 pipeline, AI call strategy, Store.track/1, TelemetryHandler, HandlerGuardian, context propagation

## Gray Areas Resolved

### 1. AI Call Strategy
| Option | Tradeoff |
|--------|----------|
| AI.chat/2 direct (recommended) | Stateless, simple, no Agent dep |
| Agent PID | Requires pre-started Agent |
| Both via overload | Confusing API |

**Decision:** AI.chat/2 direct — user confirmed.

### 2. Pipeline Architecture
| Option | Tradeoff |
|--------|----------|
| Dedicated pipeline (recommended) | Resolve adapter 1x, performant |
| Compose facade fns | 7+ redundant GenServer calls |

**Decision:** Dedicated pipeline — user confirmed.

### 3. Conversation Context in TelemetryHandler
| Option | Tradeoff |
|--------|----------|
| Process metadata (recommended) | Zero PhoenixAI changes, dev sets Logger.metadata |
| Opts on attach | Doesn't scale (1 conv per handler) |
| Ignore context | Useless for per-conversation audit |

**Decision:** Process metadata — user confirmed.

### 4. Store.track/1 Design
| Option | Tradeoff |
|--------|----------|
| Wrapper around log_event/2 (recommended) | Ergonomic, both APIs available |
| Replace log_event/2 | Breaking change |

**Decision:** Wrapper — user confirmed.
