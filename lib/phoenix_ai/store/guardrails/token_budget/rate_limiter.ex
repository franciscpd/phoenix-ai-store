if Code.ensure_loaded?(Hammer) do
  defmodule PhoenixAI.Store.Guardrails.TokenBudget.RateLimiter do
    @moduledoc """
    Default Hammer-backed rate limiter for the `:time_window` scope of
    `PhoenixAI.Store.Guardrails.TokenBudget`.

    Start this process in your supervision tree when using the time-window
    token budget:

        children = [
          {PhoenixAI.Store.Guardrails.TokenBudget.RateLimiter, clean_period: :timer.minutes(5)}
        ]

    The module implements the `Hammer` behaviour and exposes `hit/4`.
    """

    use Hammer, backend: :ets
  end
end
