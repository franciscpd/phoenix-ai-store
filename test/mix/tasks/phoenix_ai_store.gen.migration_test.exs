defmodule Mix.Tasks.PhoenixAiStore.Gen.MigrationTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  @tmp_dir "tmp/test_migrations"

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "generates migration file with correct content" do
    output =
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
      end)

    assert output =~ "creating"

    [file] = Path.wildcard(Path.join(@tmp_dir, "*_create_phoenix_ai_store_tables.exs"))
    content = File.read!(file)

    # Check migration module name
    assert content =~ "CreatePhoenixAiStoreTables"

    # Check conversations table
    assert content =~ "create table(:phoenix_ai_store_conversations, primary_key: false)"
    assert content =~ "add :user_id, :string"
    assert content =~ "add :tags, {:array, :string}, default: []"
    assert content =~ "add :metadata, :map, default: %{}"
    assert content =~ "add :deleted_at, :utc_datetime_usec"

    # Check conversations indexes
    assert content =~ ~s|create index(:phoenix_ai_store_conversations, [:user_id])|
    assert content =~ ~s|create index(:phoenix_ai_store_conversations, [:tags], using: "GIN")|
    assert content =~ ~s|create index(:phoenix_ai_store_conversations, [:inserted_at])|
    assert content =~ ~s|create index(:phoenix_ai_store_conversations, [:deleted_at])|

    # Check messages table
    assert content =~ "create table(:phoenix_ai_store_messages, primary_key: false)"

    assert content =~
             "references(:phoenix_ai_store_conversations, type: :binary_id, on_delete: :delete_all)"

    assert content =~ "add :role, :string, null: false"
    assert content =~ "add :content, :text"
    assert content =~ "add :tool_call_id, :string"
    assert content =~ "add :tool_calls, {:array, :map}"
    assert content =~ "add :token_count, :integer"

    # Check messages indexes
    assert content =~ ~s|create index(:phoenix_ai_store_messages, [:conversation_id])|

    assert content =~
             ~s|create index(:phoenix_ai_store_messages, [:conversation_id, :inserted_at])|

    # Check filename has timestamp format
    filename = Path.basename(file)
    assert filename =~ ~r/^\d{14}_create_phoenix_ai_store_tables\.exs$/
  end

  test "generates with custom prefix" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--prefix",
        "my_ai_"
      ])
    end)

    [file] = Path.wildcard(Path.join(@tmp_dir, "*_create_my_ai_tables.exs"))
    content = File.read!(file)

    assert content =~ "create table(:my_ai_conversations, primary_key: false)"
    assert content =~ "create table(:my_ai_messages, primary_key: false)"
    assert content =~ "references(:my_ai_conversations, type: :binary_id, on_delete: :delete_all)"
    assert content =~ "create index(:my_ai_conversations, [:user_id])"
    assert content =~ "create index(:my_ai_messages, [:conversation_id])"
  end

  test "generates cost migration with cursor index" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--cost"
      ])
    end)

    [file] = Path.wildcard(Path.join(@tmp_dir, "*_add_phoenix_ai_store_cost_tables.exs"))
    content = File.read!(file)

    assert content =~ "create table(:phoenix_ai_store_cost_records, primary_key: false)"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:conversation_id])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:user_id])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:recorded_at])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:user_id, :recorded_at])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:recorded_at, :id]"
    assert content =~ "cost_records_cursor_idx"
  end

  test "is idempotent (second run skips)" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
    end)

    files_before = Path.wildcard(Path.join(@tmp_dir, "*.exs"))
    assert length(files_before) == 1

    output =
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
      end)

    assert output =~ "already exists"

    files_after = Path.wildcard(Path.join(@tmp_dir, "*.exs"))
    assert length(files_after) == 1
  end
end
