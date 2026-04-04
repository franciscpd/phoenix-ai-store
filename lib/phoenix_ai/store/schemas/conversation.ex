if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Conversation do
    @moduledoc """
    Ecto schema for persisting `PhoenixAI.Store.Conversation` structs.

    This module is only compiled when Ecto is available as a dependency.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.Conversation, as: StoreConversation
    alias PhoenixAI.Store.Schemas.Message, as: MessageSchema

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [type: :utc_datetime_usec]

    schema "phoenix_ai_store_conversations" do
      field :user_id, :string
      field :title, :string
      field :tags, {:array, :string}, default: []
      field :model, :string
      field :metadata, :map, default: %{}
      field :deleted_at, :utc_datetime_usec

      has_many :messages, MessageSchema, foreign_key: :conversation_id

      timestamps()
    end

    @cast_fields ~w(id user_id title tags model metadata deleted_at)a

    @doc "Creates a changeset for a conversation."
    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
    end

    @doc "Converts an Ecto schema struct to a `%PhoenixAI.Store.Conversation{}`."
    def to_store_struct(%__MODULE__{} = schema) do
      messages =
        case schema.messages do
          %Ecto.Association.NotLoaded{} -> []
          msgs -> Enum.map(msgs, &MessageSchema.to_store_struct/1)
        end

      %StoreConversation{
        id: schema.id,
        user_id: schema.user_id,
        title: schema.title,
        tags: schema.tags || [],
        model: schema.model,
        messages: messages,
        metadata: schema.metadata || %{},
        deleted_at: schema.deleted_at,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }
    end

    @doc "Converts a `%PhoenixAI.Store.Conversation{}` to an attrs map for changeset."
    def from_store_struct(%StoreConversation{} = conv) do
      %{
        id: conv.id,
        user_id: conv.user_id,
        title: conv.title,
        tags: conv.tags || [],
        model: conv.model,
        metadata: conv.metadata || %{},
        deleted_at: conv.deleted_at
      }
    end
  end
end
