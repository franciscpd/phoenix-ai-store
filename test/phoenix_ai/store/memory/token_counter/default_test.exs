defmodule PhoenixAI.Store.Memory.TokenCounter.DefaultTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Memory.TokenCounter.Default

  describe "count_tokens/2" do
    test "returns 0 for nil content" do
      assert Default.count_tokens(nil, []) == 0
    end

    test "returns 0 for empty string" do
      assert Default.count_tokens("", []) == 0
    end

    test "returns token count for normal content" do
      # "Hello world" = 11 chars -> div(11, 4) = 2
      assert Default.count_tokens("Hello world", []) == 2
    end

    test "returns minimum of 1 for short non-empty content" do
      # "Hi" = 2 chars -> div(2, 4) = 0, but min is 1
      assert Default.count_tokens("Hi", []) == 1
    end

    test "handles long content" do
      content = String.duplicate("a", 1000)
      assert Default.count_tokens(content, []) == 250
    end
  end
end
