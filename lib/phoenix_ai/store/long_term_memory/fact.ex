defmodule PhoenixAI.Store.LongTermMemory.Fact do
  @moduledoc """
  A key-value fact associated with a user, persisted across conversations.

  Facts are simple string pairs — the key identifies what is known, the value
  holds the information. Save is upsert: writing to the same `{user_id, key}`
  silently overwrites the previous value.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          key: String.t(),
          value: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :user_id, :key, :value, :inserted_at, :updated_at]
end
