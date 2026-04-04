defmodule PhoenixAI.Store.Test.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_ai_store,
    adapter: Ecto.Adapters.Postgres
end
