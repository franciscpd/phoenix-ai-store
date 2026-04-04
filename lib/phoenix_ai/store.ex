defmodule PhoenixAI.Store do
  @moduledoc """
  Supervisor and public API facade for PhoenixAI conversation storage.

  `PhoenixAI.Store` is both a Supervisor (managing adapter-specific children
  and an `Instance` GenServer) and the public API facade that delegates to the
  configured adapter.

  ## Starting a store

      {:ok, _pid} = PhoenixAI.Store.start_link(
        name: :my_store,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

  ## Using the API

      {:ok, conv} = PhoenixAI.Store.save_conversation(conversation, store: :my_store)
      {:ok, conv} = PhoenixAI.Store.load_conversation(conv.id, store: :my_store)
  """

  use Supervisor

  alias PhoenixAI.Store.{Config, Conversation, Instance, Message}

  # -- Supervisor --

  @doc "Starts the store supervisor with the given options."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, :phoenix_ai_store_default)
    opts = Keyword.put(opts, :name, name)
    config = Config.resolve(opts)
    Supervisor.start_link(__MODULE__, config, name: :"#{name}_supervisor")
  end

  @impl true
  def init(config) do
    children =
      adapter_children(config[:adapter], config) ++
        [{Instance, config}]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp adapter_children(PhoenixAI.Store.Adapters.ETS, config) do
    [{PhoenixAI.Store.Adapters.ETS.TableOwner, name: :"#{config[:name]}_table_owner"}]
  end

  defp adapter_children(_adapter, _config), do: []

  # -- Public API Facade --

  @doc """
  Saves a conversation. Generates a UUID v7 if `id` is nil and injects timestamps.
  """
  @spec save_conversation(Conversation.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def save_conversation(%Conversation{} = conv, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :save], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      if config[:user_id_required] && is_nil(conv.user_id) do
        {{:error, :user_id_required}, %{}}
      else
        now = DateTime.utc_now()

        conv =
          conv
          |> maybe_generate_id()
          |> maybe_set_inserted_at(now)
          |> Map.put(:updated_at, now)

        result = adapter.save_conversation(conv, adapter_opts)
        {result, %{}}
      end
    end)
  end

  @doc """
  Loads a conversation by ID, including its messages.
  """
  @spec load_conversation(String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_found | term()}
  def load_conversation(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :load], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      result = adapter.load_conversation(id, adapter_opts)

      result =
        with {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) <- result,
             true <- config[:soft_delete] do
          {:error, :not_found}
        else
          _ -> result
        end

      {result, %{}}
    end)
  end

  @doc """
  Lists conversations matching the given filters.
  """
  @spec list_conversations(keyword(), keyword()) ::
          {:ok, [Conversation.t()]} | {:error, term()}
  def list_conversations(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :list], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      filters =
        if config[:soft_delete],
          do: Keyword.put_new(filters, :exclude_deleted, true),
          else: filters

      result = adapter.list_conversations(filters, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Deletes a conversation by ID.
  """
  @spec delete_conversation(String.t(), keyword()) :: :ok | {:error, :not_found | term()}
  def delete_conversation(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :delete], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      result =
        if config[:soft_delete] do
          case adapter.load_conversation(id, adapter_opts) do
            {:ok, conv} ->
              adapter.save_conversation(%{conv | deleted_at: DateTime.utc_now()}, adapter_opts)
              |> case do
                {:ok, _} -> :ok
                error -> error
              end

            {:error, _} = error ->
              error
          end
        else
          adapter.delete_conversation(id, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Counts conversations matching the given filters.
  """
  @spec count_conversations(keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_conversations(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :count], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      filters =
        if config[:soft_delete],
          do: Keyword.put_new(filters, :exclude_deleted, true),
          else: filters

      result = adapter.count_conversations(filters, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Checks whether a conversation with the given ID exists.
  """
  @spec conversation_exists?(String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def conversation_exists?(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :exists], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)
      result = adapter.conversation_exists?(id, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Adds a message to a conversation. Generates a UUID v7 if `id` is nil
  and injects `inserted_at`.
  """
  @spec add_message(String.t(), Message.t(), keyword()) ::
          {:ok, Message.t()} | {:error, term()}
  def add_message(conversation_id, %Message{} = msg, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :message, :add], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      msg =
        msg
        |> maybe_generate_id()
        |> maybe_set_inserted_at(DateTime.utc_now())
        |> Map.put(:conversation_id, conversation_id)

      result = adapter.add_message(conversation_id, msg, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Gets all messages for a conversation, ordered by `inserted_at`.
  """
  @spec get_messages(String.t(), keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def get_messages(conversation_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :message, :get], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)
      result = adapter.get_messages(conversation_id, adapter_opts)
      {result, %{}}
    end)
  end

  # -- Private Helpers --

  defp resolve_adapter(opts) do
    store = Keyword.get(opts, :store, :phoenix_ai_store_default)
    config = Instance.get_config(store)
    adapter_opts = Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts, config}
  end

  defp maybe_generate_id(%{id: nil} = struct) do
    %{struct | id: Uniq.UUID.uuid7()}
  end

  defp maybe_generate_id(struct), do: struct

  defp maybe_set_inserted_at(%{inserted_at: nil} = struct, now) do
    %{struct | inserted_at: now}
  end

  defp maybe_set_inserted_at(struct, _now), do: struct
end
