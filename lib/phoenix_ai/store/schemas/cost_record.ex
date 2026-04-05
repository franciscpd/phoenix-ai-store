if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.CostRecord do
    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.CostTracking.CostRecord, as: StoreCostRecord

    @primary_key {:id, :binary_id, autogenerate: false}

    schema "phoenix_ai_store_cost_records" do
      field :conversation_id, :binary_id
      field :user_id, :string
      field :provider, :string
      field :model, :string
      field :input_tokens, :integer
      field :output_tokens, :integer
      field :input_cost, :decimal
      field :output_cost, :decimal
      field :total_cost, :decimal
      field :metadata, :map, default: %{}
      field :recorded_at, :utc_datetime_usec
    end

    @cast_fields ~w(id conversation_id user_id provider model input_tokens output_tokens input_cost output_cost total_cost metadata recorded_at)a
    @required_fields ~w(conversation_id provider model input_tokens output_tokens input_cost output_cost total_cost recorded_at)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreCostRecord{
        id: schema.id,
        conversation_id: schema.conversation_id,
        user_id: schema.user_id,
        provider: String.to_existing_atom(schema.provider),
        model: schema.model,
        input_tokens: schema.input_tokens,
        output_tokens: schema.output_tokens,
        input_cost: schema.input_cost,
        output_cost: schema.output_cost,
        total_cost: schema.total_cost,
        metadata: schema.metadata || %{},
        recorded_at: schema.recorded_at
      }
    end

    def from_store_struct(%StoreCostRecord{} = record) do
      %{
        id: record.id,
        conversation_id: record.conversation_id,
        user_id: record.user_id,
        provider: to_string(record.provider),
        model: record.model,
        input_tokens: record.input_tokens,
        output_tokens: record.output_tokens,
        input_cost: record.input_cost,
        output_cost: record.output_cost,
        total_cost: record.total_cost,
        metadata: record.metadata || %{},
        recorded_at: record.recorded_at
      }
    end
  end
end
