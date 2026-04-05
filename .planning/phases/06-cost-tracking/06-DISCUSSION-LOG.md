# Phase 6: Cost Tracking - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-05
**Phase:** 06-cost-tracking
**Mode:** discuss (interactive)
**Areas analyzed:** Decimal dependency, CostRecord storage, Pricing configuration, CostBudget guardrail, Usage integration

## Gray Areas Identified

### 1. Decimal Dependency Strategy
| Option | Tradeoff |
|--------|----------|
| Required dep (recommended) | Ensures COST-08 compliance for all adapters; lightweight |
| Optional dep | Violates COST-08 when Ecto absent — Float fallback causes drift |

**Decision:** Required dep — user confirmed recommendation.

### 2. CostRecord Storage Pattern
| Option | Tradeoff |
|--------|----------|
| CostStore sub-behaviour + dedicated table (recommended) | Follows established pattern; clean separation |
| Fields on Message struct | Bloats all messages; loses per-message granularity |
| Aggregate on Conversation | Loses provider/model/time-range query capability |

**Decision:** CostStore sub-behaviour — user confirmed recommendation.

### 3. Pricing Table Configuration
| Option | Tradeoff |
|--------|----------|
| Static config only | Simple but inflexible for enterprise |
| Static config + PricingProvider behaviour (recommended) | Best of both worlds |
| Only behaviour | Overengineering for simple cases |

**Decision:** Static + behaviour — user confirmed recommendation.

### 4. CostBudget Guardrail
Confident: Same pattern as TokenBudget. No discussion needed.

### 5. Usage Integration (PhoenixAI provider field)
**Issue identified:** `Response` struct had `model` but no `provider` field.
**Resolution:** Created PRD for phoenix_ai v0.3.1. User implemented and published the fix.
**Outcome:** `Response.provider` now available — cost tracking reads `{provider, model}` directly.

## External Dependency
- PhoenixAI bumped to v0.3.1 (provider field on Response) — committed as f444b9d
