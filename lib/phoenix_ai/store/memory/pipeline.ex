defmodule PhoenixAI.Store.Memory.Pipeline do
  @moduledoc """
  Orchestrates memory strategy execution for a conversation's message list.

  The pipeline:
  1. Extracts pinned messages (role: :system or pinned: true)
  2. Sorts strategies by priority (lower = runs first)
  3. Applies each strategy sequentially on non-pinned messages
  4. Re-injects pinned messages at the beginning (in original order)
  5. Returns `{:ok, filtered_messages}`

  ## Presets

      Pipeline.preset(:default)     # SlidingWindow last: 50
      Pipeline.preset(:aggressive)  # TokenTruncation max_tokens: 4096
      Pipeline.preset(:summarize)   # Summarization + SlidingWindow
  """

  alias PhoenixAI.Store.Memory.Strategies.{SlidingWindow, Summarization, TokenTruncation}

  defstruct strategies: []

  @type strategy_entry :: {module(), keyword()}
  @type t :: %__MODULE__{strategies: [strategy_entry()]}

  @doc "Creates a new pipeline from a list of `{strategy_module, opts}` tuples."
  @spec new([strategy_entry()]) :: t()
  def new(strategies) when is_list(strategies), do: %__MODULE__{strategies: strategies}

  @doc "Returns a preset pipeline configuration."
  @spec preset(:default | :aggressive | :summarize) :: t()
  def preset(:default), do: new([{SlidingWindow, [last: 50]}])
  def preset(:aggressive), do: new([{TokenTruncation, [max_tokens: 4096]}])

  def preset(:summarize),
    do: new([{Summarization, [threshold: 20]}, {SlidingWindow, [last: 20]}])

  @doc """
  Runs the pipeline against a list of messages.

  Pinned messages (system messages and messages with `pinned: true`) are
  extracted before strategies run and re-injected at the beginning of the
  result in their original order.
  """
  @spec run(t(), [map()], map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def run(%__MODULE__{strategies: strategies}, messages, context, _opts \\ []) do
    {pinned_with_indices, non_pinned} = extract_pinned(messages)

    sorted = Enum.sort_by(strategies, fn {mod, _opts} -> mod.priority() end)

    case apply_strategies(sorted, non_pinned, context) do
      {:ok, filtered} -> {:ok, reinject_pinned(pinned_with_indices, filtered)}
      {:error, _} = error -> error
    end
  end

  defp extract_pinned(messages) do
    messages
    |> Enum.with_index()
    |> Enum.split_with(fn {msg, _idx} -> pinned?(msg) end)
    |> then(fn {pinned, non_pinned} ->
      {pinned, Enum.map(non_pinned, fn {msg, _idx} -> msg end)}
    end)
  end

  defp pinned?(%{role: :system}), do: true
  defp pinned?(%{pinned: true}), do: true
  defp pinned?(_), do: false

  defp apply_strategies([], messages, _context), do: {:ok, messages}

  defp apply_strategies([{mod, opts} | rest], messages, context) do
    case mod.apply(messages, context, opts) do
      {:ok, filtered} -> apply_strategies(rest, filtered, context)
      {:error, _} = error -> error
    end
  end

  defp reinject_pinned([], filtered), do: filtered

  defp reinject_pinned(pinned_with_indices, filtered) do
    pinned_msgs = Enum.map(pinned_with_indices, fn {msg, _idx} -> msg end)
    pinned_msgs ++ filtered
  end
end
