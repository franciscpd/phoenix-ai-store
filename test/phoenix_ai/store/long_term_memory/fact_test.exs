defmodule PhoenixAI.Store.LongTermMemory.FactTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Fact

  describe "struct" do
    test "creates a fact with defaults" do
      fact = %Fact{user_id: "user_1", key: "lang", value: "pt-BR"}
      assert fact.user_id == "user_1"
      assert fact.key == "lang"
      assert fact.value == "pt-BR"
      assert fact.id == nil
      assert fact.inserted_at == nil
      assert fact.updated_at == nil
    end

    test "creates a fact with all fields" do
      now = DateTime.utc_now()

      fact = %Fact{
        id: "abc-123",
        user_id: "user_1",
        key: "lang",
        value: "pt-BR",
        inserted_at: now,
        updated_at: now
      }

      assert fact.id == "abc-123"
      assert fact.inserted_at == now
    end
  end
end
