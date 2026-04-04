defmodule PhoenixAI.Store.LongTermMemory.InjectorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.{Fact, Injector, Profile}
  alias PhoenixAI.Store.Message

  defp make_messages do
    [
      %Message{role: :system, content: "You are helpful.", pinned: true},
      %Message{role: :user, content: "Hello"}
    ]
  end

  describe "inject/3" do
    test "returns messages unchanged when no facts and no profile" do
      messages = make_messages()
      assert Injector.inject([], nil, messages) == messages
    end

    test "injects facts as pinned system message" do
      facts = [
        %Fact{user_id: "u1", key: "language", value: "Portuguese"},
        %Fact{user_id: "u1", key: "city", value: "São Paulo"}
      ]

      result = Injector.inject(facts, nil, make_messages())

      assert length(result) == 3
      [facts_msg | _rest] = result
      assert facts_msg.role == :system
      assert facts_msg.pinned == true
      assert facts_msg.content =~ "language: Portuguese"
      assert facts_msg.content =~ "city: São Paulo"
    end

    test "injects profile as pinned system message" do
      profile = %Profile{user_id: "u1", summary: "An Elixir developer."}

      result = Injector.inject([], profile, make_messages())

      assert length(result) == 3
      [profile_msg | _rest] = result
      assert profile_msg.role == :system
      assert profile_msg.pinned == true
      assert profile_msg.content =~ "An Elixir developer."
    end

    test "injects both profile and facts (profile first, then facts)" do
      facts = [%Fact{user_id: "u1", key: "lang", value: "pt"}]
      profile = %Profile{user_id: "u1", summary: "Senior dev."}

      result = Injector.inject(facts, profile, make_messages())

      assert length(result) == 4
      [profile_msg, facts_msg | _rest] = result
      assert profile_msg.content =~ "Senior dev."
      assert facts_msg.content =~ "lang: pt"
    end

    test "skips profile injection when summary is nil" do
      profile = %Profile{user_id: "u1", summary: nil}
      facts = [%Fact{user_id: "u1", key: "a", value: "b"}]

      result = Injector.inject(facts, profile, make_messages())
      # Only facts message + original messages
      assert length(result) == 3
    end
  end
end
