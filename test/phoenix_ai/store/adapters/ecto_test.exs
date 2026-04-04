defmodule PhoenixAI.Store.Adapters.EctoTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PhoenixAI.Store.Test.Repo)
    {:ok, opts: [repo: PhoenixAI.Store.Test.Repo]}
  end

  use PhoenixAI.Store.AdapterContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.FactStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
  use PhoenixAI.Store.ProfileStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
end
