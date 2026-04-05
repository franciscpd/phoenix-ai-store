defmodule PhoenixAI.Store.Adapters.ETSTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Adapters.ETS.TableOwner

  setup do
    name = :"table_owner_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = TableOwner.start_link(name: name)
    table = TableOwner.table(pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {:ok, opts: [table: table]}
  end

  use PhoenixAI.Store.AdapterContractTest, adapter: PhoenixAI.Store.Adapters.ETS
  use PhoenixAI.Store.FactStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
  use PhoenixAI.Store.ProfileStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
  use PhoenixAI.Store.TokenUsageContractTest, adapter: PhoenixAI.Store.Adapters.ETS
  use PhoenixAI.Store.CostStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
  use PhoenixAI.Store.EventStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
end
