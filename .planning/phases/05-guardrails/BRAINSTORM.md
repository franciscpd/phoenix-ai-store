# Phase 5: Guardrails — PRD for PhoenixAI Core

**Date:** 2026-04-04
**Status:** Approved
**Type:** Product Requirements Document (PRD) — input for phoenix_ai core milestone
**Requirements:** GUARD-01, GUARD-03, GUARD-04, GUARD-05, GUARD-06, GUARD-07, GUARD-08, GUARD-09, GUARD-10

## Summary

This PRD defines the Guardrails framework that should be implemented in the `phoenix_ai` core library. The framework provides a middleware-chain policy system that runs before each AI call — enforcing token budgets, tool allowlists/denylists, content filtering, and jailbreak/prompt injection detection.

The `phoenix_ai_store` library will later extend this framework with stateful policies (TokenBudget per-conversation/user, CostBudget) that require persistent storage.

## Architecture Split

| Component | Location | Rationale |
|-----------|----------|-----------|
| Policy behaviour | `phoenix_ai` core | Stateless contract — no storage dependency |
| Request struct | `phoenix_ai` core | Pure data structure |
| PolicyViolation struct | `phoenix_ai` core | Pure data structure |
| Pipeline (policy executor) | `phoenix_ai` core | Stateless orchestration |
| JailbreakDetection policy | `phoenix_ai` core | Analyzes message content — no storage |
| ContentFilter policy | `phoenix_ai` core | User-provided functions — no storage |
| ToolPolicy | `phoenix_ai` core | Config-based allowlist/denylist — no storage |
| JailbreakDetector behaviour | `phoenix_ai` core | Pluggable detection — no storage |
| Presets (:default, :strict, :permissive) | `phoenix_ai` core | Composition of core policies |
| TokenBudget policy | `phoenix_ai_store` (Phase 5.1) | Reads token_count from stored messages |
| CostBudget policy | `phoenix_ai_store` (Phase 6) | Reads CostRecords from store |
| Extended presets with stateful policies | `phoenix_ai_store` (Phase 5.1) | Depends on store adapter |

## Module Structure (for phoenix_ai core)

```
lib/phoenix_ai/guardrails/
  policy.ex                    — Policy behaviour (@callback check/2)
  request.ex                   — Request struct (the "conn")
  policy_violation.ex          — PolicyViolation struct
  pipeline.ex                  — Ordered policy execution with halt semantics
  jailbreak_detector.ex        — JailbreakDetector behaviour
  jailbreak_detector/
    default.ex                 — Keyword-based heuristics
  policies/
    jailbreak_detection.ex     — Policy wrapping JailbreakDetector
    content_filter.ex          — Pre/post user-provided function hooks
    tool_policy.ex             — Tool allowlist/denylist
```

## Detailed Specifications

### 1. Policy Behaviour

```elixir
defmodule PhoenixAI.Guardrails.Policy do
  @callback check(Request.t(), opts :: keyword()) ::
    {:ok, Request.t()} | {:error, PolicyViolation.t()}
end
```

Middleware chain semantics:
- `{:ok, request}` — pass. Request may have been modified (e.g., sanitized content). Next policy runs.
- `{:error, %PolicyViolation{}}` — halt. No further policies run. The violation is returned to the caller.

### 2. Request Struct

```elixir
defmodule PhoenixAI.Guardrails.Request do
  @type t :: %__MODULE__{
    messages: [PhoenixAI.Message.t()],
    user_id: String.t() | nil,
    conversation_id: String.t() | nil,
    tool_calls: [map()] | nil,
    metadata: map(),
    halted: boolean(),
    violation: PolicyViolation.t() | nil
  }

  defstruct [
    :user_id,
    :conversation_id,
    :tool_calls,
    :violation,
    messages: [],
    metadata: %{},
    halted: false
  ]
end
```

- `messages` — the messages about to be sent to the AI
- `tool_calls` — extracted from the last assistant message (if any)
- `halted` — set to `true` when a policy halts the chain
- `violation` — the PolicyViolation that caused the halt
- `metadata` — arbitrary data policies can read/write (e.g., a content filter adding a `sanitized: true` flag)

### 3. PolicyViolation Struct

```elixir
defmodule PhoenixAI.Guardrails.PolicyViolation do
  @type t :: %__MODULE__{
    policy: atom(),
    reason: String.t(),
    message: String.t() | nil,
    metadata: map()
  }

  defstruct [:policy, :reason, :message, metadata: %{}]
end
```

- `policy` — module atom of the policy that triggered (e.g., `PhoenixAI.Guardrails.Policies.JailbreakDetection`)
- `reason` — human-readable description (e.g., "Token budget exceeded: 105,000 / 100,000")
- `message` — the specific message content that caused the violation (nil if not message-specific)
- `metadata` — policy-specific data (e.g., `%{score: 0.85, threshold: 0.7}` for jailbreak detection)
- No severity field — every violation is blocking

### 4. Pipeline

```elixir
defmodule PhoenixAI.Guardrails.Pipeline do
  @type policy_entry :: {module(), keyword()}

  @spec run([policy_entry()], Request.t()) ::
    {:ok, Request.t()} | {:error, PolicyViolation.t()}

  # Executes policies sequentially in list order.
  # Stops at first {:error, violation}.
  # Returns {:ok, final_request} if all pass.
end
```

Presets:

```elixir
def preset(:default) do
  [{JailbreakDetection, []}]
end

def preset(:strict) do
  [{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]
end

def preset(:permissive) do
  [{JailbreakDetection, [threshold: 0.9]}]
end
```

Note: Core presets only include core (stateless) policies. `phoenix_ai_store` will extend presets with stateful policies (TokenBudget, CostBudget) in Phase 5.1.

### 5. JailbreakDetection Policy

Wraps the JailbreakDetector behaviour.

**Options:**
- `:detector` — module implementing JailbreakDetector (default: `JailbreakDetector.Default`)
- `:scope` — `:last_message` (default) or `:all_user_messages`
- `:threshold` — score threshold for violation (default: 0.7)

### 6. JailbreakDetector Behaviour

```elixir
defmodule PhoenixAI.Guardrails.JailbreakDetector do
  @callback detect(content :: String.t(), opts :: keyword()) ::
    {:ok, :safe} | {:ok, :detected, score :: float(), details :: map()}
end
```

**Default implementation** (`JailbreakDetector.Default`):

Keyword-based heuristic scoring:

| Category | Patterns | Weight |
|----------|----------|--------|
| Role override | "you are now", "act as", "pretend to be", "roleplay as" | 0.3 |
| Instruction override | "ignore previous", "disregard all", "forget your instructions", "new instructions" | 0.4 |
| DAN patterns | "DAN mode", "jailbreak", "bypass restrictions", "developer mode" | 0.3 |
| Encoding evasion | base64-encoded instructions, unicode homoglyphs (basic detection) | 0.2 |

Scoring: `score = sum(matched_weights)`. If `score >= threshold` → detected.

Developers can replace with: OpenAI Moderation API, custom ML classifiers, Anthropic's content filter API, etc.

### 7. ContentFilter Policy

Uses developer-provided functions as hooks:

**Options:**
- `:pre` — function `(message :: Message.t()) -> {:ok, Message.t()} | {:error, reason}` — runs before AI call
- `:post` — function `(message :: Message.t()) -> {:ok, Message.t()} | {:error, reason}` — runs after AI response

Pre-hooks can modify messages (e.g., PII redaction). Post-hooks validate AI responses.

### 8. ToolPolicy

**Options:**
- `:allow` — list of allowed tool names (allowlist mode)
- `:deny` — list of denied tool names (denylist mode)

Cannot set both `:allow` and `:deny` — raises at config validation.

Inspects `request.tool_calls` for tool names. If a tool is not in the allowlist (or is in the denylist), returns a violation identifying the tool.

## Integration Points

### For phoenix_ai core:

The pipeline should be callable standalone:

```elixir
request = %Request{messages: messages, user_id: "user_1"}
policies = Pipeline.preset(:default)

case Pipeline.run(policies, request) do
  {:ok, request} -> 
    # Safe to proceed with AI call
    AI.chat(request.messages, opts)
  
  {:error, %PolicyViolation{} = violation} ->
    # Blocked — return violation to caller
    {:error, violation}
end
```

### For phoenix_ai_store (Phase 5.1, future):

The Store will:
1. Add `TokenBudget` policy that reads token counts from the adapter
2. Add `CostBudget` policy (Phase 6) that reads cost records
3. Extend presets with stateful policies
4. Integrate into the `converse/2` pipeline (Phase 8)

## Configuration (NimbleOptions)

```elixir
guardrails: [
  type: :keyword_list,
  keys: [
    policies: [type: {:list, :any}, default: []],
    preset: [type: {:in, [:default, :strict, :permissive]}, default: nil],
    jailbreak_threshold: [type: :float, default: 0.7],
    jailbreak_scope: [type: {:in, [:last_message, :all_user_messages]}, default: :last_message],
    jailbreak_detector: [type: :atom, default: PhoenixAI.Guardrails.JailbreakDetector.Default]
  ]
]
```

## Telemetry

| Event | Metadata |
|-------|----------|
| `[:phoenix_ai, :guardrails, :check, :start\|:stop\|:exception]` | `policy_count`, `request` |
| `[:phoenix_ai, :guardrails, :policy, :start\|:stop\|:exception]` | `policy`, `result` (:pass or :violation) |
| `[:phoenix_ai, :guardrails, :jailbreak, :detected]` | `score`, `threshold`, `patterns` |

## Testing Strategy

- **Policy behaviour:** Each built-in policy tested in isolation with fixture data
- **Pipeline:** Test ordered execution, halt-on-first-violation, pass-through modification
- **JailbreakDetector.Default:** Test each pattern category with known examples
- **ContentFilter:** Test with pre/post function hooks that pass, modify, and reject
- **ToolPolicy:** Test allowlist and denylist modes
- **Integration:** End-to-end: build request → run pipeline → verify result

## Success Criteria (from ROADMAP.md)

1. Token budget per conversation/user returns `{:error, %PolicyViolation{}}` when exceeded
2. Tool allowlist/denylist rejects disallowed tools with structured violation
3. Pre/post content filtering hooks work; `{:error, reason}` stops the request
4. Custom Policy behaviour participates in stacked evaluation, first violation wins
5. Jailbreak detection catches known patterns; replaceable via JailbreakDetector behaviour

## Dependencies

- No new hex dependencies for the core framework
- `hammer` (optional) will be needed in `phoenix_ai_store` for time-window token budgets

---

*Phase: 05-guardrails*
*PRD created: 2026-04-04*
*Target: phoenix_ai core library — new milestone*
