defmodule PhoenixAI.Store.LongTermMemory.Extractor do
  @moduledoc """
  Behaviour for extracting key-value facts from conversation messages.

  Implementations receive a list of messages (typically only new ones since
  the last extraction) and a context map, and return a list of
  `%{key: String.t(), value: String.t()}` pairs.
  """

  alias PhoenixAI.Store.Message

  @callback extract(
              messages :: [Message.t()],
              context :: map(),
              opts :: keyword()
            ) :: {:ok, [%{key: String.t(), value: String.t()}]} | {:error, term()}
end
