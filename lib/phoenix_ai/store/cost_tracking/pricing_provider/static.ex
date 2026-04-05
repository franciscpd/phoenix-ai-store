defmodule PhoenixAI.Store.CostTracking.PricingProvider.Static do
  @moduledoc """
  Default pricing provider that reads from application config.

  Expects `:phoenix_ai_store, :pricing` to be a map with
  `{provider_atom, model_string}` tuple keys and `{input_string, output_string}`
  values. Strings are parsed to `Decimal` at lookup time.

  ## Example config

      config :phoenix_ai_store, :pricing, %{
        {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
        {:anthropic, "claude-sonnet-4-20250514"} => {"0.000003", "0.000015"}
      }
  """

  @behaviour PhoenixAI.Store.CostTracking.PricingProvider

  @impl true
  def price_for(provider, model) do
    pricing = Application.get_env(:phoenix_ai_store, :pricing, %{})

    case Map.fetch(pricing, {provider, model}) do
      {:ok, {input_str, output_str}} ->
        {:ok, {Decimal.new(input_str), Decimal.new(output_str)}}

      :error ->
        {:error, :unknown_model}
    end
  end
end
