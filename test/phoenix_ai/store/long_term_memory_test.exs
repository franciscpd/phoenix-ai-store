defmodule PhoenixAI.Store.LongTermMemoryTest do
  use ExUnit.Case

  alias PhoenixAI.Store
  alias PhoenixAI.Store.LongTermMemory
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}

  setup do
    store_name = :"ltm_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Store.start_link(name: store_name, adapter: PhoenixAI.Store.Adapters.ETS)

    {:ok, store: store_name}
  end

  describe "save_fact/2" do
    test "saves and retrieves a fact", %{store: store} do
      fact = %Fact{user_id: "user_1", key: "lang", value: "pt-BR"}
      assert {:ok, saved} = LongTermMemory.save_fact(fact, store: store)
      assert saved.key == "lang"
      assert saved.value == "pt-BR"
      assert saved.id != nil
    end
  end

  describe "get_facts/2" do
    test "returns facts for a user", %{store: store} do
      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)

      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "b", value: "2"}, store: store)

      assert {:ok, facts} = LongTermMemory.get_facts("u1", store: store)
      assert length(facts) == 2
    end

    test "returns empty for unknown user", %{store: store} do
      assert {:ok, []} = LongTermMemory.get_facts("nobody", store: store)
    end
  end

  describe "delete_fact/3" do
    test "deletes a fact", %{store: store} do
      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)

      assert :ok = LongTermMemory.delete_fact("u1", "a", store: store)
      assert {:ok, []} = LongTermMemory.get_facts("u1", store: store)
    end
  end

  describe "save_profile/2 and get_profile/2" do
    test "saves and retrieves a profile", %{store: store} do
      profile = %Profile{user_id: "u1", summary: "Dev.", metadata: %{"level" => "senior"}}
      assert {:ok, saved} = LongTermMemory.save_profile(profile, store: store)
      assert saved.summary == "Dev."

      assert {:ok, loaded} = LongTermMemory.get_profile("u1", store: store)
      assert loaded.summary == "Dev."
    end

    test "returns :not_found for unknown user", %{store: store} do
      assert {:error, :not_found} = LongTermMemory.get_profile("nobody", store: store)
    end
  end

  describe "delete_profile/2" do
    test "deletes a profile", %{store: store} do
      {:ok, _} = LongTermMemory.save_profile(%Profile{user_id: "u1", summary: "X"}, store: store)
      assert :ok = LongTermMemory.delete_profile("u1", store: store)
      assert {:error, :not_found} = LongTermMemory.get_profile("u1", store: store)
    end
  end

  describe "extract_facts/2" do
    setup %{store: store} do
      conv = %PhoenixAI.Store.Conversation{user_id: "user_1", messages: []}
      {:ok, conv} = Store.save_conversation(conv, store: store)

      {:ok, _} =
        Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "I live in SP"},
          store: store
        )

      {:ok, _} =
        Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :assistant, content: "Got it!"},
          store: store
        )

      {:ok, conv: conv}
    end

    test "extracts facts using extract_fn", %{store: store, conv: conv} do
      extract_fn = fn _messages, _context, _opts ->
        {:ok, ~s([{"key": "city", "value": "SP"}])}
      end

      assert {:ok, facts} =
               LongTermMemory.extract_facts(conv.id,
                 store: store,
                 extract_fn: extract_fn,
                 provider: :test
               )

      assert length(facts) == 1
      assert hd(facts).key == "city"

      # Facts are persisted
      assert {:ok, stored} = LongTermMemory.get_facts("user_1", store: store)
      assert length(stored) == 1
    end

    test "incremental extraction skips already-processed messages", %{store: store, conv: conv} do
      call_count = :counters.new(1, [:atomics])

      extract_fn = fn messages, _context, _opts ->
        :counters.add(call_count, 1, 1)
        count = length(messages)
        {:ok, ~s([{"key": "call_#{:counters.get(call_count, 1)}", "value": "#{count} msgs"}])}
      end

      # First extraction — processes 2 messages
      {:ok, _} =
        LongTermMemory.extract_facts(conv.id,
          store: store,
          extract_fn: extract_fn,
          provider: :test
        )

      # Add another message
      {:ok, _} =
        Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "New msg"},
          store: store
        )

      # Second extraction — should only process the new message
      {:ok, _} =
        LongTermMemory.extract_facts(conv.id,
          store: store,
          extract_fn: extract_fn,
          provider: :test
        )

      {:ok, facts} = LongTermMemory.get_facts("user_1", store: store)
      # Second call should have received fewer messages
      second_fact = Enum.find(facts, &(&1.key == "call_2"))
      assert second_fact.value == "1 msgs"
    end

    test "returns ok empty when no new messages", %{store: store, conv: conv} do
      extract_fn = fn _msgs, _ctx, _opts -> {:ok, "[]"} end

      # First extraction processes everything
      {:ok, _} =
        LongTermMemory.extract_facts(conv.id,
          store: store,
          extract_fn: extract_fn,
          provider: :test
        )

      # Second extraction has no new messages
      assert {:ok, []} =
               LongTermMemory.extract_facts(conv.id,
                 store: store,
                 extract_fn: extract_fn,
                 provider: :test
               )
    end

    test "respects max_facts_per_user limit", %{store: store, conv: conv} do
      extract_fn = fn _msgs, _ctx, _opts ->
        {:ok,
         ~s([{"key": "a", "value": "1"}, {"key": "b", "value": "2"}, {"key": "c", "value": "3"}])}
      end

      {:ok, saved} =
        LongTermMemory.extract_facts(conv.id,
          store: store,
          extract_fn: extract_fn,
          provider: :test,
          max_facts_per_user: 2
        )

      # Only 2 facts saved due to limit
      assert length(saved) == 2

      {:ok, stored} = LongTermMemory.get_facts("user_1", store: store)
      assert length(stored) == 2
    end

    test "upserts do not count toward limit", %{store: store, conv: conv} do
      # Pre-populate a fact
      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "user_1", key: "a", value: "old"}, store: store)

      extract_fn = fn _msgs, _ctx, _opts ->
        # "a" is an upsert, "b" is new
        {:ok, ~s([{"key": "a", "value": "new"}, {"key": "b", "value": "2"}])}
      end

      {:ok, saved} =
        LongTermMemory.extract_facts(conv.id,
          store: store,
          extract_fn: extract_fn,
          provider: :test,
          max_facts_per_user: 2
        )

      # Both should save — "a" is upsert (doesn't increase count), "b" is new (count goes to 2)
      assert length(saved) == 2

      {:ok, stored} = LongTermMemory.get_facts("user_1", store: store)
      assert length(stored) == 2
      assert Enum.find(stored, &(&1.key == "a")).value == "new"
    end

    test "async mode returns {:ok, :async} immediately", %{store: store, conv: conv} do
      extract_fn = fn _msgs, _ctx, _opts ->
        Process.sleep(50)
        {:ok, ~s([{"key": "async_fact", "value": "yes"}])}
      end

      assert {:ok, :async} =
               LongTermMemory.extract_facts(conv.id,
                 store: store,
                 extract_fn: extract_fn,
                 provider: :test,
                 extraction_mode: :async
               )

      # Wait for async task to complete
      Process.sleep(200)

      {:ok, facts} = LongTermMemory.get_facts("user_1", store: store)
      assert Enum.any?(facts, &(&1.key == "async_fact"))
    end
  end

  describe "apply_memory/3 with LTM injection" do
    setup %{store: store} do
      conv = %PhoenixAI.Store.Conversation{user_id: "user_1", messages: []}
      {:ok, conv} = Store.save_conversation(conv, store: store)

      {:ok, _} =
        Store.add_message(
          conv.id,
          %PhoenixAI.Store.Message{role: :system, content: "Be helpful.", pinned: true},
          store: store
        )

      {:ok, _} =
        Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "Hello"},
          store: store
        )

      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "user_1", key: "lang", value: "pt"}, store: store)

      {:ok, _} =
        LongTermMemory.save_profile(%Profile{user_id: "user_1", summary: "A dev."}, store: store)

      {:ok, conv: conv}
    end

    test "injects facts and profile as pinned messages", %{store: store, conv: conv} do
      pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)

      {:ok, messages} =
        Store.apply_memory(conv.id, pipeline,
          store: store,
          inject_long_term_memory: true,
          user_id: "user_1"
        )

      # Should have: profile msg + facts msg + system msg + user msg
      assert length(messages) >= 3

      contents = Enum.map(messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "A dev."))
      assert Enum.any?(contents, &(&1 =~ "lang: pt"))
    end

    test "does not inject when option is false", %{store: store, conv: conv} do
      pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)

      {:ok, messages} =
        Store.apply_memory(conv.id, pipeline, store: store)

      contents = Enum.map(messages, & &1.content)
      refute Enum.any?(contents, &(&1 =~ "A dev."))
    end
  end

  describe "update_profile/2" do
    test "creates a new profile from facts", %{store: store} do
      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "lang", value: "pt"}, store: store)

      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "role", value: "dev"}, store: store)

      profile_fn = fn _profile, _facts, _context, _opts ->
        {:ok, %{summary: "Portuguese-speaking developer.", metadata: %{"level" => "mid"}}}
      end

      assert {:ok, profile} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )

      assert profile.summary == "Portuguese-speaking developer."
      assert profile.metadata == %{"level" => "mid"}
    end

    test "refines existing profile", %{store: store} do
      {:ok, _} =
        LongTermMemory.save_profile(
          %Profile{user_id: "u1", summary: "A developer.", metadata: %{}},
          store: store
        )

      {:ok, _} =
        LongTermMemory.save_fact(%Fact{user_id: "u1", key: "lang", value: "pt"}, store: store)

      profile_fn = fn existing_profile, _facts, _ctx, _opts ->
        assert existing_profile.summary == "A developer."
        {:ok, %{summary: "A Portuguese-speaking developer.", metadata: %{}}}
      end

      assert {:ok, profile} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )

      assert profile.summary =~ "Portuguese"
    end

    test "returns error when profile_fn fails", %{store: store} do
      profile_fn = fn _p, _f, _c, _o -> {:error, :ai_failed} end

      assert {:error, {:profile_update_failed, :ai_failed}} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )
    end
  end
end
