import Config

config :phoenix_ai_store, PhoenixAI.Store.Test.Repo,
  database: "phoenix_ai_store_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5434")),
  pool: Ecto.Adapters.SQL.Sandbox

config :phoenix_ai_store, ecto_repos: [PhoenixAI.Store.Test.Repo]
