defmodule PhoenixAI.Store.Guardrails.CostBudgetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Guardrails.CostBudget

  # -- Stub Adapter (implements CostStore) --

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.CostStore

    @impl true
    def save_cost_record(r, _), do: {:ok, r}

    @impl true
    def list_cost_records(_, _), do: {:ok, %{records: [], next_cursor: nil}}

    @impl true
    def count_cost_records(_, _), do: {:ok, 0}

    @impl true
    def sum_cost(filters, _opts) do
      case Keyword.get(filters, :conversation_id) do
        "conv_over" ->
          {:ok, Decimal.new("15.00")}

        "conv_under" ->
          {:ok, Decimal.new("3.00")}

        _ ->
          case Keyword.get(filters, :user_id) do
            "user_over" -> {:ok, Decimal.new("100.00")}
            "user_under" -> {:ok, Decimal.new("5.00")}
            _ -> {:ok, Decimal.new("0")}
          end
      end
    end
  end

  # -- Stub Adapter without CostStore --

  defmodule PlainAdapter do
    # Does not implement CostStore
  end

  # -- Helpers --

  defp build_request(overrides \\ %{}) do
    defaults = %{
      messages: [%PhoenixAI.Message{role: :user, content: "Hello"}],
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
    test "passes when accumulated cost is under budget" do
      request = build_request(%{conversation_id: "conv_under"})
      assert {:ok, ^request} = CostBudget.check(request, max: "10.00")
    end

    test "halts when accumulated cost exceeds budget" do
      request = build_request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{} = violation} =
               CostBudget.check(request, max: "10.00")

      assert violation.policy == CostBudget
      assert violation.reason =~ "Cost budget exceeded"
      assert violation.reason =~ "$15.00"
      assert violation.reason =~ "$10.00"
      assert violation.reason =~ "conversation"
      assert Decimal.equal?(violation.metadata.accumulated, Decimal.new("15.00"))
      assert Decimal.equal?(violation.metadata.max, Decimal.new("10.00"))
      assert violation.metadata.scope == :conversation
    end
  end

  # ========================================================
  # User scope
  # ========================================================

  describe "user scope" do
    test "passes when accumulated cost is under budget" do
      request = build_request(%{user_id: "user_under"})
      assert {:ok, ^request} = CostBudget.check(request, max: "50.00", scope: :user)
    end

    test "halts when accumulated cost exceeds budget" do
      request = build_request(%{user_id: "user_over"})

      assert {:halt, %PolicyViolation{} = violation} =
               CostBudget.check(request, max: "50.00", scope: :user)

      assert violation.policy == CostBudget
      assert violation.reason =~ "$100.00"
      assert violation.reason =~ "$50.00"
      assert Decimal.equal?(violation.metadata.accumulated, Decimal.new("100.00"))
      assert Decimal.equal?(violation.metadata.max, Decimal.new("50.00"))
      assert violation.metadata.scope == :user
    end

    test "halts when user_id is nil" do
      request = build_request(%{user_id: nil})

      assert {:halt, %PolicyViolation{} = violation} =
               CostBudget.check(request, max: "10.00", scope: :user)

      assert violation.reason =~ "user_id"
    end
  end

  # ========================================================
  # Missing adapter
  # ========================================================

  describe "missing adapter" do
    test "halts with helpful error when adapter not in assigns" do
      request = build_request(%{assigns: %{}})

      assert {:halt, %PolicyViolation{} = violation} =
               CostBudget.check(request, max: "10.00")

      assert violation.reason =~ "adapter"
    end
  end

  # ========================================================
  # Unsupported adapter (no sum_cost)
  # ========================================================

  describe "unsupported adapter" do
    test "halts with error when adapter does not support CostStore" do
      request = build_request(%{assigns: %{adapter: PlainAdapter, adapter_opts: []}})

      assert {:halt, %PolicyViolation{} = violation} =
               CostBudget.check(request, max: "10.00")

      assert violation.reason =~ "CostStore" or violation.reason =~ "sum_cost"
    end
  end

  # ========================================================
  # Accepts both string and Decimal max
  # ========================================================

  describe "max option" do
    test "accepts string max" do
      request = build_request(%{conversation_id: "conv_under"})
      assert {:ok, ^request} = CostBudget.check(request, max: "10.00")
    end

    test "accepts Decimal max" do
      request = build_request(%{conversation_id: "conv_under"})
      assert {:ok, ^request} = CostBudget.check(request, max: Decimal.new("10.00"))
    end

    test "halts correctly with Decimal max" do
      request = build_request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{}} =
               CostBudget.check(request, max: Decimal.new("10.00"))
    end
  end
end
