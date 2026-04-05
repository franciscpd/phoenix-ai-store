defmodule PhoenixAI.Store.CostTracking do
  @moduledoc """
  Orchestrator for recording per-turn cost data.

  Given a `PhoenixAI.Response` with a normalized `%PhoenixAI.Usage{}` struct,
  `record/3` resolves token pricing, computes costs with exact `Decimal`
  arithmetic, persists the cost record through the configured adapter, and
  emits a telemetry event.

  ## Options

    * `:adapter` — adapter module (required, must implement `CostStore`)
    * `:adapter_opts` — adapter options (required)
    * `:user_id` — user to attribute cost to
    * `:pricing_provider` — module implementing `PricingProvider` behaviour
      (default: `PricingProvider.Static`)
    * `:metadata` — extra metadata map
  """

  alias PhoenixAI.Store.CostTracking.{CostRecord, PricingProvider}

  @doc """
  Record the cost of a single AI provider call.

  ## Flow

  1. Validates usage is a `%PhoenixAI.Usage{}` struct
  2. Resolves adapter from opts and checks CostStore support
  3. Looks up pricing via the pricing provider
  4. Builds a `CostRecord` with exact Decimal arithmetic
  5. Persists via `adapter.save_cost_record/2`
  6. Emits `[:phoenix_ai_store, :cost, :recorded]` telemetry event
  """
  @spec record(String.t(), PhoenixAI.Response.t(), keyword()) ::
          {:ok, CostRecord.t()} | {:error, term()}
  def record(conversation_id, %PhoenixAI.Response{} = response, opts) do
    with :ok <- validate_usage(response.usage),
         {:ok, adapter, adapter_opts} <- resolve_adapter(opts),
         :ok <- check_cost_store_support(adapter),
         {:ok, {input_price, output_price}} <- lookup_pricing(response, opts),
         record <- build_record(conversation_id, response, input_price, output_price, opts),
         {:ok, saved} <- adapter.save_cost_record(record, adapter_opts) do
      emit_telemetry(saved, conversation_id, opts)
      {:ok, saved}
    end
  end

  defp validate_usage(%PhoenixAI.Usage{}), do: :ok
  defp validate_usage(_), do: {:error, :usage_not_normalized}

  defp resolve_adapter(opts) do
    case {Keyword.fetch(opts, :adapter), Keyword.fetch(opts, :adapter_opts)} do
      {{:ok, adapter}, {:ok, adapter_opts}} -> {:ok, adapter, adapter_opts}
      _ -> {:error, :adapter_not_configured}
    end
  end

  defp check_cost_store_support(adapter) do
    if function_exported?(adapter, :save_cost_record, 2) do
      :ok
    else
      {:error, :cost_store_not_supported}
    end
  end

  defp lookup_pricing(response, opts) do
    provider_mod =
      Keyword.get(opts, :pricing_provider, PricingProvider.Static)

    case provider_mod.price_for(response.provider, response.model) do
      {:ok, _prices} = ok -> ok
      {:error, :unknown_model} -> {:error, :pricing_not_found}
    end
  end

  defp build_record(conversation_id, response, input_price, output_price, opts) do
    usage = response.usage
    input_cost = Decimal.mult(Decimal.new(usage.input_tokens), input_price)
    output_cost = Decimal.mult(Decimal.new(usage.output_tokens), output_price)
    total_cost = Decimal.add(input_cost, output_cost)

    %CostRecord{
      conversation_id: conversation_id,
      user_id: Keyword.get(opts, :user_id),
      provider: response.provider,
      model: response.model,
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      input_cost: input_cost,
      output_cost: output_cost,
      total_cost: total_cost,
      metadata: Keyword.get(opts, :metadata, %{}),
      recorded_at: DateTime.utc_now()
    }
  end

  defp emit_telemetry(record, conversation_id, opts) do
    :telemetry.execute(
      [:phoenix_ai_store, :cost, :recorded],
      %{total_cost: record.total_cost},
      %{
        conversation_id: conversation_id,
        user_id: Keyword.get(opts, :user_id),
        provider: record.provider,
        model: record.model,
        input_tokens: record.input_tokens,
        output_tokens: record.output_tokens,
        input_cost: record.input_cost,
        output_cost: record.output_cost
      }
    )
  end
end
