defmodule PhoenixAI.Store.LongTermMemory.Profile do
  @moduledoc """
  A user profile combining a free-text AI-generated summary with structured metadata.

  The `summary` field is injected into AI calls as a system message.
  The `metadata` map holds structured data (tags, expertise_level, etc.)
  that is queryable but not directly injected.

  One profile per `user_id` — save uses upsert semantics.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          summary: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :user_id, :summary, :inserted_at, :updated_at, metadata: %{}]
end
