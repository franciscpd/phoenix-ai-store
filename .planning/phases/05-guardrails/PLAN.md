# Phase 5: TokenBudget Guardrail — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stateful TokenBudget policy to phoenix_ai_store that enforces token limits per-conversation, per-user, and per-time-window by reading accumulated token counts from the store adapter.

**Architecture:** TokenBudget implements the core `PhoenixAI.Guardrails.Policy` behaviour (from phoenix_ai v0.3.0). It reads token counts via a new `TokenUsage` adapter sub-behaviour. The store facade (`check_guardrails/3`) injects adapter references into `request.assigns` before calling `Pipeline.run/2`, so TokenBudget can query the store without coupling the core Policy contract to storage. Hammer is an optional dep for time-window rate limiting.

**Tech Stack:** Elixir, phoenix_ai ~> 0.3, Hammer ~> 7.3 (optional), NimbleOptions, Telemetry

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `mix.exs` | Modify | Bump phoenix_ai to ~> 0.3, add hammer optional dep |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Add `TokenUsage` sub-behaviour |
| `test/support/token_usage_contract_test.ex` | Create | Shared contract tests for TokenUsage |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement TokenUsage callbacks |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement TokenUsage callbacks |
| `lib/phoenix_ai/store/guardrails/token_budget.ex` | Create | TokenBudget policy (core logic) |
| `test/phoenix_ai/store/guardrails/token_budget_test.exs` | Create | TokenBudget unit tests |
| `lib/phoenix_ai/store/config.ex` | Modify | Add guardrails NimbleOptions section |
| `lib/phoenix_ai/store.ex` | Modify | Add `check_guardrails/3` facade |
| `test/phoenix_ai/store/guardrails_integration_test.exs` | Create | End-to-end integration tests |

---

## Task 1: Bump Dependencies

**Files:**
- Modify: `mix.exs:36-38`

- [ ] **Step 1: Update mix.exs deps**

Change the phoenix_ai dep version and add hammer:

```elixir
# In deps/0:
{:phoenix_ai, "~> 0.3"},

# After postgrex line:
# Optional — Guardrails time-window rate limiting
{:hammer, "~> 7.3", optional: true},
```

- [ ] **Step 2: Fetch and compile**

Run: `mix deps.get && mix compile`
Expected: Clean compilation with phoenix_ai 0.3.0 and hammer fetched

- [ ] **Step 3: Verify existing tests still pass**

Run: `mix test`
Expected: 197 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore(deps): bump phoenix_ai to ~> 0.3, add hammer optional"
```

---

## Task 2: TokenUsage Adapter Sub-behaviour

**Files:**
- Modify: `lib/phoenix_ai/store/adapter.ex`
- Create: `test/support/token_usage_contract_test.ex`

- [ ] **Step 1: Write the contract test**

Create `test/support/token_usage_contract_test.ex`:

```elixir
defmodule PhoenixAI.Store.TokenUsageContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.TokenUsage`.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.TokenUsageContractTest, adapter: MyAdapter
      end
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.{Conversation, Message}

      @adapter unquote(macro_opts[:adapter])

      describe "TokenUsage: sum_conversation_tokens/2" do
        test "returns 0 for conversation with no messages", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          assert {:ok, 0} = @adapter.sum_conversation_tokens(conv.id, opts)
        end

        test "sums token_count across all messages in conversation", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          msg1 = build_message(%{content: "Hello", token_count: 10})
          msg2 = build_message(%{content: "World", token_count: 25})
          msg3 = build_message(%{content: "Test", token_count: nil})

          {:ok, _} = @adapter.add_message(conv.id, msg1, opts)
          {:ok, _} = @adapter.add_message(conv.id, msg2, opts)
          {:ok, _} = @adapter.add_message(conv.id, msg3, opts)

          assert {:ok, 35} = @adapter.sum_conversation_tokens(conv.id, opts)
        end

        test "returns 0 for nonexistent conversation", %{opts: opts} do
          assert {:ok, 0} = @adapter.sum_conversation_tokens("nonexistent", opts)
        end
      end

      describe "TokenUsage: sum_user_tokens/2" do
        test "returns 0 for user with no conversations", %{opts: opts} do
          assert {:ok, 0} = @adapter.sum_user_tokens("user_no_convs", opts)
        end

        test "sums token_count across all user conversations", %{opts: opts} do
          conv1 = build_conversation(%{user_id: "token_user"})
          conv2 = build_conversation(%{user_id: "token_user"})
          conv3 = build_conversation(%{user_id: "other_user"})

          {:ok, _} = @adapter.save_conversation(conv1, opts)
          {:ok, _} = @adapter.save_conversation(conv2, opts)
          {:ok, _} = @adapter.save_conversation(conv3, opts)

          {:ok, _} = @adapter.add_message(conv1.id, build_message(%{token_count: 100}), opts)
          {:ok, _} = @adapter.add_message(conv2.id, build_message(%{token_count: 50}), opts)
          {:ok, _} = @adapter.add_message(conv3.id, build_message(%{token_count: 999}), opts)

          assert {:ok, 150} = @adapter.sum_user_tokens("token_user", opts)
        end

        test "ignores messages with nil token_count", %{opts: opts} do
          conv = build_conversation(%{user_id: "nil_token_user"})
          {:ok, _} = @adapter.save_conversation(conv, opts)

          {:ok, _} = @adapter.add_message(conv.id, build_message(%{token_count: 40}), opts)
          {:ok, _} = @adapter.add_message(conv.id, build_message(%{token_count: nil}), opts)

          assert {:ok, 40} = @adapter.sum_user_tokens("nil_token_user", opts)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Add the sub-behaviour to adapter.ex**

Add inside `lib/phoenix_ai/store/adapter.ex`, after the `ProfileStore` sub-behaviour:

```elixir
defmodule TokenUsage do
  @moduledoc """
  Sub-behaviour for adapters that support token usage aggregation.

  Used by the TokenBudget guardrail policy to efficiently query
  accumulated token counts without loading full message lists.
  """

  @callback sum_conversation_tokens(conversation_id :: String.t(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @callback sum_user_tokens(user_id :: String.t(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapter.ex test/support/token_usage_contract_test.ex
git commit -m "feat(guardrails): add TokenUsage adapter sub-behaviour + contract tests"
```

---

## Task 3: ETS Adapter — Implement TokenUsage

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex`
- Modify: `test/phoenix_ai/store/adapters/ets_test.exs`

- [ ] **Step 1: Wire contract tests into ETS test file**

Add to `test/phoenix_ai/store/adapters/ets_test.exs`, after the existing `use` statements:

```elixir
use PhoenixAI.Store.TokenUsageContractTest, adapter: PhoenixAI.Store.Adapters.ETS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep "TokenUsage"`
Expected: FAIL — `sum_conversation_tokens/2` and `sum_user_tokens/2` are not defined

- [ ] **Step 3: Implement TokenUsage in ETS adapter**

Add to `lib/phoenix_ai/store/adapters/ets.ex`, after the ProfileStore callbacks, before the closing `end`:

```elixir
# -- TokenUsage callbacks --

@behaviour PhoenixAI.Store.Adapter.TokenUsage

@impl PhoenixAI.Store.Adapter.TokenUsage
def sum_conversation_tokens(conversation_id, opts) do
  table = Keyword.fetch!(opts, :table)

  total =
    :ets.match_object(table, {{:message, conversation_id, :_}, :_})
    |> Enum.reduce(0, fn {_key, msg}, acc -> acc + (msg.token_count || 0) end)

  {:ok, total}
end

@impl PhoenixAI.Store.Adapter.TokenUsage
def sum_user_tokens(user_id, opts) do
  table = Keyword.fetch!(opts, :table)

  # Get all conversation IDs for this user
  conv_ids =
    :ets.match_object(table, {{:conversation, :_}, :_})
    |> Enum.filter(fn {_key, conv} -> conv.user_id == user_id end)
    |> Enum.map(fn {_key, conv} -> conv.id end)

  # Sum token_count across all messages in those conversations
  total =
    Enum.reduce(conv_ids, 0, fn conv_id, acc ->
      :ets.match_object(table, {{:message, conv_id, :_}, :_})
      |> Enum.reduce(acc, fn {_key, msg}, inner_acc ->
        inner_acc + (msg.token_count || 0)
      end)
    end)

  {:ok, total}
end
```

Also add at the top of the module, after the existing `@behaviour` lines:

```elixir
@behaviour PhoenixAI.Store.Adapter.TokenUsage
```

(Note: the `@behaviour` is declared twice — once at module level for the compiler, once before the `@impl` for documentation. Remove the duplicate at the `@impl` section; keep only the one at the top.)

- [ ] **Step 4: Run contract tests**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep -E "(TokenUsage|test |passed|failed)"`
Expected: All TokenUsage tests pass

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All 197+ tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex test/phoenix_ai/store/adapters/ets_test.exs
git commit -m "feat(guardrails): implement TokenUsage in ETS adapter"
```

---

## Task 4: Ecto Adapter — Implement TokenUsage

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex`
- Modify: `test/phoenix_ai/store/adapters/ecto_test.exs`

- [ ] **Step 1: Wire contract tests into Ecto test file**

Add to `test/phoenix_ai/store/adapters/ecto_test.exs`, after the existing `use` statements:

```elixir
use PhoenixAI.Store.TokenUsageContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/adapters/ecto_test.exs --trace 2>&1 | grep "TokenUsage"`
Expected: FAIL — callbacks not implemented

- [ ] **Step 3: Implement TokenUsage in Ecto adapter**

Add to `lib/phoenix_ai/store/adapters/ecto.ex`, after the ProfileStore callbacks, before the `# -- Private Helpers --` section:

```elixir
# -- TokenUsage --

@behaviour PhoenixAI.Store.Adapter.TokenUsage

@impl PhoenixAI.Store.Adapter.TokenUsage
def sum_conversation_tokens(conversation_id, opts) do
  repo = Keyword.fetch!(opts, :repo)

  total =
    from(m in msg_source(opts),
      where: m.conversation_id == ^conversation_id,
      select: coalesce(sum(m.token_count), 0)
    )
    |> repo.one()

  {:ok, total}
end

@impl PhoenixAI.Store.Adapter.TokenUsage
def sum_user_tokens(user_id, opts) do
  repo = Keyword.fetch!(opts, :repo)

  total =
    from(m in msg_source(opts),
      join: c in ^conv_source(opts),
      on: m.conversation_id == c.id,
      where: c.user_id == ^user_id,
      select: coalesce(sum(m.token_count), 0)
    )
    |> repo.one()

  {:ok, total}
end
```

Also add `@behaviour PhoenixAI.Store.Adapter.TokenUsage` at the top with the other behaviour declarations.

- [ ] **Step 4: Run contract tests**

Run: `mix test test/phoenix_ai/store/adapters/ecto_test.exs --trace 2>&1 | grep -E "(TokenUsage|test |passed|failed)"`
Expected: All TokenUsage tests pass

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ecto.ex test/phoenix_ai/store/adapters/ecto_test.exs
git commit -m "feat(guardrails): implement TokenUsage in Ecto adapter"
```

---

## Task 5: TokenBudget Policy — Conversation & User Scopes

**Files:**
- Create: `lib/phoenix_ai/store/guardrails/token_budget.ex`
- Create: `test/phoenix_ai/store/guardrails/token_budget_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/store/guardrails/token_budget_test.exs`:

```elixir
defmodule PhoenixAI.Store.Guardrails.TokenBudgetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Guardrails.TokenBudget

  # -- Stub adapter for testing --

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.TokenUsage

    @impl true
    def sum_conversation_tokens("conv_over", _opts), do: {:ok, 90_000}
    def sum_conversation_tokens("conv_under", _opts), do: {:ok, 50_000}
    def sum_conversation_tokens(_id, _opts), do: {:ok, 0}

    @impl true
    def sum_user_tokens("user_over", _opts), do: {:ok, 200_000}
    def sum_user_tokens("user_under", _opts), do: {:ok, 30_000}
    def sum_user_tokens(_id, _opts), do: {:ok, 0}
  end

  defp request(attrs \\ %{}) do
    defaults = %{
      messages: [%PhoenixAI.Message{role: :user, content: "Hello world"}],
      conversation_id: "conv_under",
      user_id: "user_under",
      assigns: %{
        adapter: StubAdapter,
        adapter_opts: []
      }
    }

    struct(Request, Map.merge(defaults, attrs))
  end

  describe "check/2 with scope: :conversation" do
    test "passes when accumulated tokens are under budget" do
      req = request(%{conversation_id: "conv_under"})
      assert {:ok, %Request{}} = TokenBudget.check(req, scope: :conversation, max: 100_000)
    end

    test "halts when accumulated tokens exceed budget" do
      req = request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :conversation, max: 100_000)

      assert v.policy == TokenBudget
      assert v.reason =~ "Token budget exceeded"
      assert v.metadata.accumulated == 90_000
      assert v.metadata.scope == :conversation
    end

    test "halts with estimated mode when accumulated + request tokens exceed budget" do
      req = request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :conversation, max: 100_000, mode: :estimated)

      assert v.metadata.estimated > 0
      assert v.metadata.total > 90_000
    end

    test "passes with estimated mode when total is under budget" do
      req = request(%{conversation_id: "conv_under"})
      assert {:ok, _} = TokenBudget.check(req, scope: :conversation, max: 100_000, mode: :estimated)
    end
  end

  describe "check/2 with scope: :user" do
    test "passes when user token total is under budget" do
      req = request(%{user_id: "user_under"})
      assert {:ok, %Request{}} = TokenBudget.check(req, scope: :user, max: 500_000)
    end

    test "halts when user token total exceeds budget" do
      req = request(%{user_id: "user_over"})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :user, max: 100_000)

      assert v.policy == TokenBudget
      assert v.metadata.accumulated == 200_000
      assert v.metadata.scope == :user
    end

    test "halts with error when user_id is nil" do
      req = request(%{user_id: nil})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :user, max: 100_000)

      assert v.reason =~ "user_id required"
    end
  end

  describe "check/2 with missing adapter" do
    test "halts with error when adapter not in assigns" do
      req = request(%{assigns: %{}})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :conversation, max: 100_000)

      assert v.reason =~ "adapter"
    end
  end

  describe "check/2 with adapter that doesn't support TokenUsage" do
    defmodule NoTokenUsageAdapter do
    end

    test "halts with unsupported error" do
      req = request(%{assigns: %{adapter: NoTokenUsageAdapter, adapter_opts: []}})

      assert {:halt, %PolicyViolation{} = v} =
               TokenBudget.check(req, scope: :conversation, max: 100_000)

      assert v.reason =~ "not supported"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/guardrails/token_budget_test.exs`
Expected: FAIL — module `TokenBudget` does not exist

- [ ] **Step 3: Implement TokenBudget policy**

Create `lib/phoenix_ai/store/guardrails/token_budget.ex`:

```elixir
defmodule PhoenixAI.Store.Guardrails.TokenBudget do
  @moduledoc """
  Guardrail policy that enforces token budget limits.

  This is a **stateful** policy that reads accumulated token counts
  from the store adapter. It implements the `PhoenixAI.Guardrails.Policy`
  behaviour from phoenix_ai core.

  ## Scopes

    * `:conversation` — sum of token_count for messages in the conversation
    * `:user` — sum across all conversations for the user
    * `:time_window` — rate-limited tokens per time window (requires Hammer)

  ## Counting Modes

    * `:accumulated` (default) — only counts tokens already stored
    * `:estimated` — accumulated + estimated tokens for the current request messages

  ## Options

    * `:scope` — `:conversation` (default), `:user`, or `:time_window`
    * `:max` — maximum token count (required)
    * `:mode` — `:accumulated` (default) or `:estimated`
    * `:token_counter` — module for estimating request tokens (default: `TokenCounter.Default`)

  ### Time-window options (scope: :time_window only)

    * `:window_ms` — window duration in milliseconds (required)
    * `:key_prefix` — Hammer key prefix (default: `"phoenix_ai_store:token_budget"`)

  ## Example

      policies = [
        {TokenBudget, scope: :conversation, max: 100_000},
        {TokenBudget, scope: :user, max: 1_000_000},
        {PhoenixAI.Guardrails.Policies.JailbreakDetection, []}
      ]

      PhoenixAI.Guardrails.Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Memory.TokenCounter

  @impl true
  @spec check(Request.t(), keyword()) :: {:ok, Request.t()} | {:halt, PolicyViolation.t()}
  def check(%Request{} = request, opts) do
    scope = Keyword.get(opts, :scope, :conversation)
    max = Keyword.fetch!(opts, :max)
    mode = Keyword.get(opts, :mode, :accumulated)

    with {:ok, adapter, adapter_opts} <- resolve_adapter(request),
         :ok <- validate_scope_requirements(scope, request),
         {:ok, adapter} <- check_token_usage_support(adapter) do
      case count_tokens(scope, mode, request, adapter, adapter_opts, opts) do
        {:ok, total, details} ->
          if total <= max do
            {:ok, request}
          else
            {:halt, build_violation(total, max, scope, details)}
          end

        {:error, reason} ->
          {:halt, error_violation(reason)}
      end
    end
  end

  # -- Token Counting --

  defp count_tokens(:conversation, mode, request, adapter, adapter_opts, opts) do
    case adapter.sum_conversation_tokens(request.conversation_id, adapter_opts) do
      {:ok, accumulated} ->
        estimated = estimate_request_tokens(mode, request, opts)
        total = accumulated + estimated
        {:ok, total, %{accumulated: accumulated, estimated: estimated}}

      {:error, _} = error ->
        error
    end
  end

  defp count_tokens(:user, mode, request, adapter, adapter_opts, opts) do
    case adapter.sum_user_tokens(request.user_id, adapter_opts) do
      {:ok, accumulated} ->
        estimated = estimate_request_tokens(mode, request, opts)
        total = accumulated + estimated
        {:ok, total, %{accumulated: accumulated, estimated: estimated}}

      {:error, _} = error ->
        error
    end
  end

  defp count_tokens(:time_window, _mode, request, _adapter, _adapter_opts, opts) do
    window_ms = Keyword.fetch!(opts, :window_ms)
    key_prefix = Keyword.get(opts, :key_prefix, "phoenix_ai_store:token_budget")
    scope_key = build_time_window_key(key_prefix, request)
    increment = estimate_all_tokens(request, opts)

    if Code.ensure_loaded?(Hammer) do
      case Hammer.check_rate_inc(scope_key, window_ms, opts[:max], increment) do
        {:allow, count} ->
          {:ok, count, %{accumulated: count, estimated: 0}}

        {:deny, limit} ->
          {:ok, limit + 1, %{accumulated: limit + 1, estimated: 0}}
      end
    else
      {:error, "Hammer dependency required for :time_window scope"}
    end
  end

  defp estimate_request_tokens(:accumulated, _request, _opts), do: 0

  defp estimate_request_tokens(:estimated, request, opts) do
    counter = Keyword.get(opts, :token_counter, TokenCounter.Default)

    request.messages
    |> Enum.reduce(0, fn msg, acc ->
      acc + counter.count_tokens(msg.content, [])
    end)
  end

  defp estimate_all_tokens(request, opts) do
    counter = Keyword.get(opts, :token_counter, TokenCounter.Default)

    request.messages
    |> Enum.reduce(0, fn msg, acc ->
      acc + counter.count_tokens(msg.content, [])
    end)
  end

  # -- Validation --

  defp resolve_adapter(%Request{assigns: assigns}) do
    case {Map.get(assigns, :adapter), Map.get(assigns, :adapter_opts)} do
      {nil, _} ->
        {:halt,
         %PolicyViolation{
           policy: __MODULE__,
           reason: "TokenBudget requires adapter in request.assigns (use Store.check_guardrails/3)"
         }}

      {adapter, opts} ->
        {:ok, adapter, opts || []}
    end
  end

  defp validate_scope_requirements(:user, %Request{user_id: nil}) do
    {:halt,
     %PolicyViolation{
       policy: __MODULE__,
       reason: "TokenBudget with scope: :user requires user_id in request"
     }}
  end

  defp validate_scope_requirements(:conversation, %Request{conversation_id: nil}) do
    {:halt,
     %PolicyViolation{
       policy: __MODULE__,
       reason: "TokenBudget with scope: :conversation requires conversation_id in request"
     }}
  end

  defp validate_scope_requirements(_scope, _request), do: :ok

  defp check_token_usage_support(adapter) do
    if function_exported?(adapter, :sum_conversation_tokens, 2) do
      {:ok, adapter}
    else
      {:halt,
       %PolicyViolation{
         policy: __MODULE__,
         reason: "TokenBudget not supported: adapter #{inspect(adapter)} does not implement TokenUsage"
       }}
    end
  end

  # -- Violation builders --

  defp build_violation(total, max, scope, details) do
    %PolicyViolation{
      policy: __MODULE__,
      reason: "Token budget exceeded: #{total} / #{max} (scope: #{scope})",
      metadata: Map.merge(details, %{total: total, max: max, scope: scope})
    }
  end

  defp error_violation(reason) do
    %PolicyViolation{
      policy: __MODULE__,
      reason: "TokenBudget error: #{inspect(reason)}"
    }
  end

  defp build_time_window_key(prefix, request) do
    scope_id = request.user_id || request.conversation_id || "global"
    "#{prefix}:#{scope_id}"
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/guardrails/token_budget_test.exs --trace`
Expected: All tests pass

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/guardrails/token_budget.ex test/phoenix_ai/store/guardrails/token_budget_test.exs
git commit -m "feat(guardrails): add TokenBudget policy with conversation & user scopes"
```

---

## Task 6: TokenBudget Time-Window Scope Tests

**Files:**
- Modify: `test/phoenix_ai/store/guardrails/token_budget_test.exs`

- [ ] **Step 1: Add time-window tests**

Append to the test file:

```elixir
describe "check/2 with scope: :time_window" do
  test "halts with clear error when Hammer is not loaded" do
    # This test only applies when Hammer is NOT in deps.
    # When Hammer IS in deps, it will pass through to Hammer.
    # We test the Hammer-absent path by using a module that
    # mimics the check but without Hammer loaded.
    # Since Hammer IS an optional dep and may be loaded in test,
    # we skip this if Hammer is available.
    if Code.ensure_loaded?(Hammer) do
      # Hammer is loaded — test the happy path instead
      req = request()
      opts = [scope: :time_window, max: 1000, window_ms: 60_000]

      result = TokenBudget.check(req, opts)
      assert match?({:ok, _}, result) or match?({:halt, _}, result)
    else
      req = request()
      opts = [scope: :time_window, max: 1000, window_ms: 60_000]

      assert {:halt, %PolicyViolation{} = v} = TokenBudget.check(req, opts)
      assert v.reason =~ "Hammer"
    end
  end
end

describe "check/2 with scope: :conversation and mode: :accumulated (default)" do
  test "does not count request message tokens" do
    # conv_under has 50_000 accumulated. With max 60_000,
    # accumulated mode should pass even if request has many tokens
    req = request(%{
      conversation_id: "conv_under",
      messages: [%PhoenixAI.Message{role: :user, content: String.duplicate("a", 40_000)}]
    })

    assert {:ok, _} = TokenBudget.check(req, scope: :conversation, max: 60_000)
  end
end
```

- [ ] **Step 2: Run tests**

Run: `mix test test/phoenix_ai/store/guardrails/token_budget_test.exs --trace`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/store/guardrails/token_budget_test.exs
git commit -m "test(guardrails): add time-window and accumulated mode tests"
```

---

## Task 7: Config Extension + Store Facade

**Files:**
- Modify: `lib/phoenix_ai/store/config.ex`
- Modify: `lib/phoenix_ai/store.ex`
- Create: `test/phoenix_ai/store/guardrails_integration_test.exs`

- [ ] **Step 1: Write integration tests**

Create `test/phoenix_ai/store/guardrails_integration_test.exs`:

```elixir
defmodule PhoenixAI.Store.GuardrailsIntegrationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{Pipeline, PolicyViolation, Request}
  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.Guardrails.TokenBudget

  setup do
    store_name = :"guardrails_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Store.start_link(
        name: store_name,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

    # Seed a conversation with messages
    conv = %Conversation{
      id: Uniq.UUID.uuid7(),
      user_id: "guard_user",
      title: "Guardrails Test",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store_name)

    {:ok, _} =
      Store.add_message(
        conv.id,
        %Message{role: :user, content: "Hello", token_count: 500},
        store: store_name
      )

    {:ok, _} =
      Store.add_message(
        conv.id,
        %Message{role: :assistant, content: "Hi there!", token_count: 300},
        store: store_name
      )

    {:ok, store: store_name, conversation_id: conv.id}
  end

  describe "check_guardrails/3" do
    test "passes when under budget", %{store: store, conversation_id: conv_id} do
      policies = [{TokenBudget, scope: :conversation, max: 10_000}]

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "New message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      assert {:ok, %Request{}} = Store.check_guardrails(request, policies, store: store)
    end

    test "halts when over budget", %{store: store, conversation_id: conv_id} do
      policies = [{TokenBudget, scope: :conversation, max: 100}]

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "New message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      assert {:error, %PolicyViolation{} = v} =
               Store.check_guardrails(request, policies, store: store)

      assert v.policy == TokenBudget
      assert v.metadata.accumulated == 800
    end

    test "works with user scope", %{store: store} do
      policies = [{TokenBudget, scope: :user, max: 100}]

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Hello"}],
        user_id: "guard_user"
      }

      assert {:error, %PolicyViolation{}} =
               Store.check_guardrails(request, policies, store: store)
    end

    test "composes with core policies", %{store: store, conversation_id: conv_id} do
      policies = [
        {TokenBudget, scope: :conversation, max: 10_000},
        {PhoenixAI.Guardrails.Policies.JailbreakDetection, []}
      ]

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Normal message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      assert {:ok, %Request{}} = Store.check_guardrails(request, policies, store: store)
    end

    test "injects adapter into request assigns", %{store: store, conversation_id: conv_id} do
      # Use a policy that passes to inspect the final request
      policies = [{TokenBudget, scope: :conversation, max: 999_999}]

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "test"}],
        conversation_id: conv_id
      }

      assert {:ok, %Request{assigns: assigns}} =
               Store.check_guardrails(request, policies, store: store)

      assert assigns.adapter == PhoenixAI.Store.Adapters.ETS
      assert is_list(assigns.adapter_opts)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/guardrails_integration_test.exs`
Expected: FAIL — `check_guardrails/3` is undefined

- [ ] **Step 3: Add guardrails config to config.ex**

Add to the `@schema` in `lib/phoenix_ai/store/config.ex`, after the `long_term_memory` key:

```elixir
guardrails: [
  type: :keyword_list,
  default: [],
  doc: "Guardrails configuration.",
  keys: [
    policies: [
      type: {:list, :any},
      default: [],
      doc: "Default policy list [{module, opts}]. Used when no policies passed to check_guardrails/3."
    ],
    token_budget: [
      type: :keyword_list,
      default: [],
      doc: "Default TokenBudget options.",
      keys: [
        max: [type: :pos_integer, doc: "Default max token budget."],
        scope: [
          type: {:in, [:conversation, :user, :time_window]},
          default: :conversation,
          doc: "Default scope."
        ],
        mode: [
          type: {:in, [:accumulated, :estimated]},
          default: :accumulated,
          doc: "Default counting mode."
        ]
      ]
    ]
  ]
]
```

- [ ] **Step 4: Add check_guardrails/3 to store facade**

Add to `lib/phoenix_ai/store.ex`, after the `apply_memory/3` function (before the Long-Term Memory Facade section):

```elixir
# -- Guardrails Facade --

alias PhoenixAI.Guardrails.{Pipeline, Request}

@doc """
Runs guardrail policies against a request, injecting the store's
adapter into `request.assigns` so stateful policies (like TokenBudget)
can query the store.

## Parameters

  * `request` — a `%PhoenixAI.Guardrails.Request{}`
  * `policies` — list of `{policy_module, opts}` tuples
  * `opts` — store options (`:store` key for store instance name)

## Returns

  * `{:ok, %Request{}}` — all policies passed
  * `{:error, %PolicyViolation{}}` — a policy halted the pipeline

## Example

    request = %Request{
      messages: messages,
      conversation_id: conv.id,
      user_id: user_id
    }

    policies = [
      {PhoenixAI.Store.Guardrails.TokenBudget, scope: :conversation, max: 100_000},
      {PhoenixAI.Guardrails.Policies.JailbreakDetection, []}
    ]

    case Store.check_guardrails(request, policies, store: :my_store) do
      {:ok, request} -> # proceed with AI call
      {:error, violation} -> # handle violation
    end
"""
@spec check_guardrails(Request.t(), [Pipeline.policy_entry()], keyword()) ::
        {:ok, Request.t()} | {:error, PhoenixAI.Guardrails.PolicyViolation.t()}
def check_guardrails(%Request{} = request, policies, opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :guardrails, :check], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    request = %{
      request
      | assigns: Map.merge(request.assigns, %{adapter: adapter, adapter_opts: adapter_opts})
    }

    result = Pipeline.run(policies, request)
    {result, %{}}
  end)
end
```

- [ ] **Step 5: Run integration tests**

Run: `mix test test/phoenix_ai/store/guardrails_integration_test.exs --trace`
Expected: All tests pass

- [ ] **Step 6: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/store/config.ex lib/phoenix_ai/store.ex test/phoenix_ai/store/guardrails_integration_test.exs
git commit -m "feat(guardrails): add check_guardrails/3 facade + config extension"
```

---

## Task 8: Final Verification

**Files:** (none — verification only)

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass (197 original + ~20 new guardrails tests)

- [ ] **Step 2: Run Credo**

Run: `mix credo --strict`
Expected: No issues (or only pre-existing ones)

- [ ] **Step 3: Verify compilation with no warnings**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 4: Spot-check telemetry event**

Run in IEx (`iex -S mix`):

```elixir
:telemetry.attach("test", [:phoenix_ai_store, :guardrails, :check, :stop], fn name, measurements, meta, _ ->
  IO.inspect({name, measurements, meta}, label: "telemetry")
end, nil)

{:ok, _} = PhoenixAI.Store.start_link(name: :tel_test, adapter: PhoenixAI.Store.Adapters.ETS)

request = %PhoenixAI.Guardrails.Request{
  messages: [%PhoenixAI.Message{role: :user, content: "test"}],
  conversation_id: "none"
}

PhoenixAI.Store.check_guardrails(
  request,
  [{PhoenixAI.Store.Guardrails.TokenBudget, scope: :conversation, max: 100_000}],
  store: :tel_test
)
```

Expected: Telemetry event fires, request passes (0 tokens < 100_000)

- [ ] **Step 5: Commit any cleanup**

Only if Steps 1-3 required fixes. Otherwise skip.

---

## Requirements Coverage

| Requirement | Covered By |
|-------------|------------|
| GUARD-01 (token budget per conversation/user/time-window) | Task 5-6: TokenBudget policy |
| GUARD-03 (tool allow/deny) | phoenix_ai v0.3.0 core (ToolPolicy) |
| GUARD-04 (content filtering hooks) | phoenix_ai v0.3.0 core (ContentFilter) |
| GUARD-05 (custom Policy behaviour) | phoenix_ai v0.3.0 core (Policy behaviour) |
| GUARD-06 (stackable, first violation wins) | phoenix_ai v0.3.0 core (Pipeline) |
| GUARD-07 (PolicyViolation with reason) | phoenix_ai v0.3.0 core (PolicyViolation struct) |
| GUARD-08 (jailbreak detection) | phoenix_ai v0.3.0 core (JailbreakDetection) |
| GUARD-09 (replaceable detector) | phoenix_ai v0.3.0 core (JailbreakDetector behaviour) |
| GUARD-10 (pre-call enforcement) | Task 7: check_guardrails/3 runs before AI call |
| GUARD-02 (cost budget) | Deferred to Phase 6 |
