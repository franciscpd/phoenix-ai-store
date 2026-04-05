---
status: complete
phase: 05-guardrails
source: ROADMAP.md success criteria, PLAN.md, automated test verification
started: 2026-04-05T02:20:00Z
updated: 2026-04-05T02:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Token Budget Per Conversation
expected: Token budget with scope :conversation returns {:error, %PolicyViolation{}} when accumulated tokens (800) exceed max (100), and {:ok, %Request{}} when under budget (max: 10,000).
result: pass

### 2. Token Budget Per User
expected: Token budget with scope :user sums tokens across ALL user conversations (800 + 200 = 1000). Returns {:error, %PolicyViolation{}} when over max (500), passes when under (50,000).
result: pass

### 3. Tool Allowlist/Denylist (Core Policy)
expected: ToolPolicy with deny: ["dangerous_tool"] blocks requests containing that tool with PolicyViolation. Allows requests with safe tools.
result: pass

### 4. Jailbreak Detection (Core Policy)
expected: JailbreakDetection detects known patterns ("ignore previous instructions", "DAN", "developer mode") and returns PolicyViolation with score metadata. Normal messages pass.
result: pass

### 5. Custom Policy Composability
expected: Custom policy implementing Policy behaviour participates in stacked evaluation. First violation wins — BlockingPolicy halts chain before TokenBudget runs. PassingPolicy + TokenBudget compose in sequence.
result: pass

### 6. Store Facade Injects Adapter
expected: Store.check_guardrails/3 injects adapter and adapter_opts into request.assigns automatically. TokenBudget works through facade without manual adapter injection.
result: pass

### 7. Estimated Mode Counts Request Tokens
expected: With mode: :estimated, TokenBudget counts accumulated (800) + estimated request tokens (~625 for 2500 bytes). Total ~1425 > max 900 triggers violation with accumulated, estimated, and total in metadata.
result: pass

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
