defmodule PhoenixAI.Store.LongTermMemory.Extractor.Default do
  @moduledoc """
  Default AI-powered fact extractor using `AI.chat/2`.

  Sends conversation messages to the AI with a prompt asking for key-value
  facts in JSON format. Accepts `:extract_fn` in opts for test injection.

  ## Options

    * `:extract_fn` - 3-arity function override for testing (avoids real AI calls)
    * `:provider` - AI provider (falls back to context)
    * `:model` - AI model (falls back to context)
  """

  @behaviour PhoenixAI.Store.LongTermMemory.Extractor

  @impl true
  def extract([], _context, _opts), do: {:ok, []}

  def extract(messages, context, opts) do
    case do_extract(messages, context, opts) do
      {:ok, json_string} -> parse_facts(json_string)
      {:error, reason} -> {:error, {:extraction_failed, reason}}
    end
  end

  defp do_extract(messages, context, opts) do
    case Keyword.get(opts, :extract_fn) do
      nil -> call_ai(messages, context, opts)
      fun when is_function(fun, 3) -> fun.(messages, context, opts)
    end
  end

  defp call_ai(messages, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

    unless provider do
      raise ArgumentError,
            "Fact extraction requires :provider in context or opts."
    end

    conversation_text =
      messages
      |> Enum.map(fn msg -> "#{msg.role}: #{msg.content}" end)
      |> Enum.join("\n")

    existing_facts_text =
      case Map.get(context, :existing_facts, []) do
        [] ->
          ""

        facts ->
          known =
            facts
            |> Enum.map(fn f -> "- #{f.key}: #{f.value}" end)
            |> Enum.join("\n")

          "\nAlready known facts (do not re-extract these unless the value changed):\n#{known}\n"
      end

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content: """
        Extract key facts about the user from the conversation below.
        Return a JSON array of objects with "key" and "value" fields.
        Keys should be snake_case identifiers (e.g., "preferred_language", "city", "expertise").
        Values should be concise strings.
        If no facts can be extracted, return an empty array [].
        #{existing_facts_text}Output ONLY the JSON array, no preamble or explanation.
        """
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

  defp parse_facts(json_string) do
    case Jason.decode(json_string) do
      {:ok, facts} when is_list(facts) ->
        parsed =
          facts
          |> Enum.filter(fn f ->
            is_map(f) and Map.has_key?(f, "key") and Map.has_key?(f, "value")
          end)
          |> Enum.map(fn f -> %{key: f["key"], value: f["value"]} end)

        {:ok, parsed}

      {:ok, _other} ->
        {:error, {:parse_error, json_string}}

      {:error, _} ->
        {:error, {:parse_error, json_string}}
    end
  end
end
