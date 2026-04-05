defmodule PhoenixAI.Store.CostTracking.CostRecord do
  @moduledoc """
  A cost record linked to a conversation turn.

  Records the token usage and computed cost for a single AI provider
  call, using `Decimal` for all monetary values.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          conversation_id: String.t(),
          user_id: String.t() | nil,
          provider: atom(),
          model: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          input_cost: Decimal.t(),
          output_cost: Decimal.t(),
          total_cost: Decimal.t(),
          metadata: map(),
          recorded_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :provider,
    :model,
    :recorded_at,
    input_tokens: 0,
    output_tokens: 0,
    input_cost: Decimal.new(0),
    output_cost: Decimal.new(0),
    total_cost: Decimal.new(0),
    metadata: %{}
  ]
end
