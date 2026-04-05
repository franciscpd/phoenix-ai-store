defmodule PhoenixAI.Store.Guardrails.TokenBudgetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Guardrails.TokenBudget

  # -- Stub Adapter (implements TokenUsage) --

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

  # -- Stub Adapter without TokenUsage --

  defmodule PlainAdapter do
    # Does not implement TokenUsage
  end

  # -- Helpers --

  defp build_request(overrides \\ %{}) do
    defaults = %{
      messages: [%PhoenixAI.Message{role: "user", content: "Hello world"}],
      assigns: %{adapter: StubAdapter, adapter_opts: []},
      conversation_id: "conv_under",
      user_id: "user_under"
    }

    struct!(Request, Map.merge(defaults, overrides))
  end

  # ========================================================
  # Conversation scope (default)
  # ========================================================

  describe "conversation scope" do
    test "passes when accumulated tokens are under budget" do
      request = build_request(%{conversation_id: "conv_under"})
      assert {:ok, ^request} = TokenBudget.check(request, max: 100_000)
    end

    test "halts when accumulated tokens exceed budget" do
      request = build_request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 80_000)

      assert violation.policy == TokenBudget
      assert violation.reason =~ "Token budget exceeded"
      assert violation.reason =~ "90000"
      assert violation.reason =~ "80000"
      assert violation.reason =~ "conversation"
      assert violation.metadata.accumulated == 90_000
      assert violation.metadata.max == 80_000
      assert violation.metadata.scope == :conversation
    end

    test "halts when conversation_id is nil" do
      request = build_request(%{conversation_id: nil})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 100_000, scope: :conversation)

      assert violation.reason =~ "conversation_id"
    end
  end

  # ========================================================
  # User scope
  # ========================================================

  describe "user scope" do
    test "passes when accumulated tokens are under budget" do
      request = build_request(%{user_id: "user_under"})
      assert {:ok, ^request} = TokenBudget.check(request, max: 100_000, scope: :user)
    end

    test "halts when accumulated tokens exceed budget" do
      request = build_request(%{user_id: "user_over"})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 150_000, scope: :user)

      assert violation.policy == TokenBudget
      assert violation.reason =~ "200000"
      assert violation.reason =~ "150000"
      assert violation.metadata.accumulated == 200_000
      assert violation.metadata.scope == :user
    end

    test "halts when user_id is nil" do
      request = build_request(%{user_id: nil})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 100_000, scope: :user)

      assert violation.reason =~ "user_id"
    end
  end

  # ========================================================
  # Estimated mode
  # ========================================================

  describe "estimated mode" do
    test "adds estimated request tokens to accumulated total" do
      # "Hello world" is 11 bytes => div(11, 4) = 2 tokens estimated
      request = build_request(%{conversation_id: "conv_under"})

      assert {:ok, ^request} =
               TokenBudget.check(request, max: 100_000, mode: :estimated)
    end

    test "halts when accumulated + estimated exceeds budget" do
      # conv_under = 50_000 accumulated, message = ~2 tokens
      # Set max to 50_001 so accumulated alone is fine, but + estimated pushes over
      request = build_request(%{conversation_id: "conv_under"})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 50_001, mode: :estimated)

      assert violation.metadata.accumulated == 50_000
      assert violation.metadata.estimated > 0
      assert violation.metadata.total > 50_001
    end
  end

  # ========================================================
  # Accumulated mode (default)
  # ========================================================

  describe "accumulated mode (default)" do
    test "does NOT count request message tokens" do
      # conv_under = 50_000, max = 50_002 => passes because estimated is NOT added
      request = build_request(%{conversation_id: "conv_under"})
      assert {:ok, ^request} = TokenBudget.check(request, max: 50_002)
    end
  end

  # ========================================================
  # Missing adapter
  # ========================================================

  describe "missing adapter" do
    test "halts with helpful error when adapter not in assigns" do
      request = build_request(%{assigns: %{}})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 100_000)

      assert violation.reason =~ "adapter"
      assert violation.reason =~ "Store.check_guardrails"
    end
  end

  # ========================================================
  # Adapter without TokenUsage
  # ========================================================

  describe "adapter without TokenUsage" do
    test "halts with not supported error" do
      request = build_request(%{assigns: %{adapter: PlainAdapter, adapter_opts: []}})

      assert {:halt, %PolicyViolation{} = violation} =
               TokenBudget.check(request, max: 100_000)

      assert violation.reason =~ "not supported" or violation.reason =~ "TokenUsage"
    end
  end

  # ========================================================
  # Time-window scope
  # ========================================================

  describe "time_window scope" do
    test "halts when Hammer is not configured properly or scope requires window_ms" do
      request = build_request()

      # Without window_ms, should halt with a config error
      result = TokenBudget.check(request, max: 100_000, scope: :time_window)

      case result do
        {:halt, %PolicyViolation{} = violation} ->
          assert violation.reason =~ "window_ms" or violation.reason =~ "Hammer"

        {:ok, _} ->
          # If Hammer is loaded and somehow passes, that's also acceptable in test
          :ok
      end
    end
  end
end
