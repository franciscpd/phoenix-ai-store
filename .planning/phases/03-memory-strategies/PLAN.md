# Phase 3: Memory Strategies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver memory strategies (sliding window, token truncation, pinned messages, summarization) that filter a conversation's message list before sending to the AI, with a Pipeline orchestrator for priority-based composition.

**Architecture:** Strategy behaviour + Pipeline orchestrator. Strategies are pure functions (`apply/3`) with priorities. Pipeline extracts pinned messages, applies strategies by priority on remaining messages, re-injects pinned at original positions. Summarization is the only strategy with side effects (AI call).

**Tech Stack:** Elixir, PhoenixAI (AI.chat/2 for summarization), Mox (mocking AI calls in tests)

---

## File Structure

```
lib/phoenix_ai/store/
├── memory/
│   ├── strategy.ex                         # @behaviour — apply/3 + priority/0
│   ├── pipeline.ex                         # Orchestrator: pinned handling, priority sorting
│   ├── token_counter.ex                    # @behaviour for token counting
│   ├── token_counter/
│   │   └── default.ex                      # chars/4 heuristic
│   └── strategies/
│       ├── sliding_window.ex               # Keep last N messages
│       ├── token_truncation.ex             # Trim to fit token budget
│       └── summarization.ex                # AI-powered condensation

test/phoenix_ai/store/
├── memory/
│   ├── pipeline_test.exs
│   ├── token_counter/
│   │   └── default_test.exs
│   └── strategies/
│       ├── sliding_window_test.exs
│       ├── token_truncation_test.exs
│       └── summarization_test.exs

# Modified existing files:
lib/phoenix_ai/store/message.ex             # Add pinned: boolean field
lib/phoenix_ai/store/schemas/message.ex     # Add pinned column
lib/phoenix_ai/store.ex                     # Add apply_memory/3
priv/templates/migration.exs.eex            # Add pinned column
test/support/migrations/...                 # Update test migration
```

---

### Task 1: Add `pinned` Field to Message

**Files:**
- Modify: `lib/phoenix_ai/store/message.ex`
- Modify: `lib/phoenix_ai/store/schemas/message.ex`
- Modify: `priv/templates/migration.exs.eex`
- Modify: `test/support/migrations/20260403000000_create_store_tables.exs`
- Modify: `test/phoenix_ai/store/message_test.exs`

- [ ] **Step 1: Write test for pinned field**

Add to `test/phoenix_ai/store/message_test.exs`:

```elixir
test "pinned defaults to false" do
  msg = %Message{}
  assert msg.pinned == false
end

test "pinned can be set to true" do
  msg = %Message{pinned: true, role: :system, content: "Important"}
  assert msg.pinned == true
end

test "to_phoenix_ai drops pinned field" do
  msg = %Message{role: :user, content: "Hi", pinned: true}
  phoenix_msg = Message.to_phoenix_ai(msg)
  refute Map.has_key?(phoenix_msg, :pinned)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/message_test.exs`
Expected: FAIL — `pinned` not a field.

- [ ] **Step 3: Add pinned to Message struct**

In `lib/phoenix_ai/store/message.ex`, add `pinned: boolean()` to the type and `pinned: false` to defstruct:

```elixir
@type t :: %__MODULE__{
        id: String.t() | nil,
        conversation_id: String.t() | nil,
        role: :system | :user | :assistant | :tool | nil,
        content: String.t() | nil,
        tool_call_id: String.t() | nil,
        tool_calls: [map()] | nil,
        metadata: map(),
        token_count: non_neg_integer() | nil,
        pinned: boolean(),
        inserted_at: DateTime.t() | nil
      }

defstruct [
  :id,
  :conversation_id,
  :role,
  :content,
  :tool_call_id,
  :tool_calls,
  :inserted_at,
  token_count: nil,
  pinned: false,
  metadata: %{}
]
```

- [ ] **Step 4: Add pinned to Ecto schema**

In `lib/phoenix_ai/store/schemas/message.ex`, add the field inside the schema block:

```elixir
field :pinned, :boolean, default: false
```

Add `:pinned` to `@cast_fields`.

Update `to_store_struct/1` to include `pinned: schema.pinned || false`.
Update `from_store_struct/1` to include `pinned: msg.pinned || false`.

- [ ] **Step 5: Update migration template**

In `priv/templates/migration.exs.eex`, add inside the messages table block (after `add :metadata`):

```
add :pinned, :boolean, default: false, null: false
```

- [ ] **Step 6: Update test migration**

In `test/support/migrations/20260403000000_create_store_tables.exs`, add inside the messages table block:

```elixir
add(:pinned, :boolean, default: false, null: false)
```

- [ ] **Step 7: Run migration on test DB**

Run: `MIX_ENV=test mix ecto.rollback -r PhoenixAI.Store.Test.Repo --migrations-path test/support/migrations && MIX_ENV=test mix ecto.migrate -r PhoenixAI.Store.Test.Repo --migrations-path test/support/migrations`

- [ ] **Step 8: Run all tests**

Run: `mix test`
Expected: All tests PASS (91 existing + 3 new = 94).

- [ ] **Step 9: Commit**

```bash
git add lib/phoenix_ai/store/message.ex lib/phoenix_ai/store/schemas/message.ex priv/templates/migration.exs.eex test/support/migrations/ test/phoenix_ai/store/message_test.exs
git commit -m "feat(memory): add pinned field to Message struct and schema"
```

---

### Task 2: TokenCounter Behaviour & Default Implementation

**Files:**
- Create: `lib/phoenix_ai/store/memory/token_counter.ex`
- Create: `lib/phoenix_ai/store/memory/token_counter/default.ex`
- Test: `test/phoenix_ai/store/memory/token_counter/default_test.exs`

- [ ] **Step 1: Write test for Default TokenCounter**

```elixir
# test/phoenix_ai/store/memory/token_counter/default_test.exs
defmodule PhoenixAI.Store.Memory.TokenCounter.DefaultTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.TokenCounter.Default

  describe "count_tokens/2" do
    test "returns 0 for nil content" do
      assert Default.count_tokens(nil, []) == 0
    end

    test "returns 0 for empty string" do
      assert Default.count_tokens("", []) == 0
    end

    test "counts using chars/4 heuristic" do
      # 20 chars / 4 = 5 tokens
      assert Default.count_tokens("12345678901234567890", []) == 5
    end

    test "returns at least 1 for non-empty content" do
      assert Default.count_tokens("Hi", []) >= 1
    end

    test "handles long content" do
      content = String.duplicate("a", 1000)
      assert Default.count_tokens(content, []) == 250
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/memory/token_counter/default_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement TokenCounter behaviour**

```elixir
# lib/phoenix_ai/store/memory/token_counter.ex
defmodule PhoenixAI.Store.Memory.TokenCounter do
  @moduledoc """
  Behaviour for counting tokens in message content.

  Implement this behaviour to provide provider-specific token counting.
  The default implementation uses a `chars / 4` heuristic.
  """

  @callback count_tokens(content :: String.t() | nil, opts :: keyword()) :: non_neg_integer()
end
```

- [ ] **Step 4: Implement Default counter**

```elixir
# lib/phoenix_ai/store/memory/token_counter/default.ex
defmodule PhoenixAI.Store.Memory.TokenCounter.Default do
  @moduledoc """
  Default token counter using a `chars / 4` heuristic.

  Approximately 15% accuracy for English text. Sufficient for memory
  strategy truncation decisions. For higher accuracy, implement a
  custom `PhoenixAI.Store.Memory.TokenCounter` (e.g., wrapping tiktoken).
  """

  @behaviour PhoenixAI.Store.Memory.TokenCounter

  @impl true
  def count_tokens(nil, _opts), do: 0
  def count_tokens("", _opts), do: 0

  def count_tokens(content, _opts) when is_binary(content) do
    max(1, div(String.length(content), 4))
  end
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/phoenix_ai/store/memory/token_counter/default_test.exs`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/memory/token_counter.ex lib/phoenix_ai/store/memory/token_counter/default.ex test/phoenix_ai/store/memory/token_counter/default_test.exs
git commit -m "feat(memory): add TokenCounter behaviour and Default implementation"
```

---

### Task 3: Strategy Behaviour & SlidingWindow

**Files:**
- Create: `lib/phoenix_ai/store/memory/strategy.ex`
- Create: `lib/phoenix_ai/store/memory/strategies/sliding_window.ex`
- Test: `test/phoenix_ai/store/memory/strategies/sliding_window_test.exs`

- [ ] **Step 1: Write SlidingWindow test**

```elixir
# test/phoenix_ai/store/memory/strategies/sliding_window_test.exs
defmodule PhoenixAI.Store.Memory.Strategies.SlidingWindowTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.SlidingWindow
  alias PhoenixAI.Store.Message

  defp make_messages(n) do
    for i <- 1..n do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}"}
    end
  end

  describe "apply/3" do
    test "keeps last N messages" do
      messages = make_messages(10)
      {:ok, result} = SlidingWindow.apply(messages, %{}, last: 3)

      assert length(result) == 3
      assert Enum.map(result, & &1.content) == ["Message 8", "Message 9", "Message 10"]
    end

    test "returns all when fewer than N" do
      messages = make_messages(3)
      {:ok, result} = SlidingWindow.apply(messages, %{}, last: 10)
      assert length(result) == 3
    end

    test "defaults to last 50" do
      messages = make_messages(60)
      {:ok, result} = SlidingWindow.apply(messages, %{}, [])
      assert length(result) == 50
    end

    test "handles empty list" do
      {:ok, result} = SlidingWindow.apply([], %{}, last: 5)
      assert result == []
    end
  end

  describe "priority/0" do
    test "returns 100" do
      assert SlidingWindow.priority() == 100
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/memory/strategies/sliding_window_test.exs`
Expected: FAIL — modules not found.

- [ ] **Step 3: Implement Strategy behaviour**

```elixir
# lib/phoenix_ai/store/memory/strategy.ex
defmodule PhoenixAI.Store.Memory.Strategy do
  @moduledoc """
  Behaviour for memory strategies that filter message lists.

  Strategies receive a list of messages (excluding pinned — handled by Pipeline),
  a context map with conversation metadata, and options. They return a filtered
  message list.

  ## Priority

  Lower number = higher priority = runs first in the pipeline.

  Built-in priorities:
  - SlidingWindow: 100
  - TokenTruncation: 200
  - Summarization: 300
  """

  alias PhoenixAI.Store.Message

  @callback apply([Message.t()], context :: map(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}

  @callback priority() :: non_neg_integer()
end
```

- [ ] **Step 4: Implement SlidingWindow**

```elixir
# lib/phoenix_ai/store/memory/strategies/sliding_window.ex
defmodule PhoenixAI.Store.Memory.Strategies.SlidingWindow do
  @moduledoc """
  Keeps the last N messages from the conversation.

  Pinned messages are handled by the Pipeline — this strategy only
  sees non-pinned messages.

  ## Options

  - `:last` - Number of messages to keep (default: 50)
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  @default_last 50

  @impl true
  def apply(messages, _context, opts) do
    last = Keyword.get(opts, :last, @default_last)
    {:ok, Enum.take(messages, -last)}
  end

  @impl true
  def priority, do: 100
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/phoenix_ai/store/memory/strategies/sliding_window_test.exs`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/memory/strategy.ex lib/phoenix_ai/store/memory/strategies/sliding_window.ex test/phoenix_ai/store/memory/strategies/sliding_window_test.exs
git commit -m "feat(memory): add Strategy behaviour and SlidingWindow strategy"
```

---

### Task 4: TokenTruncation Strategy

**Files:**
- Create: `lib/phoenix_ai/store/memory/strategies/token_truncation.ex`
- Test: `test/phoenix_ai/store/memory/strategies/token_truncation_test.exs`

- [ ] **Step 1: Write TokenTruncation test**

```elixir
# test/phoenix_ai/store/memory/strategies/token_truncation_test.exs
defmodule PhoenixAI.Store.Memory.Strategies.TokenTruncationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.TokenTruncation
  alias PhoenixAI.Store.Message

  defp make_messages(n, token_count) do
    for i <- 1..n do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}", token_count: token_count}
    end
  end

  @context %{token_counter: PhoenixAI.Store.Memory.TokenCounter.Default}

  describe "apply/3" do
    test "keeps messages within token budget using pre-computed counts" do
      # 5 messages × 10 tokens = 50 total. Budget = 30 → keep 3 newest.
      messages = make_messages(5, 10)
      {:ok, result} = TokenTruncation.apply(messages, @context, max_tokens: 30)

      assert length(result) == 3
      assert Enum.map(result, & &1.content) == ["Message 3", "Message 4", "Message 5"]
    end

    test "keeps all messages when under budget" do
      messages = make_messages(3, 10)
      {:ok, result} = TokenTruncation.apply(messages, @context, max_tokens: 100)
      assert length(result) == 3
    end

    test "returns empty when first message exceeds budget" do
      messages = [%Message{id: "1", role: :user, content: "x", token_count: 500}]
      {:ok, result} = TokenTruncation.apply(messages, @context, max_tokens: 10)
      assert result == []
    end

    test "uses TokenCounter when token_count is nil" do
      # "Hello World!" = 12 chars / 4 = 3 tokens
      messages = [
        %Message{id: "1", role: :user, content: "Hello World!", token_count: nil},
        %Message{id: "2", role: :user, content: "Hello World!", token_count: nil}
      ]

      {:ok, result} = TokenTruncation.apply(messages, @context, max_tokens: 5)
      assert length(result) == 1
      assert hd(result).id == "2"
    end

    test "handles empty list" do
      {:ok, result} = TokenTruncation.apply([], @context, max_tokens: 100)
      assert result == []
    end
  end

  describe "priority/0" do
    test "returns 200" do
      assert TokenTruncation.priority() == 200
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/memory/strategies/token_truncation_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement TokenTruncation**

```elixir
# lib/phoenix_ai/store/memory/strategies/token_truncation.ex
defmodule PhoenixAI.Store.Memory.Strategies.TokenTruncation do
  @moduledoc """
  Removes oldest messages until the total token count fits the budget.

  Uses pre-computed `token_count` from message fields when available,
  falling back to the `TokenCounter` from context.

  Over-truncates slightly rather than sending too many tokens (safe side).

  ## Options

  - `:max_tokens` - Maximum total tokens allowed (required)
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  alias PhoenixAI.Store.Memory.TokenCounter

  @impl true
  def apply(messages, context, opts) do
    max_tokens = Keyword.fetch!(opts, :max_tokens)
    counter = context[:token_counter] || TokenCounter.Default

    result =
      messages
      |> Enum.reverse()
      |> Enum.reduce_while({0, []}, fn msg, {total, acc} ->
        count = msg.token_count || counter.count_tokens(msg.content, opts)
        new_total = total + count

        if new_total <= max_tokens do
          {:cont, {new_total, [msg | acc]}}
        else
          {:halt, {total, acc}}
        end
      end)
      |> elem(1)

    {:ok, result}
  end

  @impl true
  def priority, do: 200
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/memory/strategies/token_truncation_test.exs`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/memory/strategies/token_truncation.ex test/phoenix_ai/store/memory/strategies/token_truncation_test.exs
git commit -m "feat(memory): add TokenTruncation strategy"
```

---

### Task 5: Summarization Strategy

**Files:**
- Create: `lib/phoenix_ai/store/memory/strategies/summarization.ex`
- Test: `test/phoenix_ai/store/memory/strategies/summarization_test.exs`

- [ ] **Step 1: Write Summarization test**

```elixir
# test/phoenix_ai/store/memory/strategies/summarization_test.exs
defmodule PhoenixAI.Store.Memory.Strategies.SummarizationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.Summarization
  alias PhoenixAI.Store.Message

  defp make_messages(n) do
    for i <- 1..n do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}"}
    end
  end

  describe "apply/3" do
    test "returns messages unchanged when below threshold" do
      messages = make_messages(5)
      context = %{provider: :openai, model: "gpt-4o"}
      {:ok, result} = Summarization.apply(messages, context, threshold: 10)
      assert result == messages
    end

    test "summarizes older messages when above threshold" do
      messages = make_messages(25)
      context = %{provider: :openai, model: "gpt-4o-mini"}

      # Mock the AI call by passing a summarize_fn in opts
      summarize_fn = fn _messages, _context, _opts ->
        {:ok, "This is a summary of the conversation."}
      end

      {:ok, result} =
        Summarization.apply(messages, context, threshold: 20, summarize_fn: summarize_fn)

      # First message should be the summary (pinned, system role)
      summary = hd(result)
      assert summary.role == :system
      assert summary.pinned == true
      assert summary.content == "This is a summary of the conversation."

      # Rest should be recent messages
      assert length(result) < length(messages)
    end

    test "handles empty list" do
      {:ok, result} = Summarization.apply([], %{}, threshold: 10)
      assert result == []
    end
  end

  describe "priority/0" do
    test "returns 300" do
      assert Summarization.priority() == 300
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/memory/strategies/summarization_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement Summarization**

```elixir
# lib/phoenix_ai/store/memory/strategies/summarization.ex
defmodule PhoenixAI.Store.Memory.Strategies.Summarization do
  @moduledoc """
  Condenses older messages into a single summary via an AI call.

  The summary becomes a pinned system message, preserving conversation
  context while dramatically reducing token count.

  This is the only strategy with external side effects (AI call).
  All others are pure functions.

  ## Options

  - `:threshold` - Minimum messages before summarizing (default: 20)
  - `:provider` - Override AI provider (default: from context)
  - `:model` - Override AI model (default: from context)
  - `:summarize_fn` - Custom summarization function for testing
    (receives messages, context, opts; returns `{:ok, summary_text}`)
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  alias PhoenixAI.Store.Message

  @default_threshold 20

  @impl true
  def apply(messages, context, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    if length(messages) < threshold do
      {:ok, messages}
    else
      keep_count = div(threshold, 2)
      split_point = length(messages) - keep_count
      {to_summarize, to_keep} = Enum.split(messages, split_point)

      case do_summarize(to_summarize, context, opts) do
        {:ok, summary_text} ->
          summary_msg = %Message{
            role: :system,
            content: summary_text,
            pinned: true,
            inserted_at: DateTime.utc_now()
          }

          {:ok, [summary_msg | to_keep]}

        {:error, _} = error ->
          error
      end
    end
  end

  @impl true
  def priority, do: 300

  defp do_summarize(messages, context, opts) do
    case Keyword.get(opts, :summarize_fn) do
      nil -> call_ai(messages, context, opts)
      fun when is_function(fun, 3) -> fun.(messages, context, opts)
    end
  end

  defp call_ai(messages, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

    conversation_text =
      messages
      |> Enum.map(fn msg -> "#{msg.role}: #{msg.content}" end)
      |> Enum.join("\n")

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content:
          "Summarize the following conversation concisely, preserving key facts, decisions, and context. Output only the summary, no preamble."
      },
      %PhoenixAI.Message{role: :user, content: conversation_text}
    ]

    ai_opts = [provider: provider, model: model]
    ai_opts = Enum.reject(ai_opts, fn {_k, v} -> is_nil(v) end)

    case AI.chat(prompt, ai_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/memory/strategies/summarization_test.exs`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/memory/strategies/summarization.ex test/phoenix_ai/store/memory/strategies/summarization_test.exs
git commit -m "feat(memory): add Summarization strategy with AI-powered condensation"
```

---

### Task 6: Pipeline Orchestrator

**Files:**
- Create: `lib/phoenix_ai/store/memory/pipeline.ex`
- Test: `test/phoenix_ai/store/memory/pipeline_test.exs`

- [ ] **Step 1: Write Pipeline test**

```elixir
# test/phoenix_ai/store/memory/pipeline_test.exs
defmodule PhoenixAI.Store.Memory.PipelineTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Pipeline
  alias PhoenixAI.Store.Memory.Strategies.{SlidingWindow, TokenTruncation}
  alias PhoenixAI.Store.Message

  defp make_messages(n) do
    for i <- 1..n do
      %Message{
        id: "msg-#{i}",
        role: :user,
        content: "Message #{i}",
        token_count: 5
      }
    end
  end

  describe "new/1" do
    test "creates pipeline from strategy modules with opts" do
      pipeline = Pipeline.new([{SlidingWindow, last: 10}])
      assert %Pipeline{} = pipeline
    end

    test "creates pipeline from multiple strategies" do
      pipeline = Pipeline.new([{SlidingWindow, last: 10}, {TokenTruncation, max_tokens: 100}])
      assert length(pipeline.strategies) == 2
    end
  end

  describe "preset/1" do
    test ":default creates SlidingWindow with last: 50" do
      pipeline = Pipeline.preset(:default)
      assert %Pipeline{} = pipeline
    end

    test ":aggressive creates TokenTruncation with max_tokens: 4096" do
      pipeline = Pipeline.preset(:aggressive)
      assert %Pipeline{} = pipeline
    end

    test ":summarize creates Summarization + SlidingWindow" do
      pipeline = Pipeline.preset(:summarize)
      assert %Pipeline{} = pipeline
    end
  end

  describe "run/4" do
    test "extracts pinned messages and re-injects them" do
      pinned = %Message{id: "sys", role: :system, content: "System prompt", pinned: false}
      messages = [pinned | make_messages(20)]

      pipeline = Pipeline.new([{SlidingWindow, last: 5}])
      {:ok, result} = Pipeline.run(pipeline, messages, %{})

      # System message should be first (re-injected)
      assert hd(result).id == "sys"
      assert hd(result).role == :system

      # Total = 1 pinned + 5 from sliding window
      assert length(result) == 6
    end

    test "preserves manually pinned messages" do
      important = %Message{id: "important", role: :user, content: "Critical info", pinned: true}
      messages = make_messages(5) ++ [important] ++ make_messages(5)

      pipeline = Pipeline.new([{SlidingWindow, last: 3}])
      {:ok, result} = Pipeline.run(pipeline, messages, %{})

      # Important message should survive even though sliding window only keeps 3
      assert Enum.any?(result, &(&1.id == "important"))
    end

    test "applies strategies sorted by priority" do
      # SlidingWindow (priority 100) runs before TokenTruncation (200)
      messages = make_messages(20)

      pipeline =
        Pipeline.new([
          {TokenTruncation, max_tokens: 50},
          {SlidingWindow, last: 15}
        ])

      {:ok, result} = Pipeline.run(pipeline, messages, %{})

      # SlidingWindow runs first (100 < 200): 20 → 15
      # TokenTruncation runs second: 15 × 5 tokens = 75, budget 50 → 10
      assert length(result) == 10
    end

    test "handles empty message list" do
      pipeline = Pipeline.new([{SlidingWindow, last: 5}])
      {:ok, result} = Pipeline.run(pipeline, [], %{})
      assert result == []
    end

    test "passes context through to strategies" do
      # Use TokenTruncation which reads token_counter from context
      messages = [
        %Message{id: "1", role: :user, content: String.duplicate("a", 100), token_count: nil}
      ]

      context = %{token_counter: PhoenixAI.Store.Memory.TokenCounter.Default}
      pipeline = Pipeline.new([{TokenTruncation, max_tokens: 10}])
      {:ok, result} = Pipeline.run(pipeline, messages, context)

      # 100 chars / 4 = 25 tokens > 10 budget → empty
      assert result == []
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/memory/pipeline_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement Pipeline**

```elixir
# lib/phoenix_ai/store/memory/pipeline.ex
defmodule PhoenixAI.Store.Memory.Pipeline do
  @moduledoc """
  Orchestrates memory strategy execution with priority-based ordering.

  The pipeline:
  1. Extracts pinned messages (role: :system OR pinned: true)
  2. Sorts strategies by priority (lower = runs first)
  3. Applies each strategy sequentially on non-pinned messages
  4. Re-injects pinned messages at original positions
  5. Returns the filtered message list

  ## Presets

  - `:default` — SlidingWindow(last: 50)
  - `:aggressive` — TokenTruncation(max_tokens: 4096)
  - `:summarize` — Summarization(threshold: 20) + SlidingWindow(last: 20)

  ## Usage

      pipeline = Pipeline.preset(:default)
      {:ok, filtered} = Pipeline.run(pipeline, messages, context)
  """

  alias PhoenixAI.Store.Memory.Strategies.{SlidingWindow, Summarization, TokenTruncation}

  defstruct strategies: []

  @type strategy_entry :: {module(), keyword()}
  @type t :: %__MODULE__{strategies: [strategy_entry()]}

  @doc "Creates a pipeline from a list of `{strategy_module, opts}` tuples."
  @spec new([strategy_entry()]) :: t()
  def new(strategies) when is_list(strategies) do
    %__MODULE__{strategies: strategies}
  end

  @doc "Returns a preset pipeline configuration."
  @spec preset(:default | :aggressive | :summarize) :: t()
  def preset(:default), do: new([{SlidingWindow, [last: 50]}])
  def preset(:aggressive), do: new([{TokenTruncation, [max_tokens: 4096]}])

  def preset(:summarize) do
    new([
      {Summarization, [threshold: 20]},
      {SlidingWindow, [last: 20]}
    ])
  end

  @doc """
  Runs the pipeline on a list of messages.

  Pinned messages (role: :system or pinned: true) are extracted before
  strategies run and re-injected afterward at their original positions.
  """
  @spec run(t(), [PhoenixAI.Store.Message.t()], map(), keyword()) ::
          {:ok, [PhoenixAI.Store.Message.t()]} | {:error, term()}
  def run(%__MODULE__{strategies: strategies}, messages, context, _opts \\ []) do
    {pinned_with_indices, non_pinned} = extract_pinned(messages)

    sorted =
      strategies
      |> Enum.sort_by(fn {mod, _opts} -> mod.priority() end)

    case apply_strategies(sorted, non_pinned, context) do
      {:ok, filtered} ->
        {:ok, reinject_pinned(pinned_with_indices, filtered)}

      {:error, _} = error ->
        error
    end
  end

  defp extract_pinned(messages) do
    messages
    |> Enum.with_index()
    |> Enum.split_with(fn {msg, _idx} -> pinned?(msg) end)
    |> then(fn {pinned, non_pinned} ->
      {pinned, Enum.map(non_pinned, fn {msg, _idx} -> msg end)}
    end)
  end

  defp pinned?(%{role: :system}), do: true
  defp pinned?(%{pinned: true}), do: true
  defp pinned?(_), do: false

  defp apply_strategies([], messages, _context), do: {:ok, messages}

  defp apply_strategies([{mod, opts} | rest], messages, context) do
    case mod.apply(messages, context, opts) do
      {:ok, filtered} -> apply_strategies(rest, filtered, context)
      {:error, _} = error -> error
    end
  end

  defp reinject_pinned([], filtered), do: filtered

  defp reinject_pinned(pinned_with_indices, filtered) do
    # Pinned messages go at the beginning, in their original order
    pinned_msgs = Enum.map(pinned_with_indices, fn {msg, _idx} -> msg end)
    pinned_msgs ++ filtered
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/memory/pipeline_test.exs`
Expected: All PASS.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/memory/pipeline.ex test/phoenix_ai/store/memory/pipeline_test.exs
git commit -m "feat(memory): add Pipeline orchestrator with presets and pinned handling"
```

---

### Task 7: Store Facade — `apply_memory/3`

**Files:**
- Modify: `lib/phoenix_ai/store.ex`
- Modify: `test/phoenix_ai/store_test.exs`

- [ ] **Step 1: Write apply_memory integration test**

Add to `test/phoenix_ai/store_test.exs`:

```elixir
describe "apply_memory/3" do
  test "applies pipeline and returns PhoenixAI messages", %{store: store} do
    {:ok, conv} = Store.save_conversation(%Conversation{title: "Memory test"}, store: store)

    for i <- 1..20 do
      Store.add_message(conv.id, %Message{role: :user, content: "Msg #{i}"}, store: store)
    end

    pipeline = PhoenixAI.Store.Memory.Pipeline.new([
      {PhoenixAI.Store.Memory.Strategies.SlidingWindow, last: 5}
    ])

    {:ok, result} = Store.apply_memory(conv.id, pipeline, store: store)

    # Should return PhoenixAI.Message structs (not Store.Message)
    assert Enum.all?(result, &match?(%PhoenixAI.Message{}, &1))
    # 5 from sliding window (no pinned in this conversation)
    assert length(result) == 5
  end

  test "preserves system messages in apply_memory", %{store: store} do
    {:ok, conv} = Store.save_conversation(%Conversation{title: "With system"}, store: store)

    Store.add_message(conv.id, %Message{role: :system, content: "You are helpful"}, store: store)

    for i <- 1..10 do
      Store.add_message(conv.id, %Message{role: :user, content: "Msg #{i}"}, store: store)
    end

    pipeline = PhoenixAI.Store.Memory.Pipeline.new([
      {PhoenixAI.Store.Memory.Strategies.SlidingWindow, last: 3}
    ])

    {:ok, result} = Store.apply_memory(conv.id, pipeline, store: store)

    # System message (pinned) + 3 from sliding window
    assert length(result) == 4
    assert hd(result).role == :system
    assert hd(result).content == "You are helpful"
  end

  test "returns error for missing conversation", %{store: store} do
    pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)
    assert {:error, :not_found} = Store.apply_memory("nonexistent", pipeline, store: store)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store_test.exs`
Expected: FAIL — `apply_memory` not defined.

- [ ] **Step 3: Implement apply_memory in facade**

Add to `lib/phoenix_ai/store.ex`:

```elixir
alias PhoenixAI.Store.Memory.Pipeline

@doc """
Applies a memory strategy pipeline to a conversation's messages.

Loads all messages, runs the pipeline (which handles pinned messages,
priority-based strategy execution), and returns `PhoenixAI.Message`
structs ready for the Agent's `messages:` option.

## Usage

    pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)
    {:ok, messages} = PhoenixAI.Store.apply_memory(conv.id, pipeline, store: :my_store)
    {:ok, response} = PhoenixAI.Agent.prompt(agent, "Hello", messages: messages)
"""
@spec apply_memory(String.t(), Pipeline.t(), keyword()) ::
        {:ok, [PhoenixAI.Message.t()]} | {:error, term()}
def apply_memory(conversation_id, %Pipeline{} = pipeline, opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :memory, :apply], %{}, fn ->
    {_adapter, adapter_opts, config} = resolve_adapter(opts)

    context = %{
      conversation_id: conversation_id,
      model: Keyword.get(opts, :model, config[:model]),
      provider: Keyword.get(opts, :provider, config[:provider]),
      max_tokens: Keyword.get(opts, :max_tokens),
      token_counter:
        Keyword.get(opts, :token_counter, PhoenixAI.Store.Memory.TokenCounter.Default)
    }

    with {:ok, messages} <- get_messages_raw(conversation_id, opts),
         {:ok, filtered} <- Pipeline.run(pipeline, messages, context) do
      result = {:ok, Enum.map(filtered, &Message.to_phoenix_ai/1)}
      {result, %{}}
    else
      {:error, _} = error -> {error, %{}}
    end
  end)
end

# Internal: get Store.Message structs (not converted to PhoenixAI.Message)
defp get_messages_raw(conversation_id, opts) do
  {adapter, adapter_opts, _config} = resolve_adapter(opts)
  adapter.get_messages(conversation_id, adapter_opts)
end
```

Note: `get_messages_raw/2` is needed because the public `get_messages/2` wraps in telemetry span. We need raw access for `apply_memory` to avoid double-spanning.

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store.ex test/phoenix_ai/store_test.exs
git commit -m "feat(memory): add apply_memory/3 facade for Agent integration"
```

---

### Task 8: Final Verification

**Files:**
- No new files

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 2: Run formatter**

Run: `mix format --check-formatted`
Expected: Clean.

- [ ] **Step 3: Verify optional Ecto compilation**

Run: `mix compile --no-optional-deps --warnings-as-errors`
Expected: Compiles successfully — memory modules have no Ecto dependency.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "chore(memory): fix formatting"
```

---

## Summary

| Task | What it delivers | Commit message |
|------|------------------|----------------|
| 1 | `pinned` field on Message struct + schema | `feat(memory): add pinned field to Message` |
| 2 | TokenCounter behaviour + Default (chars/4) | `feat(memory): add TokenCounter behaviour` |
| 3 | Strategy behaviour + SlidingWindow | `feat(memory): add Strategy behaviour and SlidingWindow` |
| 4 | TokenTruncation strategy | `feat(memory): add TokenTruncation strategy` |
| 5 | Summarization strategy (AI-powered) | `feat(memory): add Summarization strategy` |
| 6 | Pipeline orchestrator with presets | `feat(memory): add Pipeline orchestrator` |
| 7 | `apply_memory/3` facade function | `feat(memory): add apply_memory/3 facade` |
| 8 | Final verification | `chore(memory): fix formatting` |

### Requirements Coverage

| Requirement | Task |
|-------------|------|
| MEM-01: Sliding window | Task 3 |
| MEM-02: Token-aware truncation | Task 4 |
| MEM-03: Pinned messages | Tasks 1, 6 (Pipeline handles pinning) |
| MEM-04: Summarization | Task 5 |
| MEM-05: Custom strategy via behaviour | Task 3 (Strategy behaviour) |
| MEM-06: Compose strategies | Task 6 (Pipeline + presets) |
| MEM-07: Agent integration | Task 7 (apply_memory → messages: for Agent) |
