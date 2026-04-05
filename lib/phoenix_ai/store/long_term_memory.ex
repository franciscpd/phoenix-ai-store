defmodule PhoenixAI.Store.LongTermMemory do
  @moduledoc """
  Orchestrates long-term memory: fact CRUD, extraction, profile updates,
  and context injection.

  All functions accept a `:store` option to specify which store instance
  to use (default: `:phoenix_ai_store_default`).
  """

  alias PhoenixAI.Store.Instance
  alias PhoenixAI.Store.LongTermMemory.{Extractor, Fact, Profile}

  # -- Manual CRUD: Facts --

  @doc """
  Persists a long-term memory fact for a user.

  Performs an upsert keyed on `{user_id, key}` — if a fact with the same key
  already exists for the user it will be updated, otherwise a new row is created.

  ## Examples

      {:ok, fact} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "language", value: "Elixir"})
  """
  @spec save_fact(Fact.t(), keyword()) :: {:ok, Fact.t()} | {:error, term()}
  def save_fact(%Fact{} = fact, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :fact, :save], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_fact_store(opts) do
          adapter.save_fact(fact, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Returns all stored facts for a user, ordered by insertion time.

  ## Examples

      {:ok, facts} = LongTermMemory.get_facts("u1")
  """
  @spec get_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def get_facts(user_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :fact, :get], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_fact_store(opts) do
          adapter.get_facts(user_id, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Deletes a specific fact by key for a user.

  Returns `:ok` whether or not the fact existed.

  ## Examples

      :ok = LongTermMemory.delete_fact("u1", "language")
  """
  @spec delete_fact(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_fact(user_id, key, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :fact, :delete], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_fact_store(opts) do
          adapter.delete_fact(user_id, key, adapter_opts)
        end

      {result, %{}}
    end)
  end

  # -- Manual CRUD: Profiles --

  @doc """
  Persists a user profile summary.

  Performs an upsert keyed on `user_id` — if a profile already exists for the
  user it will be replaced, otherwise a new one is created.

  ## Examples

      {:ok, profile} = LongTermMemory.save_profile(%Profile{user_id: "u1", summary: "Elixir developer"})
  """
  @spec save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def save_profile(%Profile{} = profile, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :profile, :save], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_profile_store(opts) do
          adapter.save_profile(profile, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Loads the profile for a user by ID.

  Returns `{:error, :not_found}` if no profile exists for the user.

  ## Examples

      {:ok, profile} = LongTermMemory.get_profile("u1")
      {:error, :not_found} = LongTermMemory.get_profile("unknown")
  """
  @spec get_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, :not_found | term()}
  def get_profile(user_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :profile, :get], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_profile_store(opts) do
          adapter.load_profile(user_id, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Deletes the profile for a user.

  Returns `:ok` whether or not a profile existed.

  ## Examples

      :ok = LongTermMemory.delete_profile("u1")
  """
  @spec delete_profile(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_profile(user_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :profile, :delete], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_profile_store(opts) do
          adapter.delete_profile(user_id, adapter_opts)
        end

      {result, %{}}
    end)
  end

  # -- Extraction --

  @doc """
  Extracts new facts from a conversation's unprocessed messages and persists them.

  Uses a cursor stored in `conversation.metadata["_ltm_cursor"]` to process only
  messages added since the last extraction. Pass `extraction_mode: :async` to run
  extraction in a supervised Task and return `{:ok, :async}` immediately.

  ## Options

    * `:extraction_mode` — `:sync` (default) or `:async`
    * `:extractor` — extractor module (default: `Extractor.Default`)
    * `:max_facts_per_user` — cap on total facts per user (default: `100`)
    * `:provider` / `:model` — AI provider options forwarded to the extractor

  ## Examples

      {:ok, facts} = LongTermMemory.extract_facts(conversation_id)
      {:ok, :async} = LongTermMemory.extract_facts(conversation_id, extraction_mode: :async)
  """
  @spec extract_facts(String.t(), keyword()) ::
          {:ok, [Fact.t()]} | {:ok, :async} | {:error, term()}
  def extract_facts(conversation_id, opts \\ []) do
    mode = Keyword.get(opts, :extraction_mode, :sync)

    case mode do
      :async ->
        with {:ok, _adapter, _adapter_opts} <- resolve_fact_store(opts) do
          store = Keyword.get(opts, :store, :phoenix_ai_store_default)
          task_sup = :"#{store}_task_supervisor"

          Task.Supervisor.start_child(task_sup, fn ->
            do_extract_facts_with_telemetry(conversation_id, opts)
          end)

          {:ok, :async}
        end

      _sync ->
        do_extract_facts_with_telemetry(conversation_id, opts)
    end
  end

  defp do_extract_facts_with_telemetry(conversation_id, opts) do
    :telemetry.span([:phoenix_ai_store, :extract_facts], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_fact_store(opts) do
          do_extract_facts(conversation_id, adapter, adapter_opts, opts)
        end

      {result, %{}}
    end)
  end

  defp do_extract_facts(conversation_id, adapter, adapter_opts, opts) do
    with {:ok, conv} <- adapter.load_conversation(conversation_id, adapter_opts),
         {:ok, all_messages} <- adapter.get_messages(conversation_id, adapter_opts) do
      cursor = get_in(conv.metadata || %{}, ["_ltm_cursor"])
      new_messages = filter_messages_after_cursor(all_messages, cursor)

      if new_messages == [] do
        {:ok, []}
      else
        extractor = Keyword.get(opts, :extractor, Extractor.Default)
        {:ok, existing_facts} = adapter.get_facts(conv.user_id, adapter_opts)

        context = %{
          user_id: conv.user_id,
          conversation_id: conv.id,
          provider: Keyword.get(opts, :provider),
          model: Keyword.get(opts, :model),
          existing_facts: existing_facts
        }

        case extractor.extract(new_messages, context, opts) do
          {:ok, raw_facts} ->
            saved = save_extracted_facts(raw_facts, conv.user_id, adapter, adapter_opts, opts)
            update_cursor(conv, new_messages, adapter, adapter_opts)
            {:ok, saved}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  defp filter_messages_after_cursor(messages, nil), do: messages

  defp filter_messages_after_cursor(messages, cursor_id) do
    case Enum.find_index(messages, &(&1.id == cursor_id)) do
      nil -> messages
      idx -> Enum.drop(messages, idx + 1)
    end
  end

  defp save_extracted_facts(raw_facts, user_id, adapter, adapter_opts, opts) do
    max_facts = Keyword.get(opts, :max_facts_per_user, 100)
    {:ok, existing_count} = adapter.count_facts(user_id, adapter_opts)
    {:ok, existing_facts} = adapter.get_facts(user_id, adapter_opts)
    existing_keys = MapSet.new(existing_facts, & &1.key)

    {saved, _count} =
      Enum.reduce(raw_facts, {[], existing_count}, fn %{key: key, value: value}, {acc, count} ->
        is_upsert = MapSet.member?(existing_keys, key)

        if not is_upsert and count >= max_facts do
          {acc, count}
        else
          fact = %Fact{user_id: user_id, key: key, value: value}

          case adapter.save_fact(fact, adapter_opts) do
            {:ok, saved} ->
              new_count = if is_upsert, do: count, else: count + 1
              {[saved | acc], new_count}

            {:error, _} ->
              {acc, count}
          end
        end
      end)

    Enum.reverse(saved)
  end

  defp update_cursor(conv, messages, adapter, adapter_opts) do
    last_msg = List.last(messages)

    if last_msg && last_msg.id do
      updated_metadata = Map.put(conv.metadata || %{}, "_ltm_cursor", last_msg.id)
      updated_conv = %{conv | metadata: updated_metadata}
      adapter.save_conversation(updated_conv, adapter_opts)
    end
  end

  # -- Profile Update --

  @doc """
  Regenerates and saves a user profile summary from their stored facts.

  Reads all facts for `user_id`, calls an AI provider (or a custom `:profile_fn`)
  to produce a new summary and metadata map, then upserts the result via
  `save_profile/2`. Requires `:provider` in opts (or a `:profile_fn` override).

  ## Options

    * `:provider` / `:model` — AI provider options
    * `:profile_fn` — `fun(existing_profile, facts, context, opts) :: {:ok, map} | {:error, term}`

  ## Examples

      {:ok, profile} = LongTermMemory.update_profile("u1", provider: :openai, model: "gpt-4o")
  """
  @spec update_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def update_profile(user_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :profile, :update], %{}, fn ->
      result =
        with {:ok, adapter, adapter_opts} <- resolve_profile_store(opts),
             {:ok, _, _} <- resolve_fact_store(opts) do
          do_update_profile_impl(user_id, adapter, adapter_opts, opts)
        end

      {result, %{}}
    end)
  end

  defp do_update_profile_impl(user_id, adapter, adapter_opts, opts) do
    existing_profile =
      case adapter.load_profile(user_id, adapter_opts) do
        {:ok, profile} -> profile
        {:error, :not_found} -> nil
      end

    {:ok, facts} = adapter.get_facts(user_id, adapter_opts)

    context = %{
      user_id: user_id,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model)
    }

    case do_update_profile(existing_profile, facts, context, opts) do
      {:ok, %{summary: summary, metadata: metadata}} ->
        profile = %Profile{
          user_id: user_id,
          summary: summary,
          metadata: metadata || %{}
        }

        adapter.save_profile(profile, adapter_opts)

      {:error, reason} ->
        {:error, {:profile_update_failed, reason}}
    end
  end

  defp do_update_profile(existing_profile, facts, context, opts) do
    case Keyword.get(opts, :profile_fn) do
      nil -> call_profile_ai(existing_profile, facts, context, opts)
      fun when is_function(fun, 4) -> fun.(existing_profile, facts, context, opts)
    end
  end

  defp call_profile_ai(existing_profile, facts, context, _opts) do
    provider = context[:provider]
    model = context[:model]

    unless provider do
      raise ArgumentError,
            "Profile update requires :provider in context or opts."
    end

    facts_text =
      facts
      |> Enum.map(fn f -> "- #{f.key}: #{f.value}" end)
      |> Enum.join("\n")

    existing_text =
      if existing_profile && existing_profile.summary do
        "Current profile:\n#{existing_profile.summary}\n\n"
      else
        ""
      end

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content: """
        You are updating a user profile based on known facts.
        #{existing_text}User facts:
        #{facts_text}

        Generate a concise user profile summary (2-3 sentences) and structured metadata.
        Return JSON: {"summary": "...", "metadata": {"key": "value", ...}}
        Output ONLY the JSON, no preamble.
        """
      },
      %PhoenixAI.Message{
        role: :user,
        content: "Generate the updated profile."
      }
    ]

    ai_opts =
      [provider: provider, model: model]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case AI.chat(prompt, ai_opts) do
      {:ok, response} -> parse_profile_response(response.content)
      {:error, _} = error -> error
    end
  end

  defp parse_profile_response(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"summary" => summary} = data} ->
        {:ok, %{summary: summary, metadata: Map.get(data, "metadata", %{})}}

      _ ->
        {:error, {:parse_error, json_string}}
    end
  end

  # -- Private --

  defp resolve_adapter(opts) do
    store = Keyword.get(opts, :store, :phoenix_ai_store_default)
    config = Instance.get_config(store)
    adapter_opts = Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts}
  end

  defp resolve_fact_store(opts) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    Code.ensure_loaded(adapter)

    if function_exported?(adapter, :save_fact, 2) do
      {:ok, adapter, adapter_opts}
    else
      {:error, :ltm_not_supported}
    end
  end

  defp resolve_profile_store(opts) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    Code.ensure_loaded(adapter)

    if function_exported?(adapter, :save_profile, 2) do
      {:ok, adapter, adapter_opts}
    else
      {:error, :ltm_not_supported}
    end
  end
end
