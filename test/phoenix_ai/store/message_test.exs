defmodule PhoenixAI.Store.MessageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Message

  describe "struct" do
    test "creates with defaults" do
      msg = %Message{}

      assert msg.id == nil
      assert msg.conversation_id == nil
      assert msg.role == nil
      assert msg.content == nil
      assert msg.tool_call_id == nil
      assert msg.tool_calls == nil
      assert msg.metadata == %{}
      assert msg.token_count == nil
      assert msg.inserted_at == nil
      assert msg.pinned == false
    end

    test "pinned defaults to false" do
      msg = %Message{}
      assert msg.pinned == false
    end

    test "pinned can be set to true" do
      msg = %Message{pinned: true}
      assert msg.pinned == true
    end

    test "creates with all fields" do
      now = DateTime.utc_now()

      msg = %Message{
        id: "msg-1",
        conversation_id: "conv-1",
        role: :user,
        content: "Hello",
        tool_call_id: "tc-1",
        tool_calls: [%{"id" => "tc-1", "type" => "function"}],
        metadata: %{"source" => "web"},
        token_count: 42,
        inserted_at: now
      }

      assert msg.id == "msg-1"
      assert msg.conversation_id == "conv-1"
      assert msg.role == :user
      assert msg.content == "Hello"
      assert msg.tool_call_id == "tc-1"
      assert msg.tool_calls == [%{"id" => "tc-1", "type" => "function"}]
      assert msg.metadata == %{"source" => "web"}
      assert msg.token_count == 42
      assert msg.inserted_at == now
    end
  end

  describe "to_phoenix_ai/1" do
    test "converts to PhoenixAI.Message" do
      store_msg = %Message{
        id: "msg-1",
        conversation_id: "conv-1",
        role: :assistant,
        content: "Hi there",
        tool_call_id: "tc-1",
        tool_calls: [%{"id" => "tc-1"}],
        metadata: %{"key" => "val"},
        token_count: 10,
        inserted_at: DateTime.utc_now()
      }

      result = Message.to_phoenix_ai(store_msg)

      assert %PhoenixAI.Message{} = result
      assert result.role == :assistant
      assert result.content == "Hi there"
      assert result.tool_call_id == "tc-1"
      assert result.tool_calls == [%{"id" => "tc-1"}]
      assert result.metadata == %{"key" => "val"}
    end

    test "handles nil optional fields" do
      store_msg = %Message{role: :user, content: "Hello"}

      result = Message.to_phoenix_ai(store_msg)

      assert result.role == :user
      assert result.content == "Hello"
      assert result.tool_call_id == nil
      assert result.tool_calls == nil
      assert result.metadata == %{}
    end

    test "does not include pinned field" do
      store_msg = %Message{role: :user, content: "Hello", pinned: true}

      result = Message.to_phoenix_ai(store_msg)

      refute Map.has_key?(Map.from_struct(result), :pinned)
    end
  end

  describe "from_phoenix_ai/1" do
    test "converts from PhoenixAI.Message" do
      phoenix_msg = %PhoenixAI.Message{
        role: :user,
        content: "Hello",
        tool_call_id: "tc-1",
        tool_calls: [%{"id" => "tc-1"}],
        metadata: %{"key" => "val"}
      }

      result = Message.from_phoenix_ai(phoenix_msg)

      assert %Message{} = result
      assert result.role == :user
      assert result.content == "Hello"
      assert result.tool_call_id == "tc-1"
      assert result.tool_calls == [%{"id" => "tc-1"}]
      assert result.metadata == %{"key" => "val"}
      assert result.id == nil
      assert result.conversation_id == nil
      assert result.token_count == nil
      assert result.inserted_at == nil
    end

    test "handles minimal PhoenixAI.Message" do
      phoenix_msg = %PhoenixAI.Message{role: :system, content: "You are helpful."}

      result = Message.from_phoenix_ai(phoenix_msg)

      assert result.role == :system
      assert result.content == "You are helpful."
      assert result.metadata == %{}
    end
  end
end
