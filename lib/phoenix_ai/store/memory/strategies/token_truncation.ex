defmodule PhoenixAI.Store.Memory.Strategies.TokenTruncation do
  @moduledoc """
  A memory strategy that removes oldest messages until the total token count
  fits within a budget.

  Sums tokens from newest to oldest, keeping the newest messages that fit.

  ## Options

    * `:max_tokens` - the maximum token budget (required)

  ## Token counting

  Uses `token_count` from the message struct when available. Falls back to
  the token counter provided in context (`:token_counter`) or
  `PhoenixAI.Store.Memory.TokenCounter.Default`.

  ## Priority

  Returns 200.
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  @impl true
  def apply(messages, context, opts) do
    max_tokens =
      Keyword.get(opts, :max_tokens) ||
        raise ArgumentError, "TokenTruncation requires :max_tokens option"

    counter = context[:token_counter] || PhoenixAI.Store.Memory.TokenCounter.Default

    result =
      messages
      |> Enum.reverse()
      |> Enum.reduce_while({0, []}, fn msg, {total, acc} ->
        count = msg.token_count || counter.count_tokens(msg.content, opts)
        new_total = total + count

        if new_total <= max_tokens do
          {:cont, {new_total, [msg | acc]}}
        else
          {:halt, {total, acc}}
        end
      end)
      |> elem(1)

    {:ok, result}
  end

  @impl true
  def priority, do: 200
end
