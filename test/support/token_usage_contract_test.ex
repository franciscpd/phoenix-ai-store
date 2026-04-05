defmodule PhoenixAI.Store.TokenUsageContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.TokenUsage`.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.{Conversation, Message}

      @adapter unquote(macro_opts[:adapter])

      describe "TokenUsage: sum_conversation_tokens/2" do
        test "returns 0 for conversation with no messages", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)
          assert {:ok, 0} = @adapter.sum_conversation_tokens(conv.id, opts)
        end

        test "sums token_count across all messages in conversation", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          msg1 = build_message(%{content: "Hello", token_count: 10})
          msg2 = build_message(%{content: "World", token_count: 25})
          msg3 = build_message(%{content: "Test", token_count: nil})

          {:ok, _} = @adapter.add_message(conv.id, msg1, opts)
          {:ok, _} = @adapter.add_message(conv.id, msg2, opts)
          {:ok, _} = @adapter.add_message(conv.id, msg3, opts)

          assert {:ok, 35} = @adapter.sum_conversation_tokens(conv.id, opts)
        end

        test "returns 0 for nonexistent conversation", %{opts: opts} do
          assert {:ok, 0} = @adapter.sum_conversation_tokens("nonexistent", opts)
        end
      end

      describe "TokenUsage: sum_user_tokens/2" do
        test "returns 0 for user with no conversations", %{opts: opts} do
          assert {:ok, 0} = @adapter.sum_user_tokens("user_no_convs", opts)
        end

        test "sums token_count across all user conversations", %{opts: opts} do
          conv1 = build_conversation(%{user_id: "token_user"})
          conv2 = build_conversation(%{user_id: "token_user"})
          conv3 = build_conversation(%{user_id: "other_user"})

          {:ok, _} = @adapter.save_conversation(conv1, opts)
          {:ok, _} = @adapter.save_conversation(conv2, opts)
          {:ok, _} = @adapter.save_conversation(conv3, opts)

          {:ok, _} = @adapter.add_message(conv1.id, build_message(%{token_count: 100}), opts)
          {:ok, _} = @adapter.add_message(conv2.id, build_message(%{token_count: 50}), opts)
          {:ok, _} = @adapter.add_message(conv3.id, build_message(%{token_count: 999}), opts)

          assert {:ok, 150} = @adapter.sum_user_tokens("token_user", opts)
        end

        test "ignores messages with nil token_count", %{opts: opts} do
          conv = build_conversation(%{user_id: "nil_token_user"})
          {:ok, _} = @adapter.save_conversation(conv, opts)

          {:ok, _} = @adapter.add_message(conv.id, build_message(%{token_count: 40}), opts)
          {:ok, _} = @adapter.add_message(conv.id, build_message(%{token_count: nil}), opts)

          assert {:ok, 40} = @adapter.sum_user_tokens("nil_token_user", opts)
        end
      end
    end
  end
end
