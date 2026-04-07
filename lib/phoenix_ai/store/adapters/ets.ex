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
  @behaviour PhoenixAI.Store.Adapter.CostStore
  @behaviour PhoenixAI.Store.Adapter.EventStore

  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
  alias PhoenixAI.Store.CostTracking.CostRecord
  alias PhoenixAI.Store.EventLog.Event

  @doc "Inserts or updates a conversation in the ETS table, preserving `inserted_at` on upsert."
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

  @doc "Loads a conversation by ID from ETS and eagerly populates its messages."
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

  @doc "Returns all conversations from ETS matching the given filters, sorted by `inserted_at` descending."
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

  @doc "Deletes a conversation and all its messages and cost records from ETS."
  @impl true
  def delete_conversation(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_key, _conv}] ->
        :ets.delete(table, {:conversation, id})

        # Delete all messages for this conversation
        :ets.match_object(table, {{:message, id, :_}, :_})
        |> Enum.each(fn {key, _msg} -> :ets.delete(table, key) end)

        # Delete all cost records for this conversation
        :ets.match_object(table, {{:cost_record, id, :_}, :_})
        |> Enum.each(fn {key, _record} -> :ets.delete(table, key) end)

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Counts conversations in ETS matching the given filters.

  Note: O(n) — materializes the full filtered list then counts.
  Use the Ecto adapter for production workloads requiring efficient counts.
  """
  @impl true
  def count_conversations(filters, opts) do
    {:ok, conversations} = list_conversations(filters, opts)
    {:ok, length(conversations)}
  end

  @doc "Checks whether a conversation with the given ID exists in the ETS table."
  @impl true
  def conversation_exists?(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_key, _conv}] -> {:ok, true}
      [] -> {:ok, false}
    end
  end

  @doc "Appends a message to a conversation in ETS. Returns `{:error, :not_found}` if the conversation does not exist."
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

  @doc "Returns all messages for a conversation from ETS, sorted by `inserted_at` ascending."
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

  @doc "Upserts a fact in ETS keyed on `{user_id, key}`, preserving `inserted_at` on update."
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

  @doc "Returns all facts for a user from ETS, sorted by `inserted_at` ascending."
  @impl PhoenixAI.Store.Adapter.FactStore
  def get_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    facts =
      :ets.match_object(table, {{:fact, user_id, :_}, :_})
      |> Enum.map(fn {_key, fact} -> fact end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:ok, facts}
  end

  @doc "Deletes a fact by `{user_id, key}` from ETS. Always returns `:ok`."
  @impl PhoenixAI.Store.Adapter.FactStore
  def delete_fact(user_id, key, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:fact, user_id, key})
    :ok
  end

  @doc "Counts all facts for a user in ETS via a full match scan."
  @impl PhoenixAI.Store.Adapter.FactStore
  def count_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    count = :ets.match_object(table, {{:fact, user_id, :_}, :_}) |> length()
    {:ok, count}
  end

  # -- ProfileStore callbacks --

  @doc "Upserts a user profile in ETS keyed on `user_id`, preserving `inserted_at` on update."
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

  @doc "Loads a user profile from ETS. Returns `{:error, :not_found}` if absent."
  @impl PhoenixAI.Store.Adapter.ProfileStore
  def load_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:profile, user_id}) do
      [{_key, profile}] -> {:ok, profile}
      [] -> {:error, :not_found}
    end
  end

  @doc "Deletes a user profile from ETS. Always returns `:ok`."
  @impl PhoenixAI.Store.Adapter.ProfileStore
  def delete_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:profile, user_id})
    :ok
  end

  # -- TokenUsage callbacks --

  @doc "Sums `token_count` across all messages for a conversation stored in ETS."
  @impl PhoenixAI.Store.Adapter.TokenUsage
  def sum_conversation_tokens(conversation_id, opts) do
    table = Keyword.fetch!(opts, :table)

    total =
      :ets.match_object(table, {{:message, conversation_id, :_}, :_})
      |> Enum.reduce(0, fn {_key, msg}, acc -> acc + (msg.token_count || 0) end)

    {:ok, total}
  end

  @doc "Sums `token_count` across all messages in all conversations belonging to a user in ETS."
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

  # -- CostStore callbacks --

  @doc "Inserts a cost record into ETS keyed on `{conversation_id, record_id}`."
  @impl PhoenixAI.Store.Adapter.CostStore
  def save_cost_record(%CostRecord{} = record, opts) do
    table = Keyword.fetch!(opts, :table)

    record = %{
      record
      | id: record.id || Uniq.UUID.uuid7(),
        recorded_at: record.recorded_at || DateTime.utc_now()
    }

    :ets.insert(table, {{:cost_record, record.conversation_id, record.id}, record})
    {:ok, record}
  end

  @doc "Returns all cost records for a conversation from ETS, sorted by `recorded_at` ascending."
  @impl PhoenixAI.Store.Adapter.CostStore
  def get_cost_records(conversation_id, opts) do
    table = Keyword.fetch!(opts, :table)

    records =
      :ets.match_object(table, {{:cost_record, conversation_id, :_}, :_})
      |> Enum.map(fn {_key, record} -> record end)
      |> Enum.sort_by(& &1.recorded_at, {:asc, DateTime})

    {:ok, records}
  end

  @doc "Sums `total_cost` across all cost records matching the given filters in ETS."
  @impl PhoenixAI.Store.Adapter.CostStore
  def sum_cost(filters, opts) do
    table = Keyword.fetch!(opts, :table)

    total =
      :ets.match_object(table, {{:cost_record, :_, :_}, :_})
      |> Enum.map(fn {_key, record} -> record end)
      |> apply_cost_filters(filters)
      |> Enum.reduce(Decimal.new("0"), fn record, acc ->
        Decimal.add(acc, record.total_cost)
      end)

    {:ok, total}
  end

  defp apply_cost_filters(records, []), do: records

  defp apply_cost_filters(records, [{:user_id, user_id} | rest]) do
    records
    |> Enum.filter(&(&1.user_id == user_id))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [{:conversation_id, conversation_id} | rest]) do
    records
    |> Enum.filter(&(&1.conversation_id == conversation_id))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [{:provider, provider} | rest]) do
    records
    |> Enum.filter(&(&1.provider == provider))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [{:model, model} | rest]) do
    records
    |> Enum.filter(&(&1.model == model))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [{:after, dt} | rest]) do
    records
    |> Enum.filter(&(DateTime.compare(&1.recorded_at, dt) in [:gt, :eq]))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [{:before, dt} | rest]) do
    records
    |> Enum.filter(&(DateTime.compare(&1.recorded_at, dt) in [:lt, :eq]))
    |> apply_cost_filters(rest)
  end

  defp apply_cost_filters(records, [_ | rest]), do: apply_cost_filters(records, rest)

  # -- EventStore callbacks --

  @doc "Appends an event to the ETS table keyed on `{inserted_at, id}` for stable ordering."
  @impl PhoenixAI.Store.Adapter.EventStore
  def log_event(%Event{} = event, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    event = %{
      event
      | id: event.id || Uniq.UUID.uuid7(),
        inserted_at: event.inserted_at || now
    }

    :ets.insert(table, {{:event, event.inserted_at, event.id}, event})
    {:ok, event}
  end

  @doc "Returns a paginated, filtered list of events from ETS with an opaque cursor for the next page."
  @impl PhoenixAI.Store.Adapter.EventStore
  def list_events(filters, opts) do
    table = Keyword.fetch!(opts, :table)
    limit = Keyword.get(filters, :limit)
    cursor = Keyword.get(filters, :cursor)

    events =
      :ets.match_object(table, {{:event, :_, :_}, :_})
      |> Enum.map(fn {_key, event} -> event end)
      |> filter_events(filters)
      |> Enum.sort_by(&{&1.inserted_at, &1.id}, fn {ts1, id1}, {ts2, id2} ->
        case DateTime.compare(ts1, ts2) do
          :lt -> true
          :gt -> false
          :eq -> id1 < id2
        end
      end)
      |> maybe_apply_cursor(cursor)
      |> maybe_take(limit)

    next_cursor =
      if limit && length(events) == limit do
        last = List.last(events)
        encode_event_cursor(last)
      else
        nil
      end

    {:ok, %{events: events, next_cursor: next_cursor}}
  end

  @doc "Counts events in ETS matching the given filters."
  @impl PhoenixAI.Store.Adapter.EventStore
  def count_events(filters, opts) do
    table = Keyword.fetch!(opts, :table)

    count =
      :ets.match_object(table, {{:event, :_, :_}, :_})
      |> Enum.map(fn {_key, event} -> event end)
      |> filter_events(filters)
      |> length()

    {:ok, count}
  end

  # -- Event filtering helpers --

  defp filter_events(events, []), do: events

  defp filter_events(events, [{:conversation_id, conv_id} | rest]) do
    events
    |> Enum.filter(&(&1.conversation_id == conv_id))
    |> filter_events(rest)
  end

  defp filter_events(events, [{:user_id, user_id} | rest]) do
    events
    |> Enum.filter(&(&1.user_id == user_id))
    |> filter_events(rest)
  end

  defp filter_events(events, [{:type, type} | rest]) do
    events
    |> Enum.filter(&(&1.type == type))
    |> filter_events(rest)
  end

  defp filter_events(events, [{:after, dt} | rest]) do
    events
    |> Enum.filter(&(DateTime.compare(&1.inserted_at, dt) in [:gt, :eq]))
    |> filter_events(rest)
  end

  defp filter_events(events, [{:before, dt} | rest]) do
    events
    |> Enum.filter(&(DateTime.compare(&1.inserted_at, dt) in [:lt, :eq]))
    |> filter_events(rest)
  end

  defp filter_events(events, [_ | rest]), do: filter_events(events, rest)

  defp maybe_apply_cursor(events, nil), do: events

  defp maybe_apply_cursor(events, cursor) do
    {cursor_ts, cursor_id} = decode_event_cursor(cursor)

    Enum.drop_while(events, fn event ->
      case DateTime.compare(event.inserted_at, cursor_ts) do
        :lt -> true
        :gt -> false
        :eq -> event.id <= cursor_id
      end
    end)
  end

  defp maybe_take(events, nil), do: events
  defp maybe_take(events, limit), do: Enum.take(events, limit)

  defp encode_event_cursor(%Event{} = event) do
    PhoenixAI.Store.Cursor.encode(event.inserted_at, event.id)
  end

  defp decode_event_cursor(cursor) do
    {:ok, {ts, id}} = PhoenixAI.Store.Cursor.decode(cursor)
    {ts, id}
  end
end
