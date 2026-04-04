defmodule PhoenixAI.Store.Test.Repo.Migrations.CreateLtmTables do
  use Ecto.Migration

  def change do
    create table(:phoenix_ai_store_facts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, :string, null: false)
      add(:key, :string, null: false)
      add(:value, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:phoenix_ai_store_facts, [:user_id, :key]))
    create(index(:phoenix_ai_store_facts, [:user_id]))

    create table(:phoenix_ai_store_profiles, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, :string, null: false)
      add(:summary, :text)
      add(:metadata, :map, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:phoenix_ai_store_profiles, [:user_id]))
  end
end
