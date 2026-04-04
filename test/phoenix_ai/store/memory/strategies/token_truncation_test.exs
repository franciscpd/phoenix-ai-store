defmodule PhoenixAI.Store.Memory.Strategies.TokenTruncationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.TokenTruncation
  alias PhoenixAI.Store.Message

  defp build_messages(count, token_count) do
    for i <- 1..count do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}", token_count: token_count}
    end
  end

  describe "apply/3" do
    test "keeps messages within budget using pre-computed token_count" do
      messages = build_messages(5, 10)

      assert {:ok, result} = TokenTruncation.apply(messages, %{}, max_tokens: 30)
      assert length(result) == 3
      assert Enum.map(result, & &1.id) == ["msg-3", "msg-4", "msg-5"]
    end

    test "keeps all when under budget" do
      messages = build_messages(3, 10)

      assert {:ok, result} = TokenTruncation.apply(messages, %{}, max_tokens: 100)
      assert length(result) == 3
      assert Enum.map(result, & &1.id) == ["msg-1", "msg-2", "msg-3"]
    end

    test "returns empty when first message exceeds budget" do
      messages = [%Message{id: "msg-1", role: :user, content: "Hello", token_count: 50}]

      assert {:ok, []} = TokenTruncation.apply(messages, %{}, max_tokens: 10)
    end

    test "uses TokenCounter when token_count is nil" do
      # Default counter: chars / 4, min 1
      # "Hello World!" = 12 chars / 4 = 3 tokens each
      messages =
        for i <- 1..5 do
          %Message{id: "msg-#{i}", role: :user, content: "Hello World!", token_count: nil}
        end

      # 3 tokens each, budget 9 -> keeps 3 newest
      assert {:ok, result} = TokenTruncation.apply(messages, %{}, max_tokens: 9)
      assert length(result) == 3
      assert Enum.map(result, & &1.id) == ["msg-3", "msg-4", "msg-5"]
    end

    test "handles empty list" do
      assert {:ok, []} = TokenTruncation.apply([], %{}, max_tokens: 100)
    end
  end

  describe "priority/0" do
    test "returns 200" do
      assert TokenTruncation.priority() == 200
    end
  end
end
