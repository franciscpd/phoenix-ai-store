defmodule PhoenixAI.Store.Adapters.ETS do
  @moduledoc """
  In-memory ETS adapter for `PhoenixAI.Store.Adapter`.

  All functions receive an `opts` keyword list containing a `:table` key
  with the ETS table reference (typically owned by a `TableOwner` GenServer).

  ## Storage Layout

  - Conversations: `{{:conversation, id}, %Conversation{}}`
  - Messages: `{{:message, conversation_id, message_id}, %Message{}}`
  - Facts: `{{:fact, user_id, key}, %Fact{}}`
  - Profiles: `{{:profile, user_id}, %Profile{}}`
  """

  @behaviour PhoenixAI.Store.Adapter
  @behaviour PhoenixAI.Store.Adapter.FactStore
  @behaviour PhoenixAI.Store.Adapter.ProfileStore
  @behaviour PhoenixAI.Store.Adapter.TokenUsage

  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}

  @impl true
  def save_conversation(%Conversation{} = conversation, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    conversation =
      case :ets.lookup(table, {:conversation, conversation.id}) do
        [{_key, existing}] ->
          # Preserve original inserted_at on upsert
          %{
            conversation
            | inserted_at: existing.inserted_at,
              updated_at: conversation.updated_at || now
          }

        [] ->
          %{
            conversation
            | inserted_at: conversation.inserted_at || now,
              updated_at: conversation.updated_at || now
          }
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
      |> filter_by_date_after(Keyword.get(filters, :inserted_after))
      |> filter_by_date_before(Keyword.get(filters, :inserted_before))
      |> filter_by_exclude_deleted(Keyword.get(filters, :exclude_deleted, false))
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
  # NOTE: O(n) — materializes the full filtered list then counts.
  # Acceptable for dev/test adapter. For production, use the Ecto adapter.
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
        # Respect values already set by facade; only fill in defaults for nil fields
        message = %{
          message
          | id: message.id || Uniq.UUID.uuid7(),
            conversation_id: conversation_id,
            inserted_at: message.inserted_at || DateTime.utc_now()
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

  defp filter_by_date_after(conversations, nil), do: conversations

  defp filter_by_date_after(conversations, dt) do
    Enum.filter(conversations, &(DateTime.compare(&1.inserted_at, dt) in [:gt, :eq]))
  end

  defp filter_by_date_before(conversations, nil), do: conversations

  defp filter_by_date_before(conversations, dt) do
    Enum.filter(conversations, &(DateTime.compare(&1.inserted_at, dt) in [:lt, :eq]))
  end

  defp filter_by_exclude_deleted(conversations, false), do: conversations

  defp filter_by_exclude_deleted(conversations, true) do
    Enum.filter(conversations, &is_nil(&1.deleted_at))
  end

  defp maybe_offset(conversations, nil), do: conversations
  defp maybe_offset(conversations, offset), do: Enum.drop(conversations, offset)

  defp maybe_limit(conversations, nil), do: conversations
  defp maybe_limit(conversations, limit), do: Enum.take(conversations, limit)

  # -- FactStore callbacks --

  @impl PhoenixAI.Store.Adapter.FactStore
  def save_fact(%Fact{} = fact, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    fact =
      case :ets.match_object(table, {{:fact, fact.user_id, fact.key}, :_}) do
        [{_key, existing}] ->
          %{
            fact
            | id: existing.id,
              inserted_at: existing.inserted_at,
              updated_at: now
          }

        [] ->
          %{
            fact
            | id: fact.id || Uniq.UUID.uuid7(),
              inserted_at: fact.inserted_at || now,
              updated_at: fact.updated_at || now
          }
      end

    :ets.insert(table, {{:fact, fact.user_id, fact.key}, fact})
    {:ok, fact}
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def get_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    facts =
      :ets.match_object(table, {{:fact, user_id, :_}, :_})
      |> Enum.map(fn {_key, fact} -> fact end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:ok, facts}
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def delete_fact(user_id, key, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:fact, user_id, key})
    :ok
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def count_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    count = :ets.match_object(table, {{:fact, user_id, :_}, :_}) |> length()
    {:ok, count}
  end

  # -- ProfileStore callbacks --

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def save_profile(%Profile{} = profile, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    profile =
      case :ets.lookup(table, {:profile, profile.user_id}) do
        [{_key, existing}] ->
          %{
            profile
            | id: existing.id,
              inserted_at: existing.inserted_at,
              updated_at: now
          }

        [] ->
          %{
            profile
            | id: profile.id || Uniq.UUID.uuid7(),
              inserted_at: profile.inserted_at || now,
              updated_at: profile.updated_at || now
          }
      end

    :ets.insert(table, {{:profile, profile.user_id}, profile})
    {:ok, profile}
  end

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def load_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:profile, user_id}) do
      [{_key, profile}] -> {:ok, profile}
      [] -> {:error, :not_found}
    end
  end

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def delete_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:profile, user_id})
    :ok
  end

  # -- TokenUsage callbacks --

  @impl PhoenixAI.Store.Adapter.TokenUsage
  def sum_conversation_tokens(conversation_id, opts) do
    table = Keyword.fetch!(opts, :table)

    total =
      :ets.match_object(table, {{:message, conversation_id, :_}, :_})
      |> Enum.reduce(0, fn {_key, msg}, acc -> acc + (msg.token_count || 0) end)

    {:ok, total}
  end

  @impl PhoenixAI.Store.Adapter.TokenUsage
  def sum_user_tokens(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    conversation_ids =
      :ets.match_object(table, {{:conversation, :_}, :_})
      |> Enum.filter(fn {_key, conv} -> conv.user_id == user_id end)
      |> Enum.map(fn {_key, conv} -> conv.id end)

    total =
      Enum.reduce(conversation_ids, 0, fn conv_id, acc ->
        :ets.match_object(table, {{:message, conv_id, :_}, :_})
        |> Enum.reduce(acc, fn {_key, msg}, inner_acc ->
          inner_acc + (msg.token_count || 0)
        end)
      end)

    {:ok, total}
  end
end
