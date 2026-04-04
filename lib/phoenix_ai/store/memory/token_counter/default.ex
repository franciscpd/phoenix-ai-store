defmodule PhoenixAI.Store.Memory.TokenCounter.Default do
  @moduledoc """
  Default token counter using a `bytes / 4` heuristic.

  This approximation is commonly used as a rough estimate for
  English text across most LLM tokenizers.
  """

  @behaviour PhoenixAI.Store.Memory.TokenCounter

  @impl true
  def count_tokens(nil, _opts), do: 0

  @impl true
  def count_tokens("", _opts), do: 0

  @impl true
  def count_tokens(content, _opts) when is_binary(content) do
    max(1, div(byte_size(content), 4))
  end
end
