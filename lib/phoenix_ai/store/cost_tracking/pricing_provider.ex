defmodule PhoenixAI.Store.CostTracking.PricingProvider do
  @moduledoc """
  Behaviour for resolving per-model token pricing.

  Implementations return `{input_price, output_price}` as `Decimal` values
  representing the cost per token for a given provider and model.
  """

  @callback price_for(provider :: atom(), model :: String.t()) ::
              {:ok, {input_price :: Decimal.t(), output_price :: Decimal.t()}}
              | {:error, :unknown_model}
end
