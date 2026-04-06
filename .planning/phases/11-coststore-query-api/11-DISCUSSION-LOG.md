# Phase 11: CostStore Query API - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-06
**Phase:** 11-coststore-query-api
**Areas discussed:** API Shape, Cursor Encoding, Provider Filter, Backward Compatibility

---

## API Shape (Nome da função e return shape)

| Option | Description | Selected |
|--------|-------------|----------|
| list_cost_records → %{records: ...} | Rename to list_cost_records(filters, opts). Return %{records: [...], next_cursor: ...}. Generic key :records | ✓ |
| list_cost_records → %{cost_records: ...} | Same name, but domain-specific key :cost_records (list_events uses :events) | |
| get_cost_records → %{records: ...} | Keep name get_cost_records but change signature to (filters, opts). Less import churn | |

**User's choice:** list_cost_records → %{records: ...}
**Notes:** Generic :records key chosen over domain-specific :cost_records

---

## Cursor Encoding & Error Handling

| Option | Description | Selected |
|--------|-------------|----------|
| CostTracking module + with/rescue | Create encode/decode_cursor in CostTracking. Defensive decode returning {:error, :invalid_cursor} | |
| Shared Cursor module | Extract cursor helpers into shared module (EventLog + CostTracking use same). More DRY | ✓ |
| Claude decides | Let Claude choose the approach | |

**User's choice:** Shared Cursor module
**Notes:** Also migrate EventLog to use the shared module. Defensive decode with `with` chain.

---

## Provider Filter: atom vs string

| Option | Description | Selected |
|--------|-------------|----------|
| Accept both, normalize in adapter | Each adapter normalizes: ETS string→atom, Ecto atom→string | |
| Normalize in facade before adapter | Store.list_cost_records normalizes provider to atom before delegating. Single normalization point | ✓ |
| Document: always atom | Provider MUST be atom. Error on string. Simple, explicit | |

**User's choice:** Normalize in facade (recommended by Claude after user asked "qual o melhor caminho?")
**Notes:** phoenix-filament-ai receives strings from HTTP params. Single normalization point in facade keeps adapters pure.

---

## Backward Compatibility

| Option | Description | Selected |
|--------|-------------|----------|
| Clean break total | Remove get_cost_records. Callers migrate to list_cost_records([conversation_id: id], opts). CHANGELOG entry | ✓ |
| Deprecation warning temporary | Keep get_cost_records with IO.warn + delegation. Remove in v0.4.0 | |
| Detect + route in facade | If first arg is binary, treat as conversation_id automatically. Implicit magic | |

**User's choice:** Clean break total
**Notes:** 0.x semver allows breaking changes. phoenix-filament-ai will update its calls.

---

## Claude's Discretion

- Internal cursor helper API design
- Whether to add @since annotations
- Test organization for cursor edge cases

## Deferred Ideas

None — discussion stayed within phase scope
