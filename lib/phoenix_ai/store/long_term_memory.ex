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
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.save_fact(fact, adapter_opts)
  end

  @spec get_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def get_facts(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.get_facts(user_id, adapter_opts)
  end

  @spec delete_fact(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_fact(user_id, key, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.delete_fact(user_id, key, adapter_opts)
  end

  # -- Manual CRUD: Profiles --

  @spec save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def save_profile(%Profile{} = profile, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.save_profile(profile, adapter_opts)
  end

  @spec get_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, :not_found | term()}
  def get_profile(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.load_profile(user_id, adapter_opts)
  end

  @spec delete_profile(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_profile(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.delete_profile(user_id, adapter_opts)
  end

  # -- Extraction --

  @spec extract_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def extract_facts(conversation_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)

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

    Enum.reduce(raw_facts, [], fn %{key: key, value: value}, acc ->
      {:ok, count} = adapter.count_facts(user_id, adapter_opts)

      if count >= max_facts do
        acc
      else
        fact = %Fact{user_id: user_id, key: key, value: value}

        case adapter.save_fact(fact, adapter_opts) do
          {:ok, saved} -> acc ++ [saved]
          {:error, _} -> acc
        end
      end
    end)
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
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    check_fact_store!(adapter)

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

  defp check_fact_store!(adapter) do
    Code.ensure_loaded(adapter)

    unless function_exported?(adapter, :save_fact, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.FactStore. " <>
              "Long-term memory requires an adapter that supports fact storage."
    end
  end

  defp check_profile_store!(adapter) do
    Code.ensure_loaded(adapter)

    unless function_exported?(adapter, :save_profile, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.ProfileStore. " <>
              "Long-term memory requires an adapter that supports profile storage."
    end
  end
end
