defmodule PhoenixAI.Store.Test.Repo.Migrations.CreateStoreTables do
  use Ecto.Migration

  def change do
    create table(:phoenix_ai_store_conversations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, :string)
      add(:title, :string)
      add(:tags, {:array, :string}, default: [])
      add(:model, :string)
      add(:metadata, :map, default: %{})
      add(:deleted_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:phoenix_ai_store_conversations, [:user_id]))
    create(index(:phoenix_ai_store_conversations, [:tags], using: "GIN"))
    create(index(:phoenix_ai_store_conversations, [:inserted_at]))
    create(index(:phoenix_ai_store_conversations, [:deleted_at]))

    create table(:phoenix_ai_store_messages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :conversation_id,
        references(:phoenix_ai_store_conversations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:role, :string, null: false)
      add(:content, :text)
      add(:tool_call_id, :string)
      add(:tool_calls, {:array, :map})
      add(:token_count, :integer)
      add(:pinned, :boolean, default: false, null: false)
      add(:metadata, :map, default: %{})
      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:phoenix_ai_store_messages, [:conversation_id]))
    create(index(:phoenix_ai_store_messages, [:conversation_id, :inserted_at]))
  end
end
