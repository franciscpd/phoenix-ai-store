defmodule PhoenixAI.Store.Memory.Strategies.SlidingWindowTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.SlidingWindow
  alias PhoenixAI.Store.Message

  defp build_messages(count) do
    for i <- 1..count do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}"}
    end
  end

  describe "apply/3" do
    test "keeps last N messages" do
      messages = build_messages(10)

      assert {:ok, result} = SlidingWindow.apply(messages, %{}, last: 3)
      assert length(result) == 3
      assert Enum.map(result, & &1.id) == ["msg-8", "msg-9", "msg-10"]
    end

    test "returns all messages when fewer than limit" do
      messages = build_messages(3)

      assert {:ok, result} = SlidingWindow.apply(messages, %{}, last: 10)
      assert length(result) == 3
      assert Enum.map(result, & &1.id) == ["msg-1", "msg-2", "msg-3"]
    end

    test "defaults to 50" do
      messages = build_messages(60)

      assert {:ok, result} = SlidingWindow.apply(messages, %{}, [])
      assert length(result) == 50
      assert List.first(result).id == "msg-11"
      assert List.last(result).id == "msg-60"
    end

    test "handles empty list" do
      assert {:ok, []} = SlidingWindow.apply([], %{}, last: 10)
    end
  end

  describe "priority/0" do
    test "returns 100" do
      assert SlidingWindow.priority() == 100
    end
  end
end
