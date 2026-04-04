if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Message do
    @moduledoc """
    Ecto schema for persisting `PhoenixAI.Store.Message` structs.

    This module is only compiled when Ecto is available as a dependency.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.Message, as: StoreMessage
    alias PhoenixAI.Store.Schemas.Conversation, as: ConversationSchema

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec]

    schema "phoenix_ai_store_messages" do
      field :role, :string
      field :content, :string
      field :tool_call_id, :string
      field :tool_calls, {:array, :map}
      field :token_count, :integer
      field :pinned, :boolean, default: false
      field :metadata, :map, default: %{}

      belongs_to :conversation, ConversationSchema, type: :binary_id

      timestamps()
    end

    @cast_fields ~w(id role content tool_call_id tool_calls token_count pinned metadata conversation_id)a
    @required_fields ~w(role conversation_id)a
    @valid_roles ~w(system user assistant tool)

    @doc "Creates a changeset for a message."
    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
      |> validate_inclusion(:role, @valid_roles)
    end

    @doc "Converts an Ecto schema struct to a `%PhoenixAI.Store.Message{}`."
    def to_store_struct(%__MODULE__{} = schema) do
      %StoreMessage{
        id: schema.id,
        conversation_id: schema.conversation_id,
        role: safe_to_atom(schema.role),
        content: schema.content,
        tool_call_id: schema.tool_call_id,
        tool_calls: schema.tool_calls,
        token_count: schema.token_count,
        pinned: schema.pinned || false,
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at
      }
    end

    @doc "Converts a `%PhoenixAI.Store.Message{}` to an attrs map for changeset."
    def from_store_struct(%StoreMessage{} = msg) do
      %{
        id: msg.id,
        conversation_id: msg.conversation_id,
        role: safe_to_string(msg.role),
        content: msg.content,
        tool_call_id: msg.tool_call_id,
        tool_calls: msg.tool_calls,
        token_count: msg.token_count,
        pinned: msg.pinned || false,
        metadata: msg.metadata || %{}
      }
    end

    defp safe_to_atom(nil), do: nil
    defp safe_to_atom(role) when is_atom(role), do: role
    defp safe_to_atom(role) when is_binary(role), do: String.to_existing_atom(role)

    defp safe_to_string(nil), do: nil
    defp safe_to_string(role) when is_binary(role), do: role
    defp safe_to_string(role) when is_atom(role), do: Atom.to_string(role)
  end
end
