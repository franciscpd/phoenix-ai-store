defmodule PhoenixAI.Store.Adapters.ETS do
  @moduledoc """
  In-memory ETS adapter for `PhoenixAI.Store.Adapter`.

  All functions receive an `opts` keyword list containing a `:table` key
  with the ETS table reference (typically owned by a `TableOwner` GenServer).

  ## Storage Layout

  - Conversations: `{{:conversation, id}, %Conversation{}}`
  - Messages: `{{:message, conversation_id, message_id}, %Message{}}`
  """

  @behaviour PhoenixAI.Store.Adapter

  alias PhoenixAI.Store.{Conversation, Message}

  @impl true
  def save_conversation(%Conversation{} = conversation, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    conversation =
      case :ets.lookup(table, {:conversation, conversation.id}) do
        [{_key, existing}] ->
          %{conversation | inserted_at: existing.inserted_at, updated_at: now}

        [] ->
          %{conversation | inserted_at: conversation.inserted_at || now, updated_at: now}
      end

    :ets.insert(table, {{:conversation, conversation.id}, conversation})
    {:ok, conversation}
  end

  @impl true
  def load_conversation(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_key, conversation}] ->
        {:ok, messages} = get_messages(id, opts)
        {:ok, %{conversation | messages: messages}}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_conversations(filters, opts) do
    table = Keyword.fetch!(opts, :table)

    conversations =
      :ets.match_object(table, {{:conversation, :_}, :_})
      |> Enum.map(fn {_key, conv} -> conv end)
      |> filter_by_user_id(Keyword.get(filters, :user_id))
      |> filter_by_tags(Keyword.get(filters, :tags))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> maybe_offset(Keyword.get(filters, :offset))
      |> maybe_limit(Keyword.get(filters, :limit))

    {:ok, conversations}
  end

  @impl true
  def delete_conversation(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_key, _conv}] ->
        :ets.delete(table, {:conversation, id})

        # Delete all messages for this conversation
        :ets.match_object(table, {{:message, id, :_}, :_})
        |> Enum.each(fn {key, _msg} -> :ets.delete(table, key) end)

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def count_conversations(filters, opts) do
    {:ok, conversations} = list_conversations(filters, opts)
    {:ok, length(conversations)}
  end

  @impl true
  def conversation_exists?(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_key, _conv}] -> {:ok, true}
      [] -> {:ok, false}
    end
  end

  @impl true
  def add_message(conversation_id, %Message{} = message, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, conversation_id}) do
      [{_key, _conv}] ->
        message = %{
          message
          | id: Uniq.UUID.uuid7(),
            conversation_id: conversation_id,
            inserted_at: DateTime.utc_now()
        }

        :ets.insert(table, {{:message, conversation_id, message.id}, message})
        {:ok, message}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def get_messages(conversation_id, opts) do
    table = Keyword.fetch!(opts, :table)

    messages =
      :ets.match_object(table, {{:message, conversation_id, :_}, :_})
      |> Enum.map(fn {_key, msg} -> msg end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:ok, messages}
  end

  # -- Private Helpers --

  defp filter_by_user_id(conversations, nil), do: conversations

  defp filter_by_user_id(conversations, user_id) do
    Enum.filter(conversations, &(&1.user_id == user_id))
  end

  defp filter_by_tags(conversations, nil), do: conversations

  defp filter_by_tags(conversations, tags) do
    Enum.filter(conversations, fn conv ->
      Enum.all?(tags, &(&1 in conv.tags))
    end)
  end

  defp maybe_offset(conversations, nil), do: conversations
  defp maybe_offset(conversations, offset), do: Enum.drop(conversations, offset)

  defp maybe_limit(conversations, nil), do: conversations
  defp maybe_limit(conversations, limit), do: Enum.take(conversations, limit)
end
