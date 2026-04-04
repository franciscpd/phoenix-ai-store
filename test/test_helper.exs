ExUnit.start()

{:ok, _} = PhoenixAI.Store.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(PhoenixAI.Store.Test.Repo, :manual)
