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

    import Ecto.Query

    alias PhoenixAI.Store.{Conversation, Message}
    alias PhoenixAI.Store.Schemas.Conversation, as: ConvSchema
    alias PhoenixAI.Store.Schemas.Message, as: MsgSchema
    alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
    alias PhoenixAI.Store.Schemas.Fact, as: FactSchema
    alias PhoenixAI.Store.Schemas.Profile, as: ProfileSchema

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

    @impl true
    def load_conversation(id, opts) do
      if not valid_uuid?(id), do: {:error, :not_found}, else: do_load_conversation(id, opts)
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

    @impl true
    def delete_conversation(id, opts) do
      if not valid_uuid?(id), do: {:error, :not_found}, else: do_delete_conversation(id, opts)
    end

    defp do_delete_conversation(id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.one(from(c in conv_source(opts), where: c.id == ^id)) do
        nil -> {:error, :not_found}
        schema -> repo.delete(schema) |> handle_delete_result()
      end
    end

    @impl true
    def count_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from(c in conv_source(opts), select: count(c.id))
        |> apply_filters(filters)

      {:ok, repo.one(query)}
    end

    @impl true
    def conversation_exists?(id, opts) do
      if not valid_uuid?(id), do: {:ok, false}, else: do_conversation_exists?(id, opts)
    end

    defp do_conversation_exists?(id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      {:ok, repo.exists?(from(c in conv_source(opts), where: c.id == ^id))}
    end

    @impl true
    def add_message(conversation_id, %Message{} = message, opts) do
      if not valid_uuid?(conversation_id) do
        {:error, :not_found}
      else
        do_add_message(conversation_id, message, opts)
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

    @impl true
    def get_messages(conversation_id, opts) do
      if not valid_uuid?(conversation_id),
        do: {:ok, []},
        else: do_get_messages(conversation_id, opts)
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

    @impl PhoenixAI.Store.Adapter.FactStore
    def save_fact(%Fact{} = fact, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = FactSchema.from_store_struct(fact)

      case repo.one(from(f in fact_source(opts), where: f.user_id == ^fact.user_id and f.key == ^fact.key)) do
        nil ->
          attrs = Map.put_new(attrs, :id, Uniq.UUID.uuid7())

          %FactSchema{}
          |> Ecto.put_meta(source: fact_table_name(opts))
          |> FactSchema.changeset(attrs)
          |> repo.insert()
          |> handle_fact_result()

        existing ->
          existing
          |> FactSchema.changeset(attrs)
          |> repo.update()
          |> handle_fact_result()
      end
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def get_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      facts =
        from(f in fact_source(opts), where: f.user_id == ^user_id, order_by: [asc: f.inserted_at])
        |> repo.all()
        |> Enum.map(&FactSchema.to_store_struct/1)

      {:ok, facts}
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def delete_fact(user_id, key, opts) do
      repo = Keyword.fetch!(opts, :repo)
      from(f in fact_source(opts), where: f.user_id == ^user_id and f.key == ^key) |> repo.delete_all()
      :ok
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def count_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      count = from(f in fact_source(opts), where: f.user_id == ^user_id, select: count(f.id)) |> repo.one()
      {:ok, count}
    end

    # -- ProfileStore --

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def save_profile(%Profile{} = profile, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ProfileSchema.from_store_struct(profile)

      case repo.one(from(p in profile_source(opts), where: p.user_id == ^profile.user_id)) do
        nil ->
          attrs = Map.put_new(attrs, :id, Uniq.UUID.uuid7())

          %ProfileSchema{}
          |> Ecto.put_meta(source: profile_table_name(opts))
          |> ProfileSchema.changeset(attrs)
          |> repo.insert()
          |> handle_profile_result()

        existing ->
          existing
          |> ProfileSchema.changeset(attrs)
          |> repo.update()
          |> handle_profile_result()
      end
    end

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def load_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.one(from(p in profile_source(opts), where: p.user_id == ^user_id)) do
        nil -> {:error, :not_found}
        schema -> {:ok, ProfileSchema.to_store_struct(schema)}
      end
    end

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def delete_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      from(p in profile_source(opts), where: p.user_id == ^user_id) |> repo.delete_all()
      :ok
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
    defp profile_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "profiles"

    defp handle_fact_result({:ok, schema}), do: {:ok, FactSchema.to_store_struct(schema)}
    defp handle_fact_result({:error, changeset}), do: {:error, changeset}

    defp handle_profile_result({:ok, schema}), do: {:ok, ProfileSchema.to_store_struct(schema)}
    defp handle_profile_result({:error, changeset}), do: {:error, changeset}

    defp valid_uuid?(id) when is_binary(id) do
      case Ecto.UUID.cast(id) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp valid_uuid?(_), do: false
  end
end
