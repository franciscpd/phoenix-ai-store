defmodule PhoenixAI.Store.Adapter do
  @moduledoc "Behaviour for storage backends."

  alias PhoenixAI.Store.{Conversation, Message}

  @callback save_conversation(Conversation.t(), opts :: keyword()) ::
              {:ok, Conversation.t()} | {:error, term()}

  @callback load_conversation(id :: String.t(), opts :: keyword()) ::
              {:ok, Conversation.t()} | {:error, :not_found | term()}

  @callback list_conversations(filters :: keyword(), opts :: keyword()) ::
              {:ok, [Conversation.t()]} | {:error, term()}

  @callback delete_conversation(id :: String.t(), opts :: keyword()) ::
              :ok | {:error, :not_found | term()}

  @callback count_conversations(filters :: keyword(), opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @callback conversation_exists?(id :: String.t(), opts :: keyword()) ::
              {:ok, boolean()} | {:error, term()}

  @callback add_message(conversation_id :: String.t(), Message.t(), opts :: keyword()) ::
              {:ok, Message.t()} | {:error, term()}

  @callback get_messages(conversation_id :: String.t(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}
end
