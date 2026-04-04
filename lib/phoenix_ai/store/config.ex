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
