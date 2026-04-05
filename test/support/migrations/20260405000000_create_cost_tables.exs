defmodule PhoenixAI.Store.Test.Repo.Migrations.CreateCostTables do
  use Ecto.Migration

  def change do
    create table(:phoenix_ai_store_cost_records, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :conversation_id,
        references(:phoenix_ai_store_conversations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, :string)
      add(:provider, :string, null: false)
      add(:model, :string, null: false)
      add(:input_tokens, :integer, null: false, default: 0)
      add(:output_tokens, :integer, null: false, default: 0)
      add(:input_cost, :decimal, precision: 20, scale: 10, null: false)
      add(:output_cost, :decimal, precision: 20, scale: 10, null: false)
      add(:total_cost, :decimal, precision: 20, scale: 10, null: false)
      add(:metadata, :map, default: %{})
      add(:recorded_at, :utc_datetime_usec, null: false)
    end

    create(index(:phoenix_ai_store_cost_records, [:conversation_id]))
    create(index(:phoenix_ai_store_cost_records, [:user_id]))
    create(index(:phoenix_ai_store_cost_records, [:recorded_at]))
    create(index(:phoenix_ai_store_cost_records, [:user_id, :recorded_at]))
  end
end
