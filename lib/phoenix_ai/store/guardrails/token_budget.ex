defmodule PhoenixAI.Store.Guardrails.TokenBudget do
  @moduledoc """
  Guardrail policy that enforces token budgets scoped to conversations,
  users, or time windows.

  This is a **stateful** policy that reads accumulated token counts from
  the store adapter. The adapter must implement the
  `PhoenixAI.Store.Adapter.TokenUsage` sub-behaviour.

  ## Options

    * `:max` (required) — maximum allowed token count
    * `:scope` — `:conversation` (default), `:user`, or `:time_window`
    * `:mode` — `:accumulated` (default) or `:estimated`
    * `:token_counter` — module implementing `PhoenixAI.Store.Memory.TokenCounter`
      (default: `PhoenixAI.Store.Memory.TokenCounter.Default`)
    * `:window_ms` — for `:time_window` scope, the window duration in ms
    * `:key_prefix` — for `:time_window` scope, Hammer key prefix
    * `:rate_limiter` — for `:time_window` scope, the Hammer-compatible module to use
      (default: `PhoenixAI.Store.Guardrails.TokenBudget.RateLimiter`)

  ## Assigns

  The policy expects `request.assigns` to contain:

    * `:adapter` — the adapter module
    * `:adapter_opts` — keyword options for the adapter

  These are injected by `PhoenixAI.Store.check_guardrails/3`.
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @default_token_counter PhoenixAI.Store.Memory.TokenCounter.Default

  @impl true
  @spec check(Request.t(), keyword()) :: {:ok, Request.t()} | {:halt, PolicyViolation.t()}
  def check(%Request{} = request, opts) do
    with {:ok, adapter, adapter_opts} <- extract_adapter(request),
         :ok <- validate_token_usage(adapter),
         scope <- Keyword.get(opts, :scope, :conversation),
         {:ok, _} <- validate_scope_requirements(request, scope, opts),
         {:ok, accumulated} <- fetch_accumulated(adapter, adapter_opts, request, scope, opts) do
      estimated = estimate_request_tokens(request, opts)
      total = accumulated + estimated
      max = Keyword.fetch!(opts, :max)

      if total <= max do
        {:ok, request}
      else
        {:halt, budget_violation(accumulated, estimated, total, max, scope)}
      end
    end
  end

  # -- Private helpers --

  defp extract_adapter(%Request{assigns: assigns}) do
    case {Map.get(assigns, :adapter), Map.get(assigns, :adapter_opts)} do
      {nil, _} ->
        {:halt, violation("No adapter found in request assigns. Use Store.check_guardrails/3 to inject the adapter.")}

      {adapter, opts} ->
        {:ok, adapter, opts || []}
    end
  end

  defp validate_token_usage(adapter) do
    if function_exported?(adapter, :sum_conversation_tokens, 2) and
         function_exported?(adapter, :sum_user_tokens, 2) do
      :ok
    else
      {:halt, violation("Adapter #{inspect(adapter)} does not support TokenUsage — sum_conversation_tokens/2 and sum_user_tokens/2 are not exported.")}
    end
  end

  defp validate_scope_requirements(request, :conversation, _opts) do
    if request.conversation_id do
      {:ok, :valid}
    else
      {:halt, violation("Scope :conversation requires conversation_id to be set on the request.")}
    end
  end

  defp validate_scope_requirements(request, :user, _opts) do
    if request.user_id do
      {:ok, :valid}
    else
      {:halt, violation("Scope :user requires user_id to be set on the request.")}
    end
  end

  defp validate_scope_requirements(_request, :time_window, opts) do
    cond do
      not Code.ensure_loaded?(Hammer) ->
        {:halt, violation("Scope :time_window requires the :hammer dependency. Add {:hammer, \"~> 7.3\"} to your mix.exs.")}

      not Keyword.has_key?(opts, :window_ms) ->
        {:halt, violation("Scope :time_window requires the :window_ms option.")}

      true ->
        {:ok, :valid}
    end
  end

  defp fetch_accumulated(adapter, adapter_opts, request, :conversation, _opts) do
    adapter.sum_conversation_tokens(request.conversation_id, adapter_opts)
  end

  defp fetch_accumulated(adapter, adapter_opts, request, :user, _opts) do
    adapter.sum_user_tokens(request.user_id, adapter_opts)
  end

  defp fetch_accumulated(_adapter, _adapter_opts, request, :time_window, opts) do
    key_prefix = Keyword.get(opts, :key_prefix, "token_budget")
    window_ms = Keyword.fetch!(opts, :window_ms)
    max = Keyword.fetch!(opts, :max)
    key = "#{key_prefix}:#{request.user_id || request.conversation_id}"

    counter = Keyword.get(opts, :token_counter, @default_token_counter)
    rate_limiter = Keyword.get(opts, :rate_limiter, default_rate_limiter())

    increment =
      request.messages
      |> Enum.map(fn msg -> counter.count_tokens(msg.content, []) end)
      |> Enum.sum()

    case rate_limiter.hit(key, window_ms, max, increment) do
      {:allow, count} -> {:ok, count}
      # Return max + 1 so that the budget check (total > max) correctly triggers a halt
      {:deny, _timeout} -> {:ok, max + 1}
    end
  end

  if Code.ensure_loaded?(Hammer) do
    defp default_rate_limiter,
      do: PhoenixAI.Store.Guardrails.TokenBudget.RateLimiter
  else
    defp default_rate_limiter, do: nil
  end

  defp estimate_request_tokens(%Request{} = request, opts) do
    mode = Keyword.get(opts, :mode, :accumulated)

    case mode do
      :accumulated ->
        0

      :estimated ->
        counter = Keyword.get(opts, :token_counter, @default_token_counter)

        request.messages
        |> Enum.map(fn msg -> counter.count_tokens(msg.content, []) end)
        |> Enum.sum()
    end
  end

  defp budget_violation(accumulated, estimated, total, max, scope) do
    %PolicyViolation{
      policy: __MODULE__,
      reason: "Token budget exceeded: #{total} / #{max} (scope: #{scope})",
      metadata: %{
        accumulated: accumulated,
        estimated: estimated,
        total: total,
        max: max,
        scope: scope
      }
    }
  end

  defp violation(reason) do
    %PolicyViolation{
      policy: __MODULE__,
      reason: reason,
      metadata: %{}
    }
  end
end
