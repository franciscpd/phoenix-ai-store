defmodule PhoenixAI.Store.Config do
  @moduledoc """
  Configuration validation for `PhoenixAI.Store` instances.

  Uses NimbleOptions to validate and apply defaults to store configuration.
  """

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "Store instance name."
    ],
    adapter: [
      type: :atom,
      required: true,
      doc: "Adapter module implementing `PhoenixAI.Store.Adapter`."
    ],
    repo: [
      type: :atom,
      doc: "Ecto Repo module (required for the Ecto adapter)."
    ],
    prefix: [
      type: :string,
      default: "phoenix_ai_store_",
      doc: "Table/collection name prefix."
    ],
    soft_delete: [
      type: :boolean,
      default: false,
      doc: "When true, deleted conversations are soft-deleted."
    ],
    user_id_required: [
      type: :boolean,
      default: false,
      doc: "When true, conversations must have a user_id."
    ],
    long_term_memory: [
      type: :keyword_list,
      default: [],
      doc: "Long-term memory configuration.",
      keys: [
        enabled: [type: :boolean, default: false, doc: "Enable LTM subsystem."],
        max_facts_per_user: [type: :pos_integer, default: 100, doc: "Maximum facts per user."],
        extraction_trigger: [
          type: {:in, [:manual, :per_turn, :on_close]},
          default: :manual,
          doc: "When fact extraction runs: :manual, :per_turn, or :on_close."
        ],
        extraction_mode: [
          type: {:in, [:sync, :async]},
          default: :sync,
          doc: "Whether extraction blocks (:sync) or runs in background (:async)."
        ],
        extractor: [
          type: :atom,
          default: PhoenixAI.Store.LongTermMemory.Extractor.Default,
          doc: "Module implementing the Extractor behaviour."
        ],
        inject_long_term_memory: [
          type: :boolean,
          default: false,
          doc: "Auto-inject facts/profile in apply_memory/3."
        ],
        extraction_provider: [type: :atom, doc: "Provider override for extraction AI calls."],
        extraction_model: [type: :string, doc: "Model override for extraction AI calls."],
        profile_provider: [type: :atom, doc: "Provider override for profile AI calls."],
        profile_model: [type: :string, doc: "Model override for profile AI calls."]
      ]
    ],
    guardrails: [
      type: :keyword_list,
      default: [],
      doc: "Guardrails configuration.",
      keys: [
        token_budget: [
          type: :keyword_list,
          default: [],
          doc: "Default TokenBudget options.",
          keys: [
            max: [type: :pos_integer, doc: "Default max token budget."],
            scope: [
              type: {:in, [:conversation, :user, :time_window]},
              default: :conversation,
              doc: "Default scope."
            ],
            mode: [
              type: {:in, [:accumulated, :estimated]},
              default: :accumulated,
              doc: "Default counting mode."
            ]
          ]
        ]
      ]
    ],
    cost_tracking: [
      type: :keyword_list,
      default: [],
      doc: "Cost tracking configuration.",
      keys: [
        enabled: [type: :boolean, default: false, doc: "Enable cost tracking."],
        pricing_provider: [
          type: :atom,
          default: PhoenixAI.Store.CostTracking.PricingProvider.Static,
          doc: "Module implementing PricingProvider behaviour."
        ]
      ]
    ],
    event_log: [
      type: :keyword_list,
      default: [],
      doc: "Event log configuration.",
      keys: [
        enabled: [type: :boolean, default: false, doc: "Enable event logging."],
        redact_fn: [
          type: {:or, [{:fun, 1}, nil]},
          default: nil,
          doc:
            "Function (Event.t()) -> Event.t() to redact sensitive data before persistence."
        ]
      ]
    ]
  ]

  @doc """
  Validates the given options against the config schema.

  Raises `NimbleOptions.ValidationError` on invalid input.
  Returns a validated keyword list with defaults applied.
  """
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    NimbleOptions.validate!(opts, @schema)
  end

  @doc """
  Merges per-instance options over global Application env defaults,
  then validates via `validate!/1`.

  Global defaults are read from:

      config :phoenix_ai_store, :defaults, soft_delete: true, prefix: "global_"
  """
  @spec resolve(keyword()) :: keyword()
  def resolve(opts) do
    global_defaults = Application.get_env(:phoenix_ai_store, :defaults, [])

    global_defaults
    |> Keyword.merge(opts)
    |> validate!()
  end
end
