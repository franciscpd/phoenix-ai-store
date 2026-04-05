# PRD: Add `provider` field to Response struct

**Date:** 2026-04-05
**Target:** phoenix_ai v0.3.1 (patch release)
**Motivation:** phoenix_ai_store Phase 6 (Cost Tracking) needs `{provider, model}` to look up pricing tables. `Response.model` exists but `Response.provider` is missing.

## Problem

The `%PhoenixAI.Response{}` struct has `model` but no `provider` field. Each provider adapter knows which provider it is (`:openai`, `:anthropic`, `:openrouter`) — this information exists at runtime in `chat/2` but is lost when `parse_response/1` constructs the Response.

Without `provider` on the Response, downstream consumers (like cost tracking) must require the developer to pass `:provider` as a separate option — duplicating information the system already has.

## Solution

Add `:provider` field to `Response` struct. Populate it in each provider's `parse_response/1`.

## Changes Required

### 1. `lib/phoenix_ai/response.ex` — Add field

```elixir
# Add to @type t
provider: atom() | nil,

# Add to defstruct
:provider,
```

Full struct after change:

```elixir
defstruct [
  :content,
  :parsed,
  :finish_reason,
  :model,
  :provider,           # <-- NEW
  tool_calls: [],
  usage: %Usage{},
  provider_response: %{}
]
```

### 2. `lib/phoenix_ai/providers/openai.ex` — Set provider in parse_response

In `parse_response/1` (~line 60), add `provider: :openai`:

```elixir
%Response{
  content: content,
  finish_reason: finish_reason,
  model: model,
  provider: :openai,    # <-- NEW
  usage: usage,
  tool_calls: tool_calls,
  provider_response: body
}
```

### 3. `lib/phoenix_ai/providers/anthropic.ex` — Set provider in parse_response

In `parse_response/1` (~line 213), add `provider: :anthropic`:

```elixir
%Response{
  content: final_content,
  finish_reason: stop_reason,
  model: model,
  provider: :anthropic,  # <-- NEW
  usage: usage,
  tool_calls: tool_calls,
  provider_response: body
}
```

### 4. `lib/phoenix_ai/providers/openrouter.ex` — Set provider in parse_response

Same pattern, add `provider: :openrouter`.

### 5. `lib/phoenix_ai/providers/test_provider.ex` — Set provider in parse_response

Add `provider: :test`.

### 6. Tests

Add a test per provider verifying `response.provider` is set:

```elixir
# In each provider test file:
test "response includes provider atom" do
  # ... existing test setup ...
  assert response.provider == :openai  # or :anthropic, :openrouter
end
```

## Scope

| In Scope | Out of Scope |
|----------|-------------|
| Add `provider` field to Response | Adding `provider` to Usage struct |
| Populate in all 4 provider adapters | Changing Provider behaviour signature |
| Tests for each provider | Telemetry changes |
| Bump version to 0.3.1 | Breaking changes |

## Impact

- **Backward compatible** — new optional field, defaults to `nil`
- **No behaviour change** — `parse_response/1` signature unchanged
- **Existing code unaffected** — pattern matches on Response without `:provider` still work
- **Enables:** phoenix_ai_store Cost Tracking can read `response.provider` + `response.model` to look up pricing without extra user configuration

## Version

Bump to **v0.3.1** in `mix.exs`. This is a non-breaking additive change.

## Telemetry (optional enhancement)

Consider adding `provider` to telemetry event metadata for `[:phoenix_ai, :chat, :stop]` — useful for cost tracking via telemetry handler. Not required for this release but a nice-to-have.
