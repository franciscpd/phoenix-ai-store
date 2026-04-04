defmodule PhoenixAI.Store.Message do
  @moduledoc """
  A message within a conversation, wrapping `PhoenixAI.Message` with
  persistence-specific fields such as `id`, `conversation_id`, `token_count`,
  and `inserted_at`.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          conversation_id: String.t() | nil,
          role: :system | :user | :assistant | :tool | nil,
          content: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [map()] | nil,
          metadata: map(),
          token_count: non_neg_integer() | nil,
          pinned: boolean(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :conversation_id,
    :role,
    :content,
    :tool_call_id,
    :tool_calls,
    :inserted_at,
    token_count: nil,
    pinned: false,
    metadata: %{}
  ]

  @doc """
  Converts a `%PhoenixAI.Store.Message{}` to a `%PhoenixAI.Message{}`.

  Only maps fields that exist on the core struct: `role`, `content`,
  `tool_call_id`, `tool_calls`, and `metadata`.
  """
  @spec to_phoenix_ai(t()) :: PhoenixAI.Message.t()
  def to_phoenix_ai(%__MODULE__{} = msg) do
    %PhoenixAI.Message{
      role: msg.role,
      content: msg.content,
      tool_call_id: msg.tool_call_id,
      tool_calls: msg.tool_calls,
      metadata: msg.metadata
    }
  end

  @doc """
  Converts a `%PhoenixAI.Message{}` to a `%PhoenixAI.Store.Message{}`.

  Store-specific fields (`id`, `conversation_id`, `token_count`, `inserted_at`)
  are left as `nil` and should be populated by the adapter on persistence.
  """
  @spec from_phoenix_ai(PhoenixAI.Message.t()) :: t()
  def from_phoenix_ai(%PhoenixAI.Message{} = msg) do
    %__MODULE__{
      role: msg.role,
      content: msg.content,
      tool_call_id: msg.tool_call_id,
      tool_calls: msg.tool_calls,
      metadata: msg.metadata
    }
  end
end
