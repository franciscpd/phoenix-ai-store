defmodule PhoenixAI.Store.AdapterContractTest do
  @moduledoc """
  Shared contract test suite for `PhoenixAI.Store.Adapter` implementations.

  Any adapter test module can `use` this module to get a standard set of
  tests that verify the adapter correctly implements all 8 callbacks.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          # ... set up adapter-specific state ...
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.AdapterContractTest, adapter: MyAdapter
      end

  The `setup` block MUST run before the `use` call and must return
  `{:ok, opts: opts}` where `opts` is the keyword list passed to
  every adapter callback.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.{Conversation, Message}

      @adapter unquote(macro_opts[:adapter])

      defp build_conversation(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          user_id: "user_1",
          title: "Test Conversation",
          tags: ["test"],
          model: "gpt-4",
          messages: [],
          metadata: %{}
        }

        struct(Conversation, Map.merge(defaults, attrs))
      end

      defp build_message(attrs \\ %{}) do
        attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

        defaults = %{
          role: :user,
          content: "Hello",
          metadata: %{}
        }

        struct(Message, Map.merge(defaults, attrs))
      end

      describe "save_conversation/2 and load_conversation/2" do
        test "saves and loads a conversation", %{opts: opts} do
          conv = build_conversation()

          assert {:ok, saved} = @adapter.save_conversation(conv, opts)
          assert saved.id == conv.id
          assert %DateTime{} = saved.inserted_at
          assert %DateTime{} = saved.updated_at

          assert {:ok, loaded} = @adapter.load_conversation(conv.id, opts)
          assert loaded.id == conv.id
          assert loaded.title == conv.title
          assert loaded.user_id == conv.user_id
        end

        test "upsert preserves inserted_at on update", %{opts: opts} do
          conv = build_conversation()

          {:ok, saved} = @adapter.save_conversation(conv, opts)
          original_inserted_at = saved.inserted_at

          updated_conv = %{conv | title: "Updated Title"}
          {:ok, upserted} = @adapter.save_conversation(updated_conv, opts)

          assert upserted.inserted_at == original_inserted_at
          assert upserted.title == "Updated Title"
        end

        test "load returns {:error, :not_found} for missing conversation", %{opts: opts} do
          assert {:error, :not_found} = @adapter.load_conversation("nonexistent", opts)
        end
      end

      describe "delete_conversation/2" do
        test "deletes an existing conversation", %{opts: opts} do
          conv = build_conversation()
          {:ok, _saved} = @adapter.save_conversation(conv, opts)

          assert :ok = @adapter.delete_conversation(conv.id, opts)
          assert {:error, :not_found} = @adapter.load_conversation(conv.id, opts)
        end

        test "returns {:error, :not_found} for missing conversation", %{opts: opts} do
          assert {:error, :not_found} = @adapter.delete_conversation("nonexistent", opts)
        end

        test "also deletes all messages for the conversation", %{opts: opts} do
          conv = build_conversation()
          {:ok, _saved} = @adapter.save_conversation(conv, opts)

          @adapter.add_message(conv.id, build_message(content: "msg 1"), opts)
          @adapter.add_message(conv.id, build_message(content: "msg 2"), opts)

          assert :ok = @adapter.delete_conversation(conv.id, opts)
          assert {:ok, []} = @adapter.get_messages(conv.id, opts)
        end
      end

      describe "list_conversations/2" do
        test "lists all conversations", %{opts: opts} do
          conv1 = build_conversation()
          conv2 = build_conversation(%{id: Uniq.UUID.uuid7()})
          {:ok, _} = @adapter.save_conversation(conv1, opts)
          {:ok, _} = @adapter.save_conversation(conv2, opts)

          {:ok, conversations} = @adapter.list_conversations([], opts)
          ids = Enum.map(conversations, & &1.id)

          assert conv1.id in ids
          assert conv2.id in ids
        end

        test "filters by user_id", %{opts: opts} do
          conv1 = build_conversation(%{user_id: "alice"})
          conv2 = build_conversation(%{id: Uniq.UUID.uuid7(), user_id: "bob"})
          {:ok, _} = @adapter.save_conversation(conv1, opts)
          {:ok, _} = @adapter.save_conversation(conv2, opts)

          {:ok, conversations} = @adapter.list_conversations([user_id: "alice"], opts)
          assert length(conversations) == 1
          assert hd(conversations).user_id == "alice"
        end
      end

      describe "count_conversations/2" do
        test "counts conversations", %{opts: opts} do
          {:ok, _} = @adapter.save_conversation(build_conversation(), opts)

          {:ok, _} =
            @adapter.save_conversation(build_conversation(%{id: Uniq.UUID.uuid7()}), opts)

          {:ok, count} = @adapter.count_conversations([], opts)
          assert count == 2
        end
      end

      describe "conversation_exists?/2" do
        test "returns true for existing conversation", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          assert {:ok, true} = @adapter.conversation_exists?(conv.id, opts)
        end

        test "returns false for missing conversation", %{opts: opts} do
          assert {:ok, false} = @adapter.conversation_exists?("nonexistent", opts)
        end
      end

      describe "add_message/3 and get_messages/2" do
        test "adds a message and retrieves it", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          msg = build_message(content: "Hello, world!")
          {:ok, saved_msg} = @adapter.add_message(conv.id, msg, opts)

          assert saved_msg.id != nil
          assert saved_msg.conversation_id == conv.id
          assert saved_msg.content == "Hello, world!"
          assert %DateTime{} = saved_msg.inserted_at

          {:ok, messages} = @adapter.get_messages(conv.id, opts)
          assert length(messages) == 1
          assert hd(messages).content == "Hello, world!"
        end

        test "returns {:error, :not_found} when adding to missing conversation", %{opts: opts} do
          msg = build_message()
          assert {:error, :not_found} = @adapter.add_message("nonexistent", msg, opts)
        end

        test "messages returned in insertion order", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          {:ok, msg1} = @adapter.add_message(conv.id, build_message(content: "first"), opts)
          Process.sleep(1)
          {:ok, msg2} = @adapter.add_message(conv.id, build_message(content: "second"), opts)
          Process.sleep(1)
          {:ok, msg3} = @adapter.add_message(conv.id, build_message(content: "third"), opts)

          {:ok, messages} = @adapter.get_messages(conv.id, opts)
          assert Enum.map(messages, & &1.content) == ["first", "second", "third"]
        end
      end
    end
  end
end
