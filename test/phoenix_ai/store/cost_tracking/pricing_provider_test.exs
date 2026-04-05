defmodule PhoenixAI.Store.CostTracking.PricingProviderTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.CostTracking.PricingProvider.Static

  setup do
    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
      {:anthropic, "claude-sonnet-4-20250514"} => {"0.000003", "0.000015"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    on_exit(fn ->
      Application.delete_env(:phoenix_ai_store, :pricing)
    end)

    :ok
  end

  describe "Static.price_for/2" do
    test "returns Decimal prices for a known model" do
      assert {:ok, {input_price, output_price}} = Static.price_for(:openai, "gpt-4o")

      assert %Decimal{} = input_price
      assert %Decimal{} = output_price
      assert Decimal.equal?(input_price, Decimal.new("0.0000025"))
      assert Decimal.equal?(output_price, Decimal.new("0.00001"))
    end

    test "returns Decimal prices for another known model" do
      assert {:ok, {input_price, output_price}} =
               Static.price_for(:anthropic, "claude-sonnet-4-20250514")

      assert Decimal.equal?(input_price, Decimal.new("0.000003"))
      assert Decimal.equal?(output_price, Decimal.new("0.000015"))
    end

    test "returns {:error, :unknown_model} for unknown model" do
      assert {:error, :unknown_model} = Static.price_for(:openai, "gpt-99")
    end

    test "returns {:error, :unknown_model} for unknown provider" do
      assert {:error, :unknown_model} = Static.price_for(:unknown, "gpt-4o")
    end

    test "returns error when no pricing configured" do
      Application.delete_env(:phoenix_ai_store, :pricing)

      assert {:error, :unknown_model} = Static.price_for(:openai, "gpt-4o")
    end
  end
end
