defmodule PhoenixAI.Store.InstanceTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Adapters.ETS.TableOwner
  alias PhoenixAI.Store.Instance

  describe "start_link/1 with ETS adapter" do
    setup do
      name = :"instance_test_#{:erlang.unique_integer([:positive])}"
      table_owner_name = :"#{name}_table_owner"
      {:ok, _} = TableOwner.start_link(name: table_owner_name)
      {:ok, _} = Instance.start_link(name: name, adapter: PhoenixAI.Store.Adapters.ETS)
      {:ok, name: name, table_owner: table_owner_name}
    end

    test "starts and registers under given name", %{name: name} do
      assert Process.whereis(name) != nil
    end

    test "get_config/1 returns resolved config", %{name: name} do
      config = Instance.get_config(name)
      assert config[:name] == name
      assert config[:adapter] == PhoenixAI.Store.Adapters.ETS
      assert is_binary(config[:prefix])
      assert is_boolean(config[:soft_delete])
    end

    test "get_adapter_opts/1 returns table reference for ETS", %{name: name} do
      opts = Instance.get_adapter_opts(name)
      assert Keyword.has_key?(opts, :table)
      assert is_reference(opts[:table])
    end
  end

  describe "adapter_opts for non-ETS adapter" do
    defmodule FakeAdapter do
      @behaviour PhoenixAI.Store.Adapter
      def save_conversation(_, _), do: {:ok, nil}
      def load_conversation(_, _), do: {:error, :not_found}
      def list_conversations(_, _), do: {:ok, []}
      def delete_conversation(_, _), do: :ok
      def count_conversations(_, _), do: {:ok, 0}
      def conversation_exists?(_, _), do: {:ok, false}
      def add_message(_, _, _), do: {:ok, nil}
      def get_messages(_, _), do: {:ok, []}
    end

    test "returns repo, prefix, soft_delete without table" do
      name = :"instance_generic_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        Instance.start_link(
          name: name,
          adapter: FakeAdapter,
          repo: MyApp.Repo,
          prefix: "test_",
          soft_delete: true
        )

      opts = Instance.get_adapter_opts(name)
      assert opts[:repo] == MyApp.Repo
      assert opts[:prefix] == "test_"
      assert opts[:soft_delete] == true
      refute Keyword.has_key?(opts, :table)
    end

    test "get_config/1 returns all resolved config keys" do
      name = :"instance_generic_cfg_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        Instance.start_link(
          name: name,
          adapter: FakeAdapter,
          repo: MyApp.Repo,
          prefix: "custom_",
          soft_delete: true
        )

      config = Instance.get_config(name)
      assert config[:name] == name
      assert config[:adapter] == FakeAdapter
      assert config[:repo] == MyApp.Repo
      assert config[:prefix] == "custom_"
      assert config[:soft_delete] == true
    end
  end
end
