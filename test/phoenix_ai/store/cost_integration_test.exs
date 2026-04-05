defmodule PhoenixAI.Store.CostIntegrationTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store
  alias PhoenixAI.Store.Conversation
  alias PhoenixAI.Store.CostTracking.CostRecord
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Guardrails.CostBudget

  @store_name :cost_integration_test_store

  setup do
    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    {:ok, _pid} =
      Store.start_link(
        name: @store_name,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

    # Save a conversation so we have a valid conversation_id
    conv = %Conversation{
      id: "conv-cost-1",
      title: "Cost test",
      user_id: "user-cost-1"
    }

    {:ok, _} = Store.save_conversation(conv, store: @store_name)

    on_exit(fn ->
      Application.delete_env(:phoenix_ai_store, :pricing)
    end)

    %{conv: conv}
  end

  defp build_response(attrs \\ %{}) do
    defaults = %{
      provider: :openai,
      model: "gpt-4o",
      usage: %PhoenixAI.Usage{
        input_tokens: 1000,
        output_tokens: 500,
        total_tokens: 1500
      }
    }

    struct(PhoenixAI.Response, Map.merge(defaults, attrs))
  end

  describe "record_cost/3" do
    test "records cost from a Response and returns CostRecord with Decimal values", %{conv: conv} do
      response = build_response()

      assert {:ok, %CostRecord{} = record} =
               Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")

      assert record.conversation_id == conv.id
      assert record.user_id == "user-cost-1"
      assert record.provider == :openai
      assert record.model == "gpt-4o"
      assert record.input_tokens == 1000
      assert record.output_tokens == 500
      assert Decimal.equal?(record.input_cost, Decimal.new("0.0025"))
      assert Decimal.equal?(record.output_cost, Decimal.new("0.005"))
      assert Decimal.equal?(record.total_cost, Decimal.new("0.0075"))
    end
  end

  describe "get_cost_records/2" do
    test "returns all recorded costs for a conversation", %{conv: conv} do
      response = build_response()

      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")
      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")

      assert {:ok, records} = Store.get_cost_records(conv.id, store: @store_name)
      assert length(records) == 2
      assert Enum.all?(records, &match?(%CostRecord{}, &1))
    end
  end

  describe "sum_cost/2" do
    test "aggregates cost with user_id filter", %{conv: conv} do
      response = build_response()

      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")
      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")

      assert {:ok, total} =
               Store.sum_cost([user_id: "user-cost-1"], store: @store_name)

      # 2 records × $0.0075 = $0.015
      assert Decimal.equal?(total, Decimal.new("0.015"))
    end

    test "returns zero for unknown user", %{conv: _conv} do
      assert {:ok, total} = Store.sum_cost([user_id: "nobody"], store: @store_name)
      assert Decimal.equal?(total, Decimal.new("0"))
    end
  end

  describe "CostBudget through check_guardrails/3" do
    test "halts when cost exceeds budget", %{conv: conv} do
      response = build_response()
      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Hello"}],
        conversation_id: conv.id,
        user_id: "user-cost-1"
      }

      policies = [{CostBudget, [max: "0.001", scope: :conversation]}]

      assert {:error, %PolicyViolation{} = violation} =
               Store.check_guardrails(request, policies, store: @store_name)

      assert violation.policy == CostBudget
      assert violation.reason =~ "Cost budget exceeded"
    end

    test "passes when cost is within budget", %{conv: conv} do
      response = build_response()
      {:ok, _} = Store.record_cost(conv.id, response, store: @store_name, user_id: "user-cost-1")

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Hello"}],
        conversation_id: conv.id,
        user_id: "user-cost-1"
      }

      policies = [{CostBudget, [max: "100.00", scope: :conversation]}]

      assert {:ok, %Request{}} =
               Store.check_guardrails(request, policies, store: @store_name)
    end
  end
end
