defmodule PhoenixAI.Store.Memory.Strategies.SummarizationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Strategies.Summarization
  alias PhoenixAI.Store.Message

  defp build_messages(count) do
    for i <- 1..count do
      %Message{id: "msg-#{i}", role: :user, content: "Message #{i}"}
    end
  end

  describe "apply/3" do
    test "returns messages unchanged when below threshold" do
      messages = build_messages(5)

      assert {:ok, result} = Summarization.apply(messages, %{}, threshold: 10)
      assert result == messages
    end

    test "summarizes older messages when above threshold" do
      messages = build_messages(20)

      summarize_fn = fn to_summarize, _context, _opts ->
        {:ok, "Summary of #{length(to_summarize)} messages"}
      end

      assert {:ok, result} =
               Summarization.apply(messages, %{}, threshold: 20, summarize_fn: summarize_fn)

      # threshold=20, keep_count=10, so summarize first 10, keep last 10
      assert length(result) == 11

      [summary | kept] = result

      assert summary.role == :system
      assert summary.content == "Summary of 10 messages"
      assert summary.pinned == true
      assert %DateTime{} = summary.inserted_at

      assert Enum.map(kept, & &1.id) == Enum.map(11..20, &"msg-#{&1}")
    end

    test "handles summarize_fn returning error" do
      messages = build_messages(20)

      summarize_fn = fn _msgs, _ctx, _opts ->
        {:error, :summarization_failed}
      end

      assert {:error, :summarization_failed} =
               Summarization.apply(messages, %{}, threshold: 20, summarize_fn: summarize_fn)
    end

    test "handles empty list" do
      assert {:ok, []} = Summarization.apply([], %{}, threshold: 20)
    end
  end

  describe "priority/0" do
    test "returns 300" do
      assert Summarization.priority() == 300
    end
  end
end
