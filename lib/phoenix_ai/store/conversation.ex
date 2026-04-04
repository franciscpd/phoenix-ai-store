defmodule PhoenixAI.Store.Conversation do
  @moduledoc """
  A conversation owned by `PhoenixAI.Store`, extending `PhoenixAI.Conversation`
  with persistence-specific fields such as `user_id`, `title`, `tags`, `model`,
  timestamps, and soft-delete support.
  """

  alias PhoenixAI.Store.Message

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          title: String.t() | nil,
          tags: [String.t()],
          model: String.t() | nil,
          messages: [Message.t()],
          metadata: map(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :title,
    :model,
    :deleted_at,
    :inserted_at,
    :updated_at,
    tags: [],
    messages: [],
    metadata: %{}
  ]

  @doc """
  Converts a `%PhoenixAI.Store.Conversation{}` to a `%PhoenixAI.Conversation{}`.

  Messages are converted via `PhoenixAI.Store.Message.to_phoenix_ai/1`.
  Store-specific fields (`user_id`, `title`, `tags`, `model`, timestamps)
  are dropped.
  """
  @spec to_phoenix_ai(t()) :: PhoenixAI.Conversation.t()
  def to_phoenix_ai(%__MODULE__{} = conv) do
    %PhoenixAI.Conversation{
      id: conv.id,
      messages: Enum.map(conv.messages, &Message.to_phoenix_ai/1),
      metadata: conv.metadata
    }
  end

  @doc """
  Converts a `%PhoenixAI.Conversation{}` to a `%PhoenixAI.Store.Conversation{}`.

  Accepts an optional keyword list to populate store-specific fields:

    * `:user_id` - the owning user's ID
    * `:title` - conversation title
    * `:tags` - list of string tags (defaults to `[]`)
    * `:model` - the AI model identifier

  Messages are converted via `PhoenixAI.Store.Message.from_phoenix_ai/1`.§
  """
  @spec from_phoenix_ai(PhoenixAI.Conversation.t(), keyword()) :: t()
  def from_phoenix_ai(%PhoenixAI.Conversation{} = conv, opts \\ []) do
    %__MODULE__{
      id: conv.id,
      messages: Enum.map(conv.messages, &Message.from_phoenix_ai/1),
      metadata: conv.metadata,
      user_id: Keyword.get(opts, :user_id),
      title: Keyword.get(opts, :title),
      tags: Keyword.get(opts, :tags, []),
      model: Keyword.get(opts, :model)
    }
  end
end
