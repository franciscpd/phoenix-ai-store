if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Fact do
    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.LongTermMemory.Fact, as: StoreFact

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [type: :utc_datetime_usec]

    schema "phoenix_ai_store_facts" do
      field :user_id, :string
      field :key, :string
      field :value, :string
      timestamps()
    end

    @cast_fields ~w(id user_id key value)a
    @required_fields ~w(user_id key value)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
      |> unique_constraint([:user_id, :key])
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreFact{
        id: schema.id,
        user_id: schema.user_id,
        key: schema.key,
        value: schema.value,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }
    end

    def from_store_struct(%StoreFact{} = fact) do
      %{id: fact.id, user_id: fact.user_id, key: fact.key, value: fact.value}
    end
  end
end
