defmodule PhoenixAI.Store.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/franciscpd/phoenix-ai-store"

  def project do
    [
      app: :phoenix_ai_store,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description:
        "Persistence, memory management, guardrails, and cost tracking for PhoenixAI conversations",
      package: package(),
      name: "PhoenixAI.Store",
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_ai, "~> 0.3"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:uniq, "~> 0.6"},
      {:decimal, "~> 2.0"},

      # Optional — Ecto adapter
      {:ecto, "~> 3.13", optional: true},
      {:ecto_sql, "~> 3.13", optional: true},
      {:postgrex, "~> 0.19", optional: true},

      # Optional — Guardrails time-window rate limiting
      {:hammer, "~> 7.3", optional: true},

      # Dev/Test
      {:mox, "~> 1.2", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "PhoenixAI.Store",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/adapters.md",
        "guides/memory-and-guardrails.md",
        "guides/telemetry-and-events.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          PhoenixAI.Store,
          PhoenixAI.Store.Conversation,
          PhoenixAI.Store.Message
        ],
        Adapters: [
          PhoenixAI.Store.Adapter,
          PhoenixAI.Store.Adapters.ETS,
          PhoenixAI.Store.Adapters.Ecto
        ],
        Memory: [
          PhoenixAI.Store.Memory.Pipeline,
          PhoenixAI.Store.Memory.SlidingWindow,
          PhoenixAI.Store.Memory.TokenTruncation,
          PhoenixAI.Store.Memory.PinnedMessages
        ],
        Guardrails: [
          PhoenixAI.Store.Guardrails.TokenBudget,
          PhoenixAI.Store.Guardrails.CostBudget
        ],
        "Cost Tracking": [
          PhoenixAI.Store.CostTracking,
          PhoenixAI.Store.CostTracking.CostRecord,
          PhoenixAI.Store.CostTracking.PricingProvider
        ],
        "Event Log": [
          PhoenixAI.Store.EventLog,
          PhoenixAI.Store.EventLog.Event
        ],
        "Long-Term Memory": [
          PhoenixAI.Store.LongTermMemory,
          PhoenixAI.Store.LongTermMemory.Fact,
          PhoenixAI.Store.LongTermMemory.Profile
        ],
        Telemetry: [
          PhoenixAI.Store.TelemetryHandler,
          PhoenixAI.Store.HandlerGuardian
        ],
        Pipeline: [
          PhoenixAI.Store.ConversePipeline
        ]
      ]
    ]
  end
end
