defmodule PhoenixAI.Store.Cost.UATTest do
  @moduledoc """
  Automated UAT for Phase 6 — Cost Tracking.
  Covers all 6 success criteria from ROADMAP.md.
  """
  use ExUnit.Case

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.CostTracking.CostRecord
  alias PhoenixAI.Store.Guardrails.CostBudget

  setup do
    store = :"cost_uat_#{System.unique_integer([:positive])}"

    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
      {:openai, "gpt-4o-mini"} => {"0.00000015", "0.0000006"},
      {:anthropic, "claude-sonnet-4-5"} => {"0.000003", "0.000015"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    {:ok, _} =
      Store.start_link(
        name: store,
        adapter: PhoenixAI.Store.Adapters.ETS,
        cost_tracking: [enabled: true]
      )

    conv = %Conversation{
      id: Uniq.UUID.uuid7(),
      user_id: "uat_cost_user",
      title: "Cost UAT",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store)

    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    {:ok, store: store, conv_id: conv.id}
  end

  # ── UAT 1: Configurable pricing tables (COST-01) ──

  describe "UAT 1: Pricing tables are configurable, never hardcoded" do
    test "prices come from Application config", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      {:ok, record} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")

      # input: 1000 * 0.0000025 = 0.0025
      assert Decimal.equal?(record.input_cost, Decimal.new("0.0025000"))
      # output: 500 * 0.00001 = 0.005
      assert Decimal.equal?(record.output_cost, Decimal.new("0.0050000"))
    end

    test "different model has different pricing", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :anthropic,
        model: "claude-sonnet-4-5",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      {:ok, record} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")

      # input: 1000 * 0.000003 = 0.003
      assert Decimal.equal?(record.input_cost, Decimal.new("0.003000"))
      # output: 500 * 0.000015 = 0.0075
      assert Decimal.equal?(record.output_cost, Decimal.new("0.007500"))
    end

    test "unknown model returns error, not zero cost", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "nonexistent-model",
        usage: %PhoenixAI.Usage{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      assert {:error, :pricing_not_found} =
               Store.record_cost(conv_id, response, store: store)
    end
  end

  # ── UAT 2: CostRecord with Decimal, no floating-point drift (COST-02, COST-08) ──

  describe "UAT 2: CostRecord uses Decimal, querying twice returns same value" do
    test "record uses Decimal and is deterministic", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")

      # Query twice — must return identical Decimal values
      {:ok, [record1]} = Store.get_cost_records(conv_id, store: store)
      {:ok, [record2]} = Store.get_cost_records(conv_id, store: store)

      assert Decimal.equal?(record1.total_cost, record2.total_cost)
      assert record1.total_cost == record2.total_cost
      assert is_struct(record1.total_cost, Decimal)
    end
  end

  # ── UAT 3: Query by conversation, user, provider, model, time range (COST-05) ──

  describe "UAT 3: Query costs by multiple dimensions in single API call" do
    setup %{store: store, conv_id: conv_id} do
      # Record costs from different providers
      openai_resp = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      anthropic_resp = %PhoenixAI.Response{
        provider: :anthropic,
        model: "claude-sonnet-4-5",
        usage: %PhoenixAI.Usage{input_tokens: 2000, output_tokens: 1000, total_tokens: 3000}
      }

      {:ok, _} = Store.record_cost(conv_id, openai_resp, store: store, user_id: "uat_cost_user")
      {:ok, _} = Store.record_cost(conv_id, anthropic_resp, store: store, user_id: "uat_cost_user")

      :ok
    end

    test "query by conversation", %{store: store, conv_id: conv_id} do
      {:ok, total} = Store.sum_cost([conversation_id: conv_id], store: store)
      assert Decimal.compare(total, Decimal.new("0")) == :gt
    end

    test "query by user", %{store: store} do
      {:ok, total} = Store.sum_cost([user_id: "uat_cost_user"], store: store)
      assert Decimal.compare(total, Decimal.new("0")) == :gt
    end

    test "query by provider", %{store: store} do
      {:ok, openai_total} = Store.sum_cost([provider: :openai], store: store)
      {:ok, anthropic_total} = Store.sum_cost([provider: :anthropic], store: store)

      # Both should be positive and different
      assert Decimal.compare(openai_total, Decimal.new("0")) == :gt
      assert Decimal.compare(anthropic_total, Decimal.new("0")) == :gt
      refute Decimal.equal?(openai_total, anthropic_total)
    end

    test "query by model", %{store: store} do
      {:ok, total} = Store.sum_cost([model: "gpt-4o"], store: store)
      assert Decimal.compare(total, Decimal.new("0")) == :gt
    end

    test "query by time range", %{store: store} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, total} = Store.sum_cost([after: future], store: store)
      assert Decimal.equal?(total, Decimal.new("0"))
    end
  end

  # ── UAT 4: Telemetry event emitted (COST-04) ──

  describe "UAT 4: Telemetry event emitted on cost record" do
    test "[:phoenix_ai_store, :cost, :recorded] fires", %{store: store, conv_id: conv_id} do
      test_pid = self()

      :telemetry.attach(
        "cost-uat-test",
        [:phoenix_ai_store, :cost, :recorded],
        fn name, measurements, metadata, _ ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")

      assert_receive {:telemetry, [:phoenix_ai_store, :cost, :recorded], measurements, metadata}
      assert is_struct(measurements.total_cost, Decimal)
      assert metadata.provider == :openai
      assert metadata.model == "gpt-4o"
      assert metadata.conversation_id == conv_id

      :telemetry.detach("cost-uat-test")
    end
  end

  # ── UAT 5: CostBudget blocks calls before they exceed limits (GUARD-02) ──

  describe "UAT 5: CostBudget guardrail blocks when exceeded" do
    test "blocks when conversation cost exceeds budget", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 10_000, output_tokens: 5_000, total_tokens: 15_000}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")
      # Cost: 10000 * 0.0000025 + 5000 * 0.00001 = 0.025 + 0.05 = 0.075

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "test"}],
        conversation_id: conv_id,
        user_id: "uat_cost_user"
      }

      # Budget $0.01 < accumulated $0.075 → should halt
      assert {:error, %PolicyViolation{policy: CostBudget} = v} =
               Store.check_guardrails(
                 request,
                 [{CostBudget, scope: :conversation, max: "0.01"}],
                 store: store
               )

      assert v.reason =~ "Cost budget exceeded"
      assert Decimal.compare(v.metadata.accumulated, Decimal.new("0.01")) == :gt
    end

    test "passes when under budget", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "uat_cost_user")

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "test"}],
        conversation_id: conv_id,
        user_id: "uat_cost_user"
      }

      # Budget $100 >> accumulated → should pass
      assert {:ok, %Request{}} =
               Store.check_guardrails(
                 request,
                 [{CostBudget, scope: :conversation, max: "100.00"}],
                 store: store
               )
    end
  end

  # ── UAT 6: Non-normalized usage returns error (Success Criteria #6) ──

  describe "UAT 6: Non-normalized usage rejected" do
    test "raw map usage returns :usage_not_normalized", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %{"prompt_tokens" => 100, "completion_tokens" => 50}
      }

      assert {:error, :usage_not_normalized} =
               Store.record_cost(conv_id, response, store: store)
    end
  end
end
