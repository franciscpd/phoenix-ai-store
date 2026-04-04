defmodule PhoenixAI.Store.Adapters.ETS.TableOwnerTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Adapters.ETS.TableOwner

  describe "start_link/1" do
    test "starts and creates an ETS table" do
      name = :"table_owner_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = TableOwner.start_link(name: name)

      assert Process.alive?(pid)
      table = TableOwner.table(pid)
      assert :ets.info(table) != :undefined
    end
  end

  describe "table/1" do
    test "returns the ETS table reference" do
      name = :"table_owner_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = TableOwner.start_link(name: name)

      table = TableOwner.table(pid)
      assert is_reference(table) or is_atom(table)

      # Verify we can use the table
      :ets.insert(table, {:test_key, "test_value"})
      assert [{:test_key, "test_value"}] = :ets.lookup(table, :test_key)
    end
  end

  describe "terminate/2" do
    test "deletes the ETS table on stop" do
      name = :"table_owner_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = TableOwner.start_link(name: name)

      table = TableOwner.table(pid)
      assert :ets.info(table) != :undefined

      GenServer.stop(pid)
      assert :ets.info(table) == :undefined
    end
  end
end
