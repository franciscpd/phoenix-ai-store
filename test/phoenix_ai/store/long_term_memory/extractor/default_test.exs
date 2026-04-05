defmodule PhoenixAI.Store.LongTermMemory.Extractor.DefaultTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Extractor.Default
  alias PhoenixAI.Store.Message

  defp make_messages do
    [
      %Message{role: :user, content: "I live in São Paulo and prefer Portuguese."},
      %Message{role: :assistant, content: "Noted! I'll communicate in Portuguese."}
    ]
  end

  describe "extract/3" do
    test "extracts facts using the provided extract_fn" do
      extract_fn = fn _messages, _context, _opts ->
        {:ok,
         ~s([{"key": "city", "value": "São Paulo"}, {"key": "language", "value": "Portuguese"}])}
      end

      context = %{user_id: "user_1", conversation_id: "conv_1"}
      opts = [extract_fn: extract_fn]

      assert {:ok, facts} = Default.extract(make_messages(), context, opts)
      assert length(facts) == 2
      assert %{key: "city", value: "São Paulo"} in facts
      assert %{key: "language", value: "Portuguese"} in facts
    end

    test "returns empty list when no facts extracted" do
      extract_fn = fn _messages, _context, _opts -> {:ok, "[]"} end
      context = %{user_id: "user_1"}

      assert {:ok, []} = Default.extract(make_messages(), context, extract_fn: extract_fn)
    end

    test "returns error when AI call fails" do
      extract_fn = fn _messages, _context, _opts -> {:error, :api_error} end
      context = %{user_id: "user_1"}

      assert {:error, {:extraction_failed, :api_error}} =
               Default.extract(make_messages(), context, extract_fn: extract_fn)
    end

    test "returns error when JSON is malformed" do
      extract_fn = fn _messages, _context, _opts -> {:ok, "not json at all"} end
      context = %{user_id: "user_1"}

      assert {:error, {:parse_error, _}} =
               Default.extract(make_messages(), context, extract_fn: extract_fn)
    end

    test "returns ok empty when messages list is empty" do
      context = %{user_id: "user_1"}
      assert {:ok, []} = Default.extract([], context, [])
    end
  end
end
