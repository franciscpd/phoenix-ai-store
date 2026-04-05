if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Adapters.Ecto do
    @moduledoc """
    Ecto/Postgres adapter for `PhoenixAI.Store.Adapter`.

    All callbacks receive an `opts` keyword list containing a `:repo` key
    pointing to the Ecto.Repo module to use for queries.

    This module is only compiled when Ecto is available as a dependency.
    """

    @behaviour PhoenixAI.Store.Adapter
    @behaviour PhoenixAI.Store.Adapter.FactStore
    @behaviour PhoenixAI.Store.Adapter.ProfileStore
    @behaviour PhoenixAI.Store.Adapter.TokenUsage
    @behaviour PhoenixAI.Store.Adapter.CostStore
    @behaviour PhoenixAI.Store.Adapter.EventStore

    import Ecto.Query

    alias PhoenixAI.Store.{Conversation, Message}
    alias PhoenixAI.Store.Schemas.Conversation, as: ConvSchema
    alias PhoenixAI.Store.Schemas.Message, as: MsgSchema
    alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
    alias PhoenixAI.Store.Schemas.Fact, as: FactSchema
    alias PhoenixAI.Store.Schemas.Profile, as: ProfileSchema
    alias PhoenixAI.Store.CostTracking.CostRecord
    alias PhoenixAI.Store.Schemas.CostRecord, as: CostRecordSchema
    alias PhoenixAI.Store.EventLog.Event
    alias PhoenixAI.Store.Schemas.Event, as: EventSchema

    @doc "Inserts or updates a conversation row in the database via the configured Repo."
    @impl true
    def save_conversation(%Conversation{} = conversation, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ConvSchema.from_store_struct(conversation)

      case repo.one(from(c in conv_source(opts), where: c.id == ^conversation.id)) do
        nil ->
          %ConvSchema{}
          |> Ecto.put_meta(source: conv_table_name(opts))
          |> ConvSchema.changeset(attrs)
          |> repo.insert()
          |> handle_conv_result()

        existing ->
          existing
          |> ConvSchema.changeset(attrs)
          |> repo.update()
          |> handle_conv_result()
      end
    end

    @doc "Loads a conversation by ID from the database, preloading messages ordered by `inserted_at`."
    @impl true
    def load_conversation(id, opts) do
      if valid_uuid?(id), do: do_load_conversation(id, opts), else: {:error, :not_found}
    end

    defp do_load_conversation(id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from c in conv_source(opts),
          where: c.id == ^id,
          preload: [messages: ^from(m in msg_source(opts), order_by: [asc: m.inserted_at])]

      case repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, ConvSchema.to_store_struct(schema)}
      end
    end

    @doc "Queries conversations from the database with optional filters, ordered by `inserted_at` descending."
    @impl true
    def list_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from(c in conv_source(opts), order_by: [desc: c.inserted_at])
        |> apply_filters(filters)

      conversations =
        repo.all(query)
        |> Enum.map(&ConvSchema.to_store_struct/1)

      {:ok, conversations}
    end

    @doc "Deletes a conversation row from the database. Returns `{:error, :not_found}` if absent."
    @impl true
    def delete_conversation(id, opts) do
      if valid_uuid?(id), do: do_delete_conversation(id, opts), else: {:error, :not_found}
    end

    defp do_delete_conversation(id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.one(from(c in conv_source(opts), where: c.id == ^id)) do
        nil -> {:error, :not_found}
        schema -> repo.delete(schema) |> handle_delete_result()
      end
    end

    @doc "Counts conversation rows matching the given filters using a database `COUNT` query."
    @impl true
    def count_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from(c in conv_source(opts), select: count(c.id))
        |> apply_filters(filters)

      {:ok, repo.one(query)}
    end

    @doc "Checks whether a conversation exists in the database using `Repo.exists?/1`."
    @impl true
    def conversation_exists?(id, opts) do
      if valid_uuid?(id), do: do_conversation_exists?(id, opts), else: {:ok, false}
    end

    defp do_conversation_exists?(id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      {:ok, repo.exists?(from(c in conv_source(opts), where: c.id == ^id))}
    end

    @doc "Inserts a message row into the database. Returns `{:error, :not_found}` if the conversation does not exist."
    @impl true
    def add_message(conversation_id, %Message{} = message, opts) do
      if valid_uuid?(conversation_id) do
        do_add_message(conversation_id, message, opts)
      else
        {:error, :not_found}
      end
    end

    defp do_add_message(conversation_id, message, opts) do
      repo = Keyword.fetch!(opts, :repo)

      if repo.exists?(from(c in conv_source(opts), where: c.id == ^conversation_id)) do
        attrs =
          MsgSchema.from_store_struct(message)
          |> Map.update(:id, Uniq.UUID.uuid7(), fn id -> id || Uniq.UUID.uuid7() end)
          |> Map.put(:conversation_id, conversation_id)

        %MsgSchema{}
        |> Ecto.put_meta(source: msg_table_name(opts))
        |> MsgSchema.changeset(attrs)
        |> repo.insert()
        |> handle_msg_result()
      else
        {:error, :not_found}
      end
    end

    @doc "Queries all messages for a conversation from the database, ordered by `inserted_at` ascending."
    @impl true
    def get_messages(conversation_id, opts) do
      if valid_uuid?(conversation_id),
        do: do_get_messages(conversation_id, opts),
        else: {:ok, []}
    end

    defp do_get_messages(conversation_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      messages =
        from(m in msg_source(opts),
          where: m.conversation_id == ^conversation_id,
          order_by: [asc: m.inserted_at]
        )
        |> repo.all()
        |> Enum.map(&MsgSchema.to_store_struct/1)

      {:ok, messages}
    end

    # -- FactStore --

    @doc "Upserts a fact row in the database using `ON CONFLICT DO UPDATE` on `{user_id, key}`."
    @impl PhoenixAI.Store.Adapter.FactStore
    def save_fact(%Fact{} = fact, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = FactSchema.from_store_struct(fact) |> Map.put_new(:id, Uniq.UUID.uuid7())

      %FactSchema{}
      |> Ecto.put_meta(source: fact_table_name(opts))
      |> FactSchema.changeset(attrs)
      |> repo.insert(
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: [:user_id, :key],
        returning: true
      )
      |> handle_fact_result()
    end

    @doc "Queries all facts for a user from the database, ordered by `inserted_at` ascending."
    @impl PhoenixAI.Store.Adapter.FactStore
    def get_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      facts =
        from(f in fact_source(opts), where: f.user_id == ^user_id, order_by: [asc: f.inserted_at])
        |> repo.all()
        |> Enum.map(&FactSchema.to_store_struct/1)

      {:ok, facts}
    end

    @doc "Deletes all fact rows matching `{user_id, key}` from the database."
    @impl PhoenixAI.Store.Adapter.FactStore
    def delete_fact(user_id, key, opts) do
      repo = Keyword.fetch!(opts, :repo)

      from(f in fact_source(opts), where: f.user_id == ^user_id and f.key == ^key)
      |> repo.delete_all()

      :ok
    end

    @doc "Counts fact rows for a user using a database `COUNT` query."
    @impl PhoenixAI.Store.Adapter.FactStore
    def count_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      count =
        from(f in fact_source(opts), where: f.user_id == ^user_id, select: count(f.id))
        |> repo.one()

      {:ok, count}
    end

    # -- ProfileStore --

    @doc "Upserts a profile row in the database using `ON CONFLICT DO UPDATE` on `user_id`."
    @impl PhoenixAI.Store.Adapter.ProfileStore
    def save_profile(%Profile{} = profile, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ProfileSchema.from_store_struct(profile) |> Map.put_new(:id, Uniq.UUID.uuid7())

      %ProfileSchema{}
      |> Ecto.put_meta(source: profile_table_name(opts))
      |> ProfileSchema.changeset(attrs)
      |> repo.insert(
        on_conflict: {:replace, [:summary, :metadata, :updated_at]},
        conflict_target: [:user_id],
        returning: true
      )
      |> handle_profile_result()
    end

    @doc "Loads a user profile from the database. Returns `{:error, :not_found}` if absent."
    @impl PhoenixAI.Store.Adapter.ProfileStore
    def load_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.one(from(p in profile_source(opts), where: p.user_id == ^user_id)) do
        nil -> {:error, :not_found}
        schema -> {:ok, ProfileSchema.to_store_struct(schema)}
      end
    end

    @doc "Deletes all profile rows for a user from the database."
    @impl PhoenixAI.Store.Adapter.ProfileStore
    def delete_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      from(p in profile_source(opts), where: p.user_id == ^user_id) |> repo.delete_all()
      :ok
    end

    # -- TokenUsage --

    @doc "Sums `token_count` for all messages in a conversation using a database `SUM` aggregate."
    @impl PhoenixAI.Store.Adapter.TokenUsage
    def sum_conversation_tokens(conversation_id, opts) do
      if valid_uuid?(conversation_id) do
        repo = Keyword.fetch!(opts, :repo)

        total =
          from(m in msg_source(opts),
            where: m.conversation_id == ^conversation_id,
            select: coalesce(sum(m.token_count), 0)
          )
          |> repo.one()

        {:ok, total}
      else
        {:ok, 0}
      end
    end

    @doc "Sums `token_count` across all messages in all conversations belonging to a user via a database join."
    @impl PhoenixAI.Store.Adapter.TokenUsage
    def sum_user_tokens(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      total =
        from(m in msg_source(opts),
          join: c in ^conv_source(opts),
          on: m.conversation_id == c.id,
          where: c.user_id == ^user_id,
          select: coalesce(sum(m.token_count), 0)
        )
        |> repo.one()

      {:ok, total}
    end

    # -- Private Helpers --

    defp apply_filters(query, []), do: query

    defp apply_filters(query, [{:user_id, user_id} | rest]) do
      query
      |> where([c], c.user_id == ^user_id)
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:tags, tags} | rest]) do
      query
      |> where([c], fragment("? @> ?", c.tags, ^tags))
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:limit, limit} | rest]) do
      query
      |> limit(^limit)
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:offset, offset} | rest]) do
      query
      |> offset(^offset)
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:inserted_after, dt} | rest]) do
      query
      |> where([c], c.inserted_at >= ^dt)
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:inserted_before, dt} | rest]) do
      query
      |> where([c], c.inserted_at <= ^dt)
      |> apply_filters(rest)
    end

    defp apply_filters(query, [{:exclude_deleted, true} | rest]) do
      query
      |> where([c], is_nil(c.deleted_at))
      |> apply_filters(rest)
    end

    defp apply_filters(query, [_ | rest]), do: apply_filters(query, rest)

    defp conv_source(opts) do
      {conv_table_name(opts), ConvSchema}
    end

    defp msg_source(opts) do
      {msg_table_name(opts), MsgSchema}
    end

    defp conv_table_name(opts) do
      Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "conversations"
    end

    defp msg_table_name(opts) do
      Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "messages"
    end

    defp handle_conv_result({:ok, schema}), do: {:ok, ConvSchema.to_store_struct(schema)}
    defp handle_conv_result({:error, changeset}), do: {:error, changeset}

    defp handle_msg_result({:ok, schema}), do: {:ok, MsgSchema.to_store_struct(schema)}
    defp handle_msg_result({:error, changeset}), do: {:error, changeset}

    defp handle_delete_result({:ok, _schema}), do: :ok
    defp handle_delete_result({:error, changeset}), do: {:error, changeset}

    defp fact_source(opts), do: {fact_table_name(opts), FactSchema}
    defp profile_source(opts), do: {profile_table_name(opts), ProfileSchema}
    defp fact_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "facts"

    defp profile_table_name(opts),
      do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "profiles"

    defp handle_fact_result({:ok, schema}), do: {:ok, FactSchema.to_store_struct(schema)}
    defp handle_fact_result({:error, changeset}), do: {:error, changeset}

    defp handle_profile_result({:ok, schema}), do: {:ok, ProfileSchema.to_store_struct(schema)}
    defp handle_profile_result({:error, changeset}), do: {:error, changeset}

    # -- CostStore --

    @doc "Inserts a cost record row into the database. Records are immutable once written."
    @impl PhoenixAI.Store.Adapter.CostStore
    def save_cost_record(%CostRecord{} = record, opts) do
      repo = Keyword.fetch!(opts, :repo)

      attrs =
        CostRecordSchema.from_store_struct(record)
        |> Map.update(:id, Uniq.UUID.uuid7(), fn id -> id || Uniq.UUID.uuid7() end)

      %CostRecordSchema{}
      |> Ecto.put_meta(source: cost_record_table_name(opts))
      |> CostRecordSchema.changeset(attrs)
      |> repo.insert()
      |> handle_cost_record_result()
    end

    @doc "Queries all cost records for a conversation from the database, ordered by `recorded_at` ascending."
    @impl PhoenixAI.Store.Adapter.CostStore
    def get_cost_records(conversation_id, opts) do
      if valid_uuid?(conversation_id) do
        repo = Keyword.fetch!(opts, :repo)

        records =
          from(cr in cost_record_source(opts),
            where: cr.conversation_id == ^conversation_id,
            order_by: [asc: cr.recorded_at]
          )
          |> repo.all()
          |> Enum.map(&CostRecordSchema.to_store_struct/1)

        {:ok, records}
      else
        {:ok, []}
      end
    end

    @doc "Sums `total_cost` across cost records matching the given filters using a database `SUM` aggregate."
    @impl PhoenixAI.Store.Adapter.CostStore
    def sum_cost(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      total =
        from(cr in cost_record_source(opts),
          select: coalesce(sum(cr.total_cost), ^Decimal.new("0"))
        )
        |> apply_cost_filters(filters)
        |> repo.one()

      {:ok, total}
    end

    defp apply_cost_filters(query, []), do: query

    defp apply_cost_filters(query, [{:user_id, user_id} | rest]) do
      query
      |> where([cr], cr.user_id == ^user_id)
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [{:conversation_id, conversation_id} | rest]) do
      query
      |> where([cr], cr.conversation_id == ^conversation_id)
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [{:provider, provider} | rest]) do
      query
      |> where([cr], cr.provider == ^to_string(provider))
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [{:model, model} | rest]) do
      query
      |> where([cr], cr.model == ^model)
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [{:after, dt} | rest]) do
      query
      |> where([cr], cr.recorded_at >= ^dt)
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [{:before, dt} | rest]) do
      query
      |> where([cr], cr.recorded_at <= ^dt)
      |> apply_cost_filters(rest)
    end

    defp apply_cost_filters(query, [_ | rest]), do: apply_cost_filters(query, rest)

    defp cost_record_source(opts), do: {cost_record_table_name(opts), CostRecordSchema}

    defp cost_record_table_name(opts),
      do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "cost_records"

    defp handle_cost_record_result({:ok, schema}),
      do: {:ok, CostRecordSchema.to_store_struct(schema)}

    defp handle_cost_record_result({:error, changeset}), do: {:error, changeset}

    defp valid_uuid?(id) when is_binary(id) do
      case Ecto.UUID.cast(id) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp valid_uuid?(_), do: false

    # -- EventStore --

    @doc "Inserts an event row into the database. The event log is append-only — no updates or deletes."
    @impl PhoenixAI.Store.Adapter.EventStore
    def log_event(%Event{} = event, opts) do
      repo = Keyword.fetch!(opts, :repo)

      attrs =
        EventSchema.from_store_struct(event)
        |> Map.update(:id, Uniq.UUID.uuid7(), fn id -> id || Uniq.UUID.uuid7() end)
        |> Map.update(:inserted_at, DateTime.utc_now(), fn ts -> ts || DateTime.utc_now() end)

      %EventSchema{}
      |> Ecto.put_meta(source: event_table_name(opts))
      |> EventSchema.changeset(attrs)
      |> repo.insert()
      |> handle_event_result()
    end

    @doc "Queries a paginated, filtered list of events from the database with an opaque cursor for the next page."
    @impl PhoenixAI.Store.Adapter.EventStore
    def list_events(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)
      limit = Keyword.get(filters, :limit)
      cursor = Keyword.get(filters, :cursor)

      query =
        from(e in event_source(opts), order_by: [asc: e.inserted_at, asc: e.id])
        |> apply_event_filters(filters)
        |> maybe_apply_ecto_cursor(cursor)
        |> maybe_apply_ecto_limit(limit)

      events =
        repo.all(query)
        |> Enum.map(&EventSchema.to_store_struct/1)

      next_cursor =
        if limit && length(events) == limit do
          last = List.last(events)
          encode_event_cursor(last)
        else
          nil
        end

      {:ok, %{events: events, next_cursor: next_cursor}}
    end

    @doc "Counts event rows matching the given filters using a database `COUNT` query."
    @impl PhoenixAI.Store.Adapter.EventStore
    def count_events(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      count =
        from(e in event_source(opts), select: count(e.id))
        |> apply_event_filters(filters)
        |> repo.one()

      {:ok, count}
    end

    defp apply_event_filters(query, []), do: query

    defp apply_event_filters(query, [{:conversation_id, conv_id} | rest]) do
      query
      |> where([e], e.conversation_id == ^conv_id)
      |> apply_event_filters(rest)
    end

    defp apply_event_filters(query, [{:user_id, user_id} | rest]) do
      query
      |> where([e], e.user_id == ^user_id)
      |> apply_event_filters(rest)
    end

    defp apply_event_filters(query, [{:type, type} | rest]) do
      query
      |> where([e], e.type == ^to_string(type))
      |> apply_event_filters(rest)
    end

    defp apply_event_filters(query, [{:after, dt} | rest]) do
      query
      |> where([e], e.inserted_at >= ^dt)
      |> apply_event_filters(rest)
    end

    defp apply_event_filters(query, [{:before, dt} | rest]) do
      query
      |> where([e], e.inserted_at <= ^dt)
      |> apply_event_filters(rest)
    end

    defp apply_event_filters(query, [_ | rest]), do: apply_event_filters(query, rest)

    defp maybe_apply_ecto_cursor(query, nil), do: query

    defp maybe_apply_ecto_cursor(query, cursor) do
      {cursor_ts, cursor_id} = decode_event_cursor(cursor)

      where(
        query,
        [e],
        e.inserted_at > ^cursor_ts or (e.inserted_at == ^cursor_ts and e.id > ^cursor_id)
      )
    end

    defp maybe_apply_ecto_limit(query, nil), do: query
    defp maybe_apply_ecto_limit(query, limit), do: limit(query, ^limit)

    defp event_source(opts), do: {event_table_name(opts), EventSchema}

    defp event_table_name(opts),
      do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "events"

    defp handle_event_result({:ok, schema}), do: {:ok, EventSchema.to_store_struct(schema)}
    defp handle_event_result({:error, changeset}), do: {:error, changeset}

    defp encode_event_cursor(%Event{} = event) do
      Base.url_encode64("#{DateTime.to_iso8601(event.inserted_at)}|#{event.id}", padding: false)
    end

    defp decode_event_cursor(cursor) do
      {:ok, decoded} = Base.url_decode64(cursor, padding: false)
      [ts_str, id] = String.split(decoded, "|", parts: 2)
      {:ok, ts, _} = DateTime.from_iso8601(ts_str)
      {ts, id}
    end
  end
end
