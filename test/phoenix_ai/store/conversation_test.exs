defmodule PhoenixAI.Store.ConversationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Conversation
  alias PhoenixAI.Store.Message

  describe "struct" do
    test "creates with defaults" do
      conv = %Conversation{}

      assert conv.id == nil
      assert conv.user_id == nil
      assert conv.title == nil
      assert conv.tags == []
      assert conv.model == nil
      assert conv.messages == []
      assert conv.metadata == %{}
      assert conv.deleted_at == nil
      assert conv.inserted_at == nil
      assert conv.updated_at == nil
    end

    test "creates with all fields" do
      now = DateTime.utc_now()

      conv = %Conversation{
        id: "conv-1",
        user_id: "user-1",
        title: "Chat about Elixir",
        tags: ["elixir", "help"],
        model: "gpt-4o",
        messages: [%Message{role: :user, content: "Hello"}],
        metadata: %{"source" => "web"},
        deleted_at: now,
        inserted_at: now,
        updated_at: now
      }

      assert conv.id == "conv-1"
      assert conv.user_id == "user-1"
      assert conv.title == "Chat about Elixir"
      assert conv.tags == ["elixir", "help"]
      assert conv.model == "gpt-4o"
      assert [%Message{role: :user}] = conv.messages
      assert conv.metadata == %{"source" => "web"}
      assert conv.deleted_at == now
      assert conv.inserted_at == now
      assert conv.updated_at == now
    end
  end

  describe "to_phoenix_ai/1" do
    test "converts to PhoenixAI.Conversation with messages" do
      store_conv = %Conversation{
        id: "conv-1",
        user_id: "user-1",
        title: "Test",
        model: "gpt-4o",
        metadata: %{"key" => "val"},
        messages: [
          %Message{id: "msg-1", role: :user, content: "Hello"},
          %Message{id: "msg-2", role: :assistant, content: "Hi"}
        ]
      }

      result = Conversation.to_phoenix_ai(store_conv)

      assert %PhoenixAI.Conversation{} = result
      assert result.id == "conv-1"
      assert result.metadata == %{"key" => "val"}
      assert length(result.messages) == 2
      assert [%PhoenixAI.Message{role: :user}, %PhoenixAI.Message{role: :assistant}] = result.messages
    end

    test "converts with empty messages" do
      store_conv = %Conversation{id: "conv-1"}

      result = Conversation.to_phoenix_ai(store_conv)

      assert result.messages == []
      assert result.metadata == %{}
    end
  end

  describe "from_phoenix_ai/2" do
    test "converts from PhoenixAI.Conversation" do
      phoenix_conv = %PhoenixAI.Conversation{
        id: "conv-1",
        messages: [
          %PhoenixAI.Message{role: :user, content: "Hello"}
        ],
        metadata: %{"key" => "val"}
      }

      result = Conversation.from_phoenix_ai(phoenix_conv)

      assert %Conversation{} = result
      assert result.id == "conv-1"
      assert result.metadata == %{"key" => "val"}
      assert [%Message{role: :user, content: "Hello"}] = result.messages
    end

    test "accepts opts for store-specific fields" do
      phoenix_conv = %PhoenixAI.Conversation{
        id: "conv-1",
        messages: [],
        metadata: %{}
      }

      result =
        Conversation.from_phoenix_ai(phoenix_conv,
          user_id: "user-1",
          title: "My Chat",
          tags: ["elixir"],
          model: "gpt-4o"
        )

      assert result.user_id == "user-1"
      assert result.title == "My Chat"
      assert result.tags == ["elixir"]
      assert result.model == "gpt-4o"
    end

    test "defaults store-specific fields when opts not provided" do
      phoenix_conv = %PhoenixAI.Conversation{id: "conv-1"}

      result = Conversation.from_phoenix_ai(phoenix_conv)

      assert result.user_id == nil
      assert result.title == nil
      assert result.tags == []
      assert result.model == nil
    end
  end
end
