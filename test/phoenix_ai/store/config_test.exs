defmodule PhoenixAI.Store.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Config

  # A dummy adapter module for testing
  defmodule FakeAdapter do
    @behaviour PhoenixAI.Store.Adapter

    @impl true
    def save_conversation(_conv, _opts), do: {:ok, nil}
    @impl true
    def load_conversation(_id, _opts), do: {:error, :not_found}
    @impl true
    def list_conversations(_filters, _opts), do: {:ok, []}
    @impl true
    def delete_conversation(_id, _opts), do: :ok
    @impl true
    def count_conversations(_filters, _opts), do: {:ok, 0}
    @impl true
    def conversation_exists?(_id, _opts), do: {:ok, false}
    @impl true
    def add_message(_cid, _msg, _opts), do: {:ok, nil}
    @impl true
    def get_messages(_cid, _opts), do: {:ok, []}
  end

  describe "validate!/1" do
    test "accepts valid config with defaults applied" do
      opts = Config.validate!(name: :my_store, adapter: FakeAdapter)

      assert opts[:name] == :my_store
      assert opts[:adapter] == FakeAdapter
      assert opts[:prefix] == "phoenix_ai_store_"
      assert opts[:soft_delete] == false
      assert opts[:user_id_required] == false
      assert opts[:repo] == nil
    end

    test "raises on missing required field :name" do
      assert_raise NimbleOptions.ValidationError, ~r/required/, fn ->
        Config.validate!(adapter: FakeAdapter)
      end
    end

    test "raises on missing required field :adapter" do
      assert_raise NimbleOptions.ValidationError, ~r/required/, fn ->
        Config.validate!(name: :my_store)
      end
    end

    test "raises on invalid adapter type (not an atom)" do
      assert_raise NimbleOptions.ValidationError, ~r/adapter/, fn ->
        Config.validate!(name: :my_store, adapter: "not_an_atom")
      end
    end

    test "accepts optional repo" do
      opts = Config.validate!(name: :my_store, adapter: FakeAdapter, repo: MyApp.Repo)

      assert opts[:repo] == MyApp.Repo
    end

    test "accepts custom prefix" do
      opts = Config.validate!(name: :my_store, adapter: FakeAdapter, prefix: "custom_")

      assert opts[:prefix] == "custom_"
    end

    test "accepts soft_delete and user_id_required flags" do
      opts =
        Config.validate!(
          name: :my_store,
          adapter: FakeAdapter,
          soft_delete: true,
          user_id_required: true
        )

      assert opts[:soft_delete] == true
      assert opts[:user_id_required] == true
    end
  end

  describe "resolve/1" do
    test "merges global application env defaults with per-instance opts" do
      # Set global defaults in application env
      Application.put_env(:phoenix_ai_store, :defaults, soft_delete: true, prefix: "global_")

      opts = Config.resolve(name: :my_store, adapter: FakeAdapter)

      assert opts[:soft_delete] == true
      assert opts[:prefix] == "global_"
      assert opts[:name] == :my_store
      assert opts[:adapter] == FakeAdapter
    after
      Application.delete_env(:phoenix_ai_store, :defaults)
    end

    test "per-instance opts override global defaults" do
      Application.put_env(:phoenix_ai_store, :defaults, soft_delete: true, prefix: "global_")

      opts =
        Config.resolve(
          name: :my_store,
          adapter: FakeAdapter,
          soft_delete: false,
          prefix: "local_"
        )

      assert opts[:soft_delete] == false
      assert opts[:prefix] == "local_"
    after
      Application.delete_env(:phoenix_ai_store, :defaults)
    end

    test "works with no global defaults set" do
      Application.delete_env(:phoenix_ai_store, :defaults)

      opts = Config.resolve(name: :my_store, adapter: FakeAdapter)

      assert opts[:name] == :my_store
      assert opts[:prefix] == "phoenix_ai_store_"
    end
  end
end
