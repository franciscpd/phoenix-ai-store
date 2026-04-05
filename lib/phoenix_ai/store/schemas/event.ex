if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Event do
    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.EventLog.Event, as: StoreEvent

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts []

    schema "phoenix_ai_store_events" do
      field :conversation_id, :binary_id
      field :user_id, :string
      field :type, :string
      field :data, :map, default: %{}
      field :metadata, :map, default: %{}
      field :inserted_at, :utc_datetime_usec
    end

    @cast_fields ~w(id conversation_id user_id type data metadata inserted_at)a
    @required_fields ~w(type inserted_at)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
    end

    def to_store_struct(%__MODULE__{} = schema) do
      type =
        try do
          String.to_existing_atom(schema.type)
        rescue
          ArgumentError -> String.to_atom(schema.type)
        end

      data = atomize_keys(schema.data || %{})

      %StoreEvent{
        id: schema.id,
        conversation_id: schema.conversation_id,
        user_id: schema.user_id,
        type: type,
        data: data,
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at
      }
    end

    def from_store_struct(%StoreEvent{} = event) do
      %{
        id: event.id,
        conversation_id: event.conversation_id,
        user_id: event.user_id,
        type: to_string(event.type),
        data: stringify_keys(event.data || %{}),
        metadata: event.metadata || %{},
        inserted_at: event.inserted_at
      }
    end

    defp atomize_keys(map) when is_map(map) do
      Map.new(map, fn
        {k, v} when is_binary(k) ->
          key =
            try do
              String.to_existing_atom(k)
            rescue
              ArgumentError -> String.to_atom(k)
            end

          {key, v}

        {k, v} ->
          {k, v}
      end)
    end

    defp stringify_keys(map) when is_map(map) do
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end
  end
end
