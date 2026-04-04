defmodule PhoenixAI.StoreTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}

  setup do
    name = :"store_test_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = Store.start_link(name: name, adapter: PhoenixAI.Store.Adapters.ETS)
    {:ok, store: name}
  end

  describe "save_conversation/2" do
    test "auto-generates UUID and timestamps when nil", %{store: store} do
      conv = %Conversation{title: "Hello"}
      {:ok, saved} = Store.save_conversation(conv, store: store)

      assert saved.id != nil
      assert String.length(saved.id) > 0
      assert %DateTime{} = saved.inserted_at
      assert %DateTime{} = saved.updated_at
      assert saved.title == "Hello"
    end

    test "preserves existing ID", %{store: store} do
      conv = %Conversation{id: "my-custom-id", title: "Custom"}
      {:ok, saved} = Store.save_conversation(conv, store: store)

      assert saved.id == "my-custom-id"
    end

    test "updates updated_at on re-save", %{store: store} do
      conv = %Conversation{title: "Original"}
      {:ok, saved} = Store.save_conversation(conv, store: store)
      original_inserted = saved.inserted_at

      # Small delay to ensure different timestamp
      Process.sleep(10)
      {:ok, updated} = Store.save_conversation(%{saved | title: "Updated"}, store: store)

      assert updated.inserted_at == original_inserted
      assert DateTime.compare(updated.updated_at, saved.updated_at) in [:gt, :eq]
    end
  end

  describe "load_conversation/2" do
    test "loads a saved conversation", %{store: store} do
      conv = %Conversation{title: "Test"}
      {:ok, saved} = Store.save_conversation(conv, store: store)
      {:ok, loaded} = Store.load_conversation(saved.id, store: store)

      assert loaded.id == saved.id
      assert loaded.title == "Test"
    end

    test "returns {:error, :not_found} for unknown ID", %{store: store} do
      assert {:error, :not_found} = Store.load_conversation("nonexistent", store: store)
    end

    test "loads conversation with messages", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "With Messages"}, store: store)
      {:ok, _msg} = Store.add_message(conv.id, %Message{role: :user, content: "Hi"}, store: store)

      {:ok, loaded} = Store.load_conversation(conv.id, store: store)
      assert length(loaded.messages) == 1
      assert hd(loaded.messages).content == "Hi"
    end
  end

  describe "delete_conversation/2" do
    test "deletes an existing conversation", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Delete Me"}, store: store)
      assert :ok = Store.delete_conversation(conv.id, store: store)
      assert {:error, :not_found} = Store.load_conversation(conv.id, store: store)
    end

    test "returns {:error, :not_found} for unknown ID", %{store: store} do
      assert {:error, :not_found} = Store.delete_conversation("nonexistent", store: store)
    end
  end

  describe "list_conversations/2" do
    test "lists all conversations", %{store: store} do
      {:ok, _} = Store.save_conversation(%Conversation{title: "A"}, store: store)
      {:ok, _} = Store.save_conversation(%Conversation{title: "B"}, store: store)

      {:ok, convs} = Store.list_conversations([], store: store)
      assert length(convs) == 2
    end

    test "filters by user_id", %{store: store} do
      {:ok, _} = Store.save_conversation(%Conversation{user_id: "u1", title: "A"}, store: store)
      {:ok, _} = Store.save_conversation(%Conversation{user_id: "u2", title: "B"}, store: store)

      {:ok, convs} = Store.list_conversations([user_id: "u1"], store: store)
      assert length(convs) == 1
      assert hd(convs).user_id == "u1"
    end
  end

  describe "count_conversations/2" do
    test "counts conversations", %{store: store} do
      {:ok, count} = Store.count_conversations([], store: store)
      assert count == 0

      {:ok, _} = Store.save_conversation(%Conversation{title: "A"}, store: store)
      {:ok, _} = Store.save_conversation(%Conversation{title: "B"}, store: store)

      {:ok, count} = Store.count_conversations([], store: store)
      assert count == 2
    end
  end

  describe "conversation_exists?/2" do
    test "returns true for existing conversation", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Exists"}, store: store)
      assert {:ok, true} = Store.conversation_exists?(conv.id, store: store)
    end

    test "returns false for unknown ID", %{store: store} do
      assert {:ok, false} = Store.conversation_exists?("nonexistent", store: store)
    end
  end

  describe "add_message/3" do
    test "adds message with auto-generated ID and timestamp", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Chat"}, store: store)
      msg = %Message{role: :user, content: "Hello!"}

      {:ok, saved_msg} = Store.add_message(conv.id, msg, store: store)

      assert saved_msg.id != nil
      assert saved_msg.conversation_id == conv.id
      assert saved_msg.role == :user
      assert saved_msg.content == "Hello!"
      assert %DateTime{} = saved_msg.inserted_at
    end

    test "returns error when conversation does not exist", %{store: store} do
      msg = %Message{role: :user, content: "Hello!"}
      assert {:error, :not_found} = Store.add_message("nonexistent", msg, store: store)
    end
  end

  describe "get_messages/2" do
    test "returns messages in insertion order", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Chat"}, store: store)

      {:ok, _} = Store.add_message(conv.id, %Message{role: :user, content: "First"}, store: store)

      Process.sleep(1)

      {:ok, _} =
        Store.add_message(conv.id, %Message{role: :assistant, content: "Second"}, store: store)

      {:ok, messages} = Store.get_messages(conv.id, store: store)
      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "First"
      assert Enum.at(messages, 1).content == "Second"
    end
  end

  describe "supervisor" do
    test "supervisor is registered with _supervisor suffix", %{store: store} do
      assert Process.whereis(:"#{store}_supervisor") != nil
    end

    test "instance is registered under store name", %{store: store} do
      assert Process.whereis(store) != nil
    end

    test "table_owner is registered for ETS adapter", %{store: store} do
      assert Process.whereis(:"#{store}_table_owner") != nil
    end
  end
end
