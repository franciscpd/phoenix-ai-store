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
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "b", value: "2"}, store: store)

      assert {:ok, facts} = LongTermMemory.get_facts("u1", store: store)
      assert length(facts) == 2
    end

    test "returns empty for unknown user", %{store: store} do
      assert {:ok, []} = LongTermMemory.get_facts("nobody", store: store)
    end
  end

  describe "delete_fact/3" do
    test "deletes a fact", %{store: store} do
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)
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
end
