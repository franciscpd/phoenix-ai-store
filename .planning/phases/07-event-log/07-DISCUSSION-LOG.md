# Phase 7: Event Log - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-05
**Phase:** 07-event-log
**Mode:** discuss (interactive)
**Areas analyzed:** EventStore pattern, append-only enforcement, cursor pagination, redaction, event struct, automatic recording

## Gray Areas Identified

### 1. EventStore Sub-Behaviour
Confident — follows established pattern. No discussion needed.

### 2. Append-Only Enforcement
| Option | Tradeoff |
|--------|----------|
| API-level only | Simple, portable, but no DB guarantee |
| API-level + Postgres constraint (recommended) | Dual enforcement, stronger compliance |

**Decision:** API + Postgres constraint — user confirmed recommendation.

### 3. Cursor-Based Pagination
| Option | Tradeoff |
|--------|----------|
| Composite (inserted_at, id) Base64 cursor (recommended) | Standard pattern, correct ordering |
| Auto-increment integer cursor | Simpler but breaks UUID v7 convention |

**Decision:** Base64 composite cursor — user confirmed recommendation.

### 4. Redaction
Confident — pre-persistence function via NimbleOptions. No discussion needed.

### 5. Event Struct Design
| Option | Tradeoff |
|--------|----------|
| Generic type + data map (recommended) | Flexible, extensible, one schema |
| Typed fields per event | Type-safe but rigid |
| Behaviour per type | Overengineering |

**Decision:** Generic struct with type atom + data map — user confirmed recommendation.

### 6. Automatic Recording
| Option | Tradeoff |
|--------|----------|
| Inline in facade only | Works for Phase 7 but incomplete |
| TelemetryHandler only (Phase 8) | Requires extra developer setup |
| Both — inline + telemetry (recommended) | Complete coverage, no extra code |

**Decision:** Phase 7 inline + Phase 8 telemetry — user confirmed recommendation.
