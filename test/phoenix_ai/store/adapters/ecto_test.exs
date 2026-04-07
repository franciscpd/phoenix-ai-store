defmodule PhoenixAI.Store.Adapters.EctoTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixAI.Store.Test.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
    {:ok, opts: [repo: Repo]}
  end

  use PhoenixAI.Store.AdapterContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.FactStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.ProfileStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.TokenUsageContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.CostStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.EventStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
end
