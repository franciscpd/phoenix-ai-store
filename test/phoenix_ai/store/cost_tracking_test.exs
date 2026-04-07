defmodule PhoenixAI.Store.CostTrackingTest do
  # async: false — this module calls Application.put_env/3 which is global state;
  # running async would cause pricing lookups in concurrent tests to see the wrong config.
  use ExUnit.Case, async: false

  alias PhoenixAI.Store.CostTracking
  alias PhoenixAI.Store.CostTracking.CostRecord

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.CostStore

    @impl true
    def save_cost_record(record, _opts), do: {:ok, record}

    @impl true
    def list_cost_records(_filters, _opts), do: {:ok, %{records: [], next_cursor: nil}}

    @impl true
    def count_cost_records(_filters, _opts), do: {:ok, 0}

    @impl true
    def sum_cost(_filters, _opts), do: {:ok, Decimal.new(0)}
  end

  defmodule NoCostAdapter do
    # An adapter that does NOT implement CostStore
  end

  setup do
    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    on_exit(fn ->
      Application.delete_env(:phoenix_ai_store, :pricing)
    end)

    :ok
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

  defp default_opts do
    [adapter: StubAdapter, adapter_opts: []]
  end

  describe "record/3" do
    test "records cost with correct Decimal arithmetic" do
      response = build_response()

      assert {:ok, %CostRecord{} = record} =
               CostTracking.record("conv-1", response, default_opts())

      # 1000 input * 0.0000025 = 0.0025
      assert Decimal.equal?(record.input_cost, Decimal.new("0.0025"))
      # 500 output * 0.00001 = 0.005
      assert Decimal.equal?(record.output_cost, Decimal.new("0.005"))
      # total = 0.0025 + 0.005 = 0.0075
      assert Decimal.equal?(record.total_cost, Decimal.new("0.0075"))

      assert record.conversation_id == "conv-1"
      assert record.provider == :openai
      assert record.model == "gpt-4o"
      assert record.input_tokens == 1000
      assert record.output_tokens == 500
    end

    test "returns {:error, :usage_not_normalized} for non-Usage struct" do
      response = build_response(%{usage: %{input_tokens: 100, output_tokens: 50}})

      assert {:error, :usage_not_normalized} =
               CostTracking.record("conv-1", response, default_opts())
    end

    test "returns {:error, :pricing_not_found} for unknown model" do
      response = build_response(%{model: "gpt-99"})

      assert {:error, :pricing_not_found} =
               CostTracking.record("conv-1", response, default_opts())
    end

    test "returns {:error, :cost_store_not_supported} for adapter without CostStore" do
      response = build_response()
      opts = [adapter: NoCostAdapter, adapter_opts: []]

      assert {:error, :cost_store_not_supported} =
               CostTracking.record("conv-1", response, opts)
    end

    test "passes user_id through to cost record" do
      response = build_response()
      opts = default_opts() ++ [user_id: "user-42"]

      assert {:ok, %CostRecord{} = record} =
               CostTracking.record("conv-1", response, opts)

      assert record.user_id == "user-42"
    end
  end
end
