defmodule PhoenixAI.Store.Guardrails.CostBudget do
  @moduledoc """
  Guardrail policy that enforces cost budgets scoped to conversations or users.

  This is a **stateful** policy that reads accumulated cost from the store
  adapter. The adapter must implement the
  `PhoenixAI.Store.Adapter.CostStore` sub-behaviour (specifically `sum_cost/2`).

  ## Options

    * `:max` (required) — maximum allowed cost as a `Decimal` or string
    * `:scope` — `:conversation` (default), `:user`, or `:time_window`

  ## Assigns

  The policy expects `request.assigns` to contain:

    * `:adapter` — the adapter module
    * `:adapter_opts` — keyword options for the adapter

  These are injected by `PhoenixAI.Store.check_guardrails/3`.
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  @spec check(Request.t(), keyword()) :: {:ok, Request.t()} | {:halt, PolicyViolation.t()}
  def check(%Request{} = request, opts) do
    scope = Keyword.get(opts, :scope, :conversation)
    max = parse_max(Keyword.fetch!(opts, :max))

    with {:ok, adapter, adapter_opts} <- extract_adapter(request),
         :ok <- validate_cost_store(adapter),
         :ok <- validate_scope_requirements(request, scope),
         {:ok, accumulated} <- query_cost(adapter, adapter_opts, request, scope) do
      case Decimal.compare(accumulated, max) do
        :gt ->
          {:halt, budget_violation(accumulated, max, scope)}

        _ ->
          {:ok, request}
      end
    end
  end

  # -- Private helpers --

  defp parse_max(%Decimal{} = d), do: d
  defp parse_max(str) when is_binary(str), do: Decimal.new(str)

  defp extract_adapter(%Request{assigns: assigns}) do
    case {Map.get(assigns, :adapter), Map.get(assigns, :adapter_opts)} do
      {nil, _} ->
        {:halt,
         violation(
           "No adapter found in request assigns. Use Store.check_guardrails/3 to inject the adapter."
         )}

      {adapter, opts} ->
        {:ok, adapter, opts || []}
    end
  end

  defp validate_cost_store(adapter) do
    if function_exported?(adapter, :sum_cost, 2) do
      :ok
    else
      {:halt,
       violation(
         "Adapter #{inspect(adapter)} does not support CostStore — sum_cost/2 is not exported."
       )}
    end
  end

  defp validate_scope_requirements(request, :conversation) do
    if request.conversation_id do
      :ok
    else
      {:halt,
       violation("Scope :conversation requires conversation_id to be set on the request.")}
    end
  end

  defp validate_scope_requirements(request, :user) do
    if request.user_id do
      :ok
    else
      {:halt, violation("Scope :user requires user_id to be set on the request.")}
    end
  end

  defp validate_scope_requirements(_request, _scope), do: :ok

  defp query_cost(adapter, adapter_opts, request, :conversation) do
    adapter.sum_cost([conversation_id: request.conversation_id], adapter_opts)
  end

  defp query_cost(adapter, adapter_opts, request, :user) do
    adapter.sum_cost([user_id: request.user_id], adapter_opts)
  end

  defp budget_violation(accumulated, max, scope) do
    %PolicyViolation{
      policy: __MODULE__,
      reason:
        "Cost budget exceeded: $#{Decimal.to_string(accumulated)} / $#{Decimal.to_string(max)} (scope: #{scope})",
      metadata: %{
        accumulated: accumulated,
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
