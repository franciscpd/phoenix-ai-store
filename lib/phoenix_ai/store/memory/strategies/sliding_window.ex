defmodule PhoenixAI.Store.Memory.Strategies.SlidingWindow do
  @moduledoc """
  A memory strategy that keeps the last N messages.

  ## Options

    * `:last` - the number of most recent messages to keep (default: 50)

  ## Priority

  Returns 100, making it a low-priority (late-running) strategy.
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  @default_last 50

  @impl true
  def apply(messages, _context, opts) do
    last = Keyword.get(opts, :last, @default_last)
    {:ok, Enum.take(messages, -last)}
  end

  @impl true
  def priority, do: 100
end
