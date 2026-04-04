defmodule PhoenixAI.Store.Memory.TokenCounter do
  @moduledoc """
  Behaviour for counting tokens in message content.

  Implementations provide a heuristic or API-based token count
  used by memory strategies to enforce token budgets.
  """

  @callback count_tokens(content :: String.t() | nil, opts :: keyword()) :: non_neg_integer()
end
