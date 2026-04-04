import Config

config :phoenix_ai_store, PhoenixAI.Store.Test.Repo,
  database: "phoenix_ai_store_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :phoenix_ai_store, ecto_repos: [PhoenixAI.Store.Test.Repo]
