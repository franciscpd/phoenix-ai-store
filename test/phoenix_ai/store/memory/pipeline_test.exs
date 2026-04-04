defmodule PhoenixAI.Store.Memory.PipelineTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.Pipeline
  alias PhoenixAI.Store.Memory.Strategies.{SlidingWindow, Summarization, TokenTruncation}
  alias PhoenixAI.Store.Message

  defp msg(role, content, opts \\ []) do
    struct(
      %Message{role: role, content: content, inserted_at: DateTime.utc_now()},
      opts
    )
  end

  describe "new/1" do
    test "creates pipeline from strategy tuples" do
      pipeline = Pipeline.new([{SlidingWindow, [last: 10]}])
      assert %Pipeline{strategies: [{SlidingWindow, [last: 10]}]} = pipeline
    end

    test "creates pipeline with multiple strategies" do
      strategies = [{SlidingWindow, [last: 10]}, {TokenTruncation, [max_tokens: 1000]}]
      pipeline = Pipeline.new(strategies)
      assert length(pipeline.strategies) == 2
    end
  end

  describe "preset/1" do
    test "creates :default preset with SlidingWindow" do
      pipeline = Pipeline.preset(:default)
      assert [{SlidingWindow, [last: 50]}] = pipeline.strategies
    end

    test "creates :aggressive preset with TokenTruncation" do
      pipeline = Pipeline.preset(:aggressive)
      assert [{TokenTruncation, [max_tokens: 4096]}] = pipeline.strategies
    end

    test "creates :summarize preset with Summarization and SlidingWindow" do
      pipeline = Pipeline.preset(:summarize)
      assert [{Summarization, [threshold: 20]}, {SlidingWindow, [last: 20]}] = pipeline.strategies
    end
  end

  describe "run/4" do
    test "extracts pinned system messages and re-injects them at the beginning" do
      messages = [
        msg(:system, "You are helpful"),
        msg(:user, "Hello"),
        msg(:assistant, "Hi there"),
        msg(:user, "How are you?")
      ]

      pipeline = Pipeline.new([{SlidingWindow, [last: 2]}])
      context = %{}

      {:ok, result} = Pipeline.run(pipeline, messages, context)

      # System message is pinned, re-injected at beginning
      assert hd(result).role == :system
      assert hd(result).content == "You are helpful"

      # SlidingWindow keeps last 2 of the non-pinned messages
      non_system = Enum.reject(result, &(&1.role == :system))
      assert length(non_system) == 2
      assert Enum.at(non_system, 0).content == "Hi there"
      assert Enum.at(non_system, 1).content == "How are you?"
    end

    test "preserves manually pinned messages (pinned: true)" do
      messages = [
        msg(:user, "Important note", pinned: true),
        msg(:user, "Message 1"),
        msg(:user, "Message 2"),
        msg(:user, "Message 3")
      ]

      pipeline = Pipeline.new([{SlidingWindow, [last: 1]}])
      context = %{}

      {:ok, result} = Pipeline.run(pipeline, messages, context)

      # Pinned message is at the beginning
      assert hd(result).content == "Important note"
      assert hd(result).pinned == true

      # Only last 1 non-pinned message kept
      non_pinned = Enum.reject(result, & &1.pinned)
      assert length(non_pinned) == 1
      assert hd(non_pinned).content == "Message 3"
    end

    test "applies strategies sorted by priority" do
      # SlidingWindow has priority 100, TokenTruncation has priority 200
      # Even if we list TokenTruncation first, SlidingWindow should run first
      messages =
        for i <- 1..10 do
          msg(:user, "Message #{i}", token_count: 10)
        end

      # TokenTruncation listed first but has higher priority number (200)
      # SlidingWindow listed second but has lower priority number (100) -> runs first
      pipeline =
        Pipeline.new([
          {TokenTruncation, [max_tokens: 100]},
          {SlidingWindow, [last: 5]}
        ])

      context = %{}

      {:ok, result} = Pipeline.run(pipeline, messages, context)

      # SlidingWindow (priority 100) runs first: keeps last 5 messages (6-10)
      # TokenTruncation (priority 200) runs second: 5 messages * 10 tokens = 50, fits in 100
      assert length(result) == 5
      assert hd(result).content == "Message 6"
    end

    test "handles empty message list" do
      pipeline = Pipeline.new([{SlidingWindow, [last: 10]}])
      {:ok, result} = Pipeline.run(pipeline, [], %{})
      assert result == []
    end

    test "passes context through to strategies" do
      # Use TokenTruncation which reads token_counter from context
      messages = [
        msg(:user, "Hello world", token_count: nil)
      ]

      # The default token counter estimates ~2 tokens for "Hello world"
      # Setting max_tokens high enough to keep it
      pipeline = Pipeline.new([{TokenTruncation, [max_tokens: 1000]}])
      context = %{token_counter: PhoenixAI.Store.Memory.TokenCounter.Default}

      {:ok, result} = Pipeline.run(pipeline, messages, context)
      assert length(result) == 1
    end

    test "returns error when a strategy fails" do
      defmodule FailingStrategy do
        @behaviour PhoenixAI.Store.Memory.Strategy

        @impl true
        def apply(_messages, _context, _opts), do: {:error, :boom}

        @impl true
        def priority, do: 50
      end

      pipeline = Pipeline.new([{FailingStrategy, []}])
      messages = [msg(:user, "Hello")]

      assert {:error, :boom} = Pipeline.run(pipeline, messages, %{})
    end

    test "handles pipeline with no strategies" do
      pipeline = Pipeline.new([])
      messages = [msg(:user, "Hello"), msg(:assistant, "Hi")]

      {:ok, result} = Pipeline.run(pipeline, messages, %{})
      assert length(result) == 2
    end

    test "multiple pinned messages preserve original order" do
      messages = [
        msg(:system, "System prompt 1"),
        msg(:user, "User msg 1"),
        msg(:system, "System prompt 2"),
        msg(:user, "User msg 2"),
        msg(:user, "User msg 3", pinned: true)
      ]

      pipeline = Pipeline.new([{SlidingWindow, [last: 1]}])
      {:ok, result} = Pipeline.run(pipeline, messages, %{})

      # Pinned messages come first, in original order
      assert Enum.at(result, 0).content == "System prompt 1"
      assert Enum.at(result, 1).content == "System prompt 2"
      assert Enum.at(result, 2).content == "User msg 3"

      # Only 1 non-pinned message kept
      non_pinned =
        Enum.reject(result, fn m -> m.role == :system || m.pinned end)

      assert length(non_pinned) == 1
      assert hd(non_pinned).content == "User msg 2"
    end
  end
end
