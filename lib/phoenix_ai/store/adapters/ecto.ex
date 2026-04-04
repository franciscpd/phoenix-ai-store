if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Adapters.Ecto do
    @moduledoc """
    Ecto/Postgres adapter for `PhoenixAI.Store.Adapter`.

    All callbacks receive an `opts` keyword list containing a `:repo` key
    pointing to the Ecto.Repo module to use for queries.

    This module is only compiled when Ecto is available as a dependency.
    """

    @behaviour PhoenixAI.Store.Adapter

    import Ecto.Query

    alias PhoenixAI.Store.{Conversation, Message}
    alias PhoenixAI.Store.Schemas.Conversation, as: ConvSchema
    alias PhoenixAI.Store.Schemas.Message, as: MsgSchema

    @impl true
    def save_conversation(%Conversation{} = conversation, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ConvSchema.from_store_struct(conversation)

      case repo.get(ConvSchema, conversation.id) do
        nil ->
          %ConvSchema{}
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
        from c in ConvSchema,
          where: c.id == ^id,
          preload: [messages: ^from(m in MsgSchema, order_by: [asc: m.inserted_at])]

      case repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, ConvSchema.to_store_struct(schema)}
      end
    end

    @impl true
    def list_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from(c in ConvSchema, order_by: [desc: c.inserted_at])
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

      case repo.get(ConvSchema, id) do
        nil -> {:error, :not_found}
        schema -> repo.delete(schema) |> handle_delete_result()
      end
    end

    @impl true
    def count_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        from(c in ConvSchema, select: count(c.id))
        |> apply_filters(filters)

      {:ok, repo.one(query)}
    end

    @impl true
    def conversation_exists?(id, opts) do
      if not valid_uuid?(id), do: {:ok, false}, else: do_conversation_exists?(id, opts)
    end

    defp do_conversation_exists?(id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      {:ok, repo.exists?(from(c in ConvSchema, where: c.id == ^id))}
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

      if repo.exists?(from(c in ConvSchema, where: c.id == ^conversation_id)) do
        attrs =
          MsgSchema.from_store_struct(message)
          |> Map.put(:id, Uniq.UUID.uuid7())
          |> Map.put(:conversation_id, conversation_id)

        %MsgSchema{}
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
        from(m in MsgSchema,
          where: m.conversation_id == ^conversation_id,
          order_by: [asc: m.inserted_at]
        )
        |> repo.all()
        |> Enum.map(&MsgSchema.to_store_struct/1)

      {:ok, messages}
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

    defp apply_filters(query, [_ | rest]), do: apply_filters(query, rest)

    defp handle_conv_result({:ok, schema}), do: {:ok, ConvSchema.to_store_struct(schema)}
    defp handle_conv_result({:error, changeset}), do: {:error, changeset}

    defp handle_msg_result({:ok, schema}), do: {:ok, MsgSchema.to_store_struct(schema)}
    defp handle_msg_result({:error, changeset}), do: {:error, changeset}

    defp handle_delete_result({:ok, _schema}), do: :ok
    defp handle_delete_result({:error, changeset}), do: {:error, changeset}

    defp valid_uuid?(id) when is_binary(id) do
      case Ecto.UUID.cast(id) do
        {:ok, _} -> true
        :error -> false
      end
    end

    defp valid_uuid?(_), do: false
  end
end
