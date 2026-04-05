defmodule PhoenixAI.Store.EventLog.Event do
  @moduledoc """
  An immutable event record in the append-only event log.

  Events capture significant actions (message sent, cost recorded,
  policy violation, etc.) with a `type` atom and a `data` map
  containing type-specific payload.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          conversation_id: String.t() | nil,
          user_id: String.t() | nil,
          type: atom(),
          data: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :type,
    :inserted_at,
    data: %{},
    metadata: %{}
  ]
end
