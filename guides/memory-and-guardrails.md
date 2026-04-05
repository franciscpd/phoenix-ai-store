# Memory & Guardrails

This guide covers how to manage conversation history size with memory strategies and how
to enforce token or cost budgets with guardrail policies.

## Memory Strategies

AI providers impose context window limits. When a conversation grows beyond those limits
you need to trim messages before sending them. PhoenixAI.Store provides three built-in
strategies.

### SlidingWindow

`PhoenixAI.Store.Memory.Strategies.SlidingWindow` keeps the last N messages and
discards older ones.

**When to use:** Most conversations. Fast, zero dependencies, predictable cost.

Options:
- `:last` — number of most recent messages to retain (default: `50`)

Priority: `100` (runs after higher-priority strategies).

### TokenTruncation

`PhoenixAI.Store.Memory.Strategies.TokenTruncation` removes oldest messages until the
total token count fits within a budget.

**When to use:** When you need hard token limits rather than message count limits, or
when messages vary wildly in length.

Options:
- `:max_tokens` — maximum token budget (required)

Token counting uses `token_count` from the message struct when available. Falls back to
a heuristic counter (`chars / 4`) from `PhoenixAI.Store.Memory.TokenCounter.Default`.

Priority: `200`.

### Summarization

`PhoenixAI.Store.Memory.Strategies.Summarization` condenses older messages into an
AI-generated summary and injects it as a pinned system message.

**When to use:** Long-running conversations where you want to preserve context from
older messages rather than dropping them entirely.

Options:
- `:threshold` — minimum message count before summarization kicks in (default: `20`)
- `:provider` — AI provider override (falls back to pipeline context)
- `:model` — model override (falls back to pipeline context)
- `:summarize_fn` — `fun(messages, context, opts) :: {:ok, binary} | {:error, term}`
  override for testing without real AI calls

Priority: `300` (runs before SlidingWindow and TokenTruncation so the summary is in
place when the window strategy runs).

## Pipeline Composition

`PhoenixAI.Store.Memory.Pipeline` chains strategies together. Strategies are sorted by
priority before execution — lower priority number runs first.

The pipeline always:
1. Extracts pinned messages (role `:system` or `pinned: true`) before running strategies
2. Runs strategies on the remaining messages in priority order
3. Re-injects pinned messages at the beginning of the result

### `Pipeline.new/1`

Create a pipeline from a list of `{strategy_module, opts}` tuples:

```elixir
alias PhoenixAI.Store.Memory.Pipeline
alias PhoenixAI.Store.Memory.Strategies.{SlidingWindow, TokenTruncation, Summarization}

# Keep last 30 messages
pipeline = Pipeline.new([{SlidingWindow, [last: 30]}])

# Trim to 8000 tokens
pipeline = Pipeline.new([{TokenTruncation, [max_tokens: 8_000]}])

# Summarize long history, then keep last 20 messages
pipeline = Pipeline.new([
  {Summarization, [threshold: 40, provider: :openai, model: "gpt-4o-mini"]},
  {SlidingWindow, [last: 20]}
])
```

### Presets

`Pipeline.preset/1` returns common configurations:

```elixir
Pipeline.preset(:default)    # SlidingWindow last: 50
Pipeline.preset(:aggressive) # TokenTruncation max_tokens: 4096
Pipeline.preset(:summarize)  # Summarization threshold: 20, then SlidingWindow last: 20
```

## Using Memory with `converse/3`

Pass a pipeline via the `:memory_pipeline` option to `Store.converse/3`. The pipeline
runs between loading messages and calling the AI provider:

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.Memory.Pipeline
alias PhoenixAI.Store.Memory.Strategies.SlidingWindow

pipeline = Pipeline.new([{SlidingWindow, [last: 20]}])

{:ok, response} =
  Store.converse(conv.id, "What did we discuss earlier?",
    store: :my_store,
    memory_pipeline: pipeline
  )
```

### Applying Memory Manually

Call `Store.apply_memory/3` to get the filtered message list without starting a
`converse/3` turn — useful when you want to call `AI.chat/2` directly:

```elixir
pipeline = Pipeline.preset(:default)

{:ok, messages} = Store.apply_memory(conv.id, pipeline, store: :my_store)
# messages is a list of %PhoenixAI.Message{} ready for AI.chat/2

{:ok, response} = AI.chat(messages, provider: :openai, model: "gpt-4o")
```

Options accepted by `apply_memory/3`:
- `:store` — store instance name
- `:model` / `:provider` — passed to strategy context
- `:max_tokens` — token budget override
- `:token_counter` — token counter module override

### Long-Term Memory Injection

To automatically inject stored facts and user profiles into the message list before
the pipeline runs, pass `:inject_long_term_memory` and `:user_id`:

```elixir
{:ok, messages} =
  Store.apply_memory(conv.id, pipeline,
    store: :my_store,
    inject_long_term_memory: true,
    user_id: "user-123"
  )
```

## Guardrails

Guardrail policies run before the AI provider call in `converse/3`. They receive a
`%PhoenixAI.Guardrails.Request{}` and either approve it or halt with a
`%PhoenixAI.Guardrails.PolicyViolation{}`.

### TokenBudget

`PhoenixAI.Store.Guardrails.TokenBudget` reads accumulated token usage from the store
adapter and rejects requests that would exceed the budget.

**Requires:** The adapter must implement `PhoenixAI.Store.Adapter.TokenUsage`
(`sum_conversation_tokens/2` and `sum_user_tokens/2`). Both built-in adapters
implement this.

Options:
- `:max` (required) — maximum allowed token count
- `:scope` — `:conversation` (default), `:user`, or `:time_window`
- `:mode` — `:accumulated` (default, count only stored tokens) or `:estimated` (add
  estimated tokens for the current request)
- `:window_ms` — required for `:time_window` scope; window duration in milliseconds
- `:key_prefix` — key prefix for rate limiter (`:time_window` scope)
- `:token_counter` — token counter module

Scope behavior:
- `:conversation` — sums tokens across all messages in the conversation
- `:user` — sums tokens across all conversations for the user
- `:time_window` — uses [Hammer](https://hex.pm/packages/hammer) for sliding window
  rate limiting (requires `{:hammer, "~> 7.3"}` in your deps)

### CostBudget

`PhoenixAI.Store.Guardrails.CostBudget` reads accumulated cost from the store adapter
and rejects requests that would exceed the budget.

**Requires:** The adapter must implement `PhoenixAI.Store.Adapter.CostStore`
(`sum_cost/2`).

Options:
- `:max` (required) — maximum allowed cost as a `Decimal` or string (e.g. `"5.00"`)
- `:scope` — `:conversation` (default) or `:user`

## Using Guardrails with `converse/3`

Pass a list of policy entries via the `:guardrails` option:

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.Guardrails.{TokenBudget, CostBudget}

{:ok, response} =
  Store.converse(conv.id, "Continue our analysis",
    store: :my_store,
    user_id: "user-123",
    guardrails: [
      {TokenBudget, [max: 100_000, scope: :conversation]},
      {CostBudget, [max: "5.00", scope: :user]}
    ]
  )
```

When a policy rejects the request, `converse/3` returns `{:error, %PolicyViolation{}}`:

```elixir
case Store.converse(conv.id, message, store: :my_store, guardrails: [...]) do
  {:ok, response} ->
    response.content

  {:error, %PhoenixAI.Guardrails.PolicyViolation{} = violation} ->
    "Blocked: #{violation.reason}"
end
```

### Checking Guardrails Manually

Use `Store.check_guardrails/3` to run policies without starting a `converse/3` turn.
The store injects the adapter into `request.assigns` automatically:

```elixir
alias PhoenixAI.Guardrails.Request

request = %Request{
  messages: messages,
  conversation_id: conv.id,
  user_id: "user-123"
}

policies = [
  {TokenBudget, [max: 50_000, scope: :conversation]},
  {CostBudget, [max: "2.50", scope: :user]}
]

case Store.check_guardrails(request, policies, store: :my_store) do
  {:ok, _request} ->
    AI.chat(messages, provider: :openai, model: "gpt-4o")

  {:error, violation} ->
    {:error, violation.reason}
end
```

## Long-Term Memory

Long-term memory (LTM) stores per-user facts and profile summaries that persist across
conversations.

**Requires:** The adapter must implement `FactStore` and optionally `ProfileStore`.

### Storing Facts

```elixir
alias PhoenixAI.Store
alias PhoenixAI.Store.LongTermMemory.Fact

fact = %Fact{user_id: "user-123", key: "preferred_language", value: "Elixir"}
{:ok, saved_fact} = Store.save_fact(fact, store: :my_store)
```

`save_fact/2` uses upsert semantics — writing to the same `{user_id, key}` overwrites
the previous value.

Retrieve and delete facts:

```elixir
{:ok, facts} = Store.get_facts("user-123", store: :my_store)

:ok = Store.delete_fact("user-123", "preferred_language", store: :my_store)
```

### Automatic Fact Extraction

Configure automatic extraction in `converse/3` via the `:extract_facts` option or the
store-level `converse: [extract_facts: true]` default:

```elixir
{:ok, response} =
  Store.converse(conv.id, "My name is Alice and I prefer dark mode",
    store: :my_store,
    user_id: "user-123",
    extract_facts: true
  )
```

Trigger extraction manually:

```elixir
{:ok, facts} = Store.extract_facts(conv.id, store: :my_store, user_id: "user-123")

# Run in background (returns immediately)
{:ok, :async} =
  Store.extract_facts(conv.id,
    store: :my_store,
    extraction_mode: :async
  )
```

### User Profiles

Profiles are AI-generated summaries built from a user's stored facts:

```elixir
# Generate and save a profile from stored facts
{:ok, profile} =
  Store.update_profile("user-123",
    store: :my_store,
    provider: :openai,
    model: "gpt-4o-mini"
  )

# Load an existing profile
{:ok, profile} = Store.get_profile("user-123", store: :my_store)
IO.puts(profile.summary)
```

### LTM Configuration

Configure LTM behavior at the store level:

```elixir
{PhoenixAI.Store,
 name: :my_store,
 adapter: PhoenixAI.Store.Adapters.ETS,
 long_term_memory: [
   enabled: true,
   max_facts_per_user: 200,
   extraction_trigger: :per_turn,   # :manual | :per_turn | :on_close
   extraction_mode: :async,          # :sync | :async
   extraction_provider: :openai,
   extraction_model: "gpt-4o-mini",
   inject_long_term_memory: true     # auto-inject into apply_memory/3
 ]}
```

## See Also

- [Adapters](adapters.html) — choose a backend for memory and fact storage
- [Telemetry & Events](telemetry-and-events.html) — observe memory trim and guardrail violations
- [Getting Started](getting-started.html) — initial setup
