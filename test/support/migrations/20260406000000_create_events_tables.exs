defmodule PhoenixAI.Store.Test.Repo.Migrations.CreateEventsTables do
  use Ecto.Migration

  def change do
    create table(:phoenix_ai_store_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:conversation_id, :binary_id)
      add(:user_id, :string)
      add(:type, :string, null: false)
      add(:data, :map, default: %{})
      add(:metadata, :map, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:phoenix_ai_store_events, [:conversation_id]))
    create(index(:phoenix_ai_store_events, [:user_id]))
    create(index(:phoenix_ai_store_events, [:inserted_at]))
    create(index(:phoenix_ai_store_events, [:inserted_at, :id]))
    create(index(:phoenix_ai_store_events, [:conversation_id, :inserted_at]))
  end
end
