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
        context = %{
          user_id: conv.user_id,
          conversation_id: conv.id,
          provider: Keyword.get(opts, :provider),
          model: Keyword.get(opts, :model)
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

  defp call_profile_ai(existing_profile, facts, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

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
