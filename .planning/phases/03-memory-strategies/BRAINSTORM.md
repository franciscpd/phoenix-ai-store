# Phase 3: Memory Strategies — Design Spec

**Created:** 2026-04-03
**Status:** Approved
**Approach:** Strategy Behaviour + Pipeline Orchestrator

## Architecture Overview

Memory strategies are pure transformations on message lists — they filter what goes to the AI while the full history stays in the database. A `Pipeline` module orchestrates strategy execution: extracting pinned messages first, applying strategies by priority on the remaining messages, then re-injecting pinned messages at their original positions.

```
PhoenixAI.Store.Memory
├── Strategy (@behaviour)           — Contract: apply/3 + priority/0
├── Pipeline                        — Orchestrator: handles pinned, priority sorting, execution
├── TokenCounter (@behaviour)       — Contract for provider-dispatched token counting
├── TokenCounter.Default            — chars/4 heuristic implementation
└── Strategies/
    ├── SlidingWindow               — Keep last N messages
    ├── TokenTruncation             — Trim to fit token budget
    └── Summarization               — AI-powered condensation
```

## Strategy Behaviour

```elixir
defmodule PhoenixAI.Store.Memory.Strategy do
  @moduledoc "Behaviour for memory strategies that filter message lists."

  alias PhoenixAI.Store.Message

  @callback apply([Message.t()], context :: map(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}

  @callback priority() :: non_neg_integer()
  # Lower number = higher priority = runs first
end
```

**Built-in priorities:**
- SlidingWindow: 100
- TokenTruncation: 200
- Summarization: 300

**Context map:**
```elixir
%{
  conversation_id: String.t(),
  user_id: String.t() | nil,
  model: String.t() | nil,
  provider: atom() | nil,
  max_tokens: non_neg_integer() | nil,
  token_counter: module()  # defaults to TokenCounter.Default
}
```

## Pipeline

```elixir
defmodule PhoenixAI.Store.Memory.Pipeline do
  @moduledoc "Orchestrates memory strategy execution with priority-based ordering."

  def new(strategies)
  def preset(:default)       # SlidingWindow(last: 50)
  def preset(:aggressive)    # TokenTruncation(max_tokens: 4096)
  def preset(:summarize)     # Summarization(threshold: 20) + SlidingWindow(last: 20)

  def run(pipeline, messages, context, opts \\ [])
end
```

### Pipeline Execution Flow

```
Input: [sys(pinned), user1, asst1, ..., user50, asst50]

Step 1 — Extract pinned:
  pinned = [sys]  (role: :system OR pinned: true)
  remaining = [user1, asst1, ..., user50, asst50]

Step 2 — Sort strategies by priority():
  [SlidingWindow(100), TokenTruncation(200), ...]

Step 3 — Apply each strategy sequentially on remaining:
  SlidingWindow(last: 10) → [user46, asst46, ..., user50, asst50]
  TokenTruncation(4096) → [user47, asst47, ..., user50, asst50]

Step 4 — Re-inject pinned at original positions:
  [sys, user47, asst47, ..., user50, asst50]

Step 5 — Return:
  {:ok, [sys, user47, asst47, ..., user50, asst50]}
```

### Presets

| Preset | Strategies | Use case |
|--------|-----------|----------|
| `:default` | SlidingWindow(last: 50) | General conversations, simple truncation |
| `:aggressive` | TokenTruncation(max_tokens: 4096) | Tight token budgets |
| `:summarize` | Summarization(threshold: 20) + SlidingWindow(last: 20) | Long conversations needing context preservation |

Presets are convenience constructors — `Pipeline.preset(:default)` returns a `Pipeline` struct that can be further customized.

## Built-in Strategies

### SlidingWindow

Keeps the last N messages (excluding pinned — handled by Pipeline).

```elixir
defmodule PhoenixAI.Store.Memory.Strategies.SlidingWindow do
  @behaviour PhoenixAI.Store.Memory.Strategy

  def apply(messages, _context, opts) do
    last = Keyword.get(opts, :last, 50)
    {:ok, Enum.take(messages, -last)}
  end

  def priority, do: 100
end
```

**Options:** `last: integer` (default: 50)

### TokenTruncation

Removes oldest messages until total token count fits the budget. Over-truncates slightly (safe side).

```elixir
defmodule PhoenixAI.Store.Memory.Strategies.TokenTruncation do
  @behaviour PhoenixAI.Store.Memory.Strategy

  def apply(messages, context, opts) do
    max_tokens = Keyword.fetch!(opts, :max_tokens)
    counter = context[:token_counter] || PhoenixAI.Store.Memory.TokenCounter.Default

    # Sum from newest to oldest, collect messages that fit
    messages
    |> Enum.reverse()
    |> Enum.reduce_while({0, []}, fn msg, {total, acc} ->
      count = msg.token_count || counter.count_tokens(msg.content, opts)
      new_total = total + count
      if new_total <= max_tokens, do: {:cont, {new_total, [msg | acc]}}, else: {:halt, {total, acc}}
    end)
    |> elem(1)
    |> then(&{:ok, &1})
  end

  def priority, do: 200
end
```

**Options:** `max_tokens: integer` (required)

### Summarization

Condenses older messages into a summary via AI call. The summary becomes a pinned system message.

```elixir
defmodule PhoenixAI.Store.Memory.Strategies.Summarization do
  @behaviour PhoenixAI.Store.Memory.Strategy

  def apply(messages, context, opts) do
    threshold = Keyword.get(opts, :threshold, 20)

    if length(messages) < threshold do
      {:ok, messages}
    else
      split_point = length(messages) - div(threshold, 2)
      {to_summarize, to_keep} = Enum.split(messages, split_point)

      summary = generate_summary(to_summarize, context, opts)

      summary_msg = %Message{
        role: :system,
        content: summary,
        pinned: true,
        inserted_at: DateTime.utc_now()
      }

      {:ok, [summary_msg | to_keep]}
    end
  end

  def priority, do: 300
end
```

**Options:**
- `threshold: integer` (default: 20) — minimum messages before summarizing
- `provider: atom` — override provider (default: conversation's provider)
- `model: String.t()` — override model (default: conversation's model)

**Summarization calls AI via `AI.chat/2`** from the phoenix_ai dependency. Provider/model are configurable with fallback to the conversation's settings from context.

## TokenCounter Behaviour

```elixir
defmodule PhoenixAI.Store.Memory.TokenCounter do
  @moduledoc "Behaviour for counting tokens in message content."

  @callback count_tokens(content :: String.t(), opts :: keyword()) :: non_neg_integer()
end

defmodule PhoenixAI.Store.Memory.TokenCounter.Default do
  @moduledoc "Default token counter using chars/4 heuristic (~15% accuracy for English)."

  @behaviour PhoenixAI.Store.Memory.TokenCounter

  @impl true
  def count_tokens(nil, _opts), do: 0
  def count_tokens(content, _opts), do: max(1, div(String.length(content), 4))
end
```

Developers can implement their own counter (e.g., wrapping tiktoken NIF for OpenAI models, or calling Anthropic's Token Count API).

## Changes to Existing Code

### Message Struct — add `pinned` field

```elixir
# lib/phoenix_ai/store/message.ex
@type t :: %__MODULE__{
  ...,
  pinned: boolean()
}

defstruct [
  ...,
  pinned: false
]
```

`pinned` is dropped in `to_phoenix_ai/1` (not a PhoenixAI.Message field).

### Message Ecto Schema — add `pinned` column

```elixir
# lib/phoenix_ai/store/schemas/message.ex
field :pinned, :boolean, default: false
```

### Migration Template — add `pinned` column

```
add :pinned, :boolean, default: false, null: false
```

### Store Facade — add `apply_memory/3`

```elixir
# New public function in PhoenixAI.Store
@spec apply_memory(String.t(), Pipeline.t(), keyword()) ::
        {:ok, [PhoenixAI.Message.t()]} | {:error, term()}
def apply_memory(conversation_id, pipeline, opts \\ [])
```

**Flow:**
1. Load messages via `get_messages/2`
2. Build context map from config + opts (model, provider, max_tokens, token_counter)
3. Run `Pipeline.run(pipeline, messages, context)`
4. Convert output via `Message.to_phoenix_ai/1`
5. Return `{:ok, [%PhoenixAI.Message{}]}` — ready for Agent's `messages:` option

**Integration with Agent:**
```elixir
pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)
{:ok, messages} = PhoenixAI.Store.apply_memory(conv.id, pipeline)
{:ok, response} = PhoenixAI.Agent.prompt(agent, "Hello", messages: messages)
```

## Testing Strategy

- **Strategy unit tests**: each strategy tested independently with fixture message lists
- **Pipeline tests**: verify pinned extraction/re-injection, priority ordering, preset construction
- **TokenCounter tests**: verify default heuristic, custom counter integration
- **Integration tests**: `apply_memory/3` end-to-end with ETS adapter
- **Summarization tests**: mock AI call, verify summary message properties (role, pinned, content)

---

*Phase: 03-memory-strategies*
*Design approved: 2026-04-03*
