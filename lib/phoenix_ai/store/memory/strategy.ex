defmodule PhoenixAI.Store.Memory.Strategy do
  @moduledoc """
  Behaviour for memory strategies that filter or transform message lists.

  Strategies are applied in priority order (lower number = higher priority)
  to reduce a conversation's message list before sending to an LLM.
  """

  alias PhoenixAI.Store.Message

  @callback apply([Message.t()], context :: map(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}

  @callback priority() :: non_neg_integer()
end
