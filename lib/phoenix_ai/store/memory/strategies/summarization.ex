defmodule PhoenixAI.Store.Memory.Strategies.Summarization do
  @moduledoc """
  A memory strategy that condenses older messages into an AI-generated summary.

  When the message count exceeds the threshold, the oldest messages are
  summarized into a single pinned system message, while the most recent
  messages are kept intact.

  ## Options

    * `:threshold` - minimum message count before summarization kicks in (default: 20)
    * `:summarize_fn` - a 3-arity function for testing (avoids real AI calls)
    * `:provider` - AI provider override (falls back to context)
    * `:model` - AI model override (falls back to context)

  ## Priority

  Returns 300.
  """

  @behaviour PhoenixAI.Store.Memory.Strategy

  alias PhoenixAI.Store.Message

  @default_threshold 20

  @impl true
  def apply([], _context, _opts), do: {:ok, []}

  def apply(messages, context, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    if length(messages) < threshold do
      {:ok, messages}
    else
      keep_count = div(threshold, 2)
      split_point = length(messages) - keep_count
      {to_summarize, to_keep} = Enum.split(messages, split_point)

      case do_summarize(to_summarize, context, opts) do
        {:ok, summary_text} ->
          summary_msg = %Message{
            role: :system,
            content: summary_text,
            pinned: true,
            inserted_at: DateTime.utc_now()
          }

          {:ok, [summary_msg | to_keep]}

        {:error, _} = error ->
          error
      end
    end
  end

  @impl true
  def priority, do: 300

  defp do_summarize(messages, context, opts) do
    case Keyword.get(opts, :summarize_fn) do
      nil -> call_ai(messages, context, opts)
      fun when is_function(fun, 3) -> fun.(messages, context, opts)
    end
  end

  # Uses AI.chat/2 from the phoenix_ai dependency
  defp call_ai(messages, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

    unless provider do
      raise ArgumentError,
            "Summarization requires :provider in context or opts. " <>
              "Pass it via Pipeline context or Summarization opts."
    end

    conversation_text =
      Enum.map_join(messages, "\n", fn msg -> "#{msg.role}: #{msg.content}" end)

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content:
          "Summarize the following conversation concisely, preserving key facts, decisions, and context. Output only the summary, no preamble."
      },
      %PhoenixAI.Message{
        role: :user,
        content: conversation_text
      }
    ]

    ai_opts =
      [provider: provider, model: model]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case AI.chat(prompt, ai_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end
end
