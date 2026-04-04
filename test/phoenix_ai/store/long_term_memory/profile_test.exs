defmodule PhoenixAI.Store.LongTermMemory.ProfileTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Profile

  describe "struct" do
    test "creates a profile with defaults" do
      profile = %Profile{user_id: "user_1"}
      assert profile.user_id == "user_1"
      assert profile.summary == nil
      assert profile.metadata == %{}
      assert profile.id == nil
    end

    test "creates a profile with all fields" do
      now = DateTime.utc_now()

      profile = %Profile{
        id: "abc-123",
        user_id: "user_1",
        summary: "An Elixir developer who prefers Portuguese.",
        metadata: %{"expertise_level" => "senior", "tags" => ["elixir", "ai"]},
        inserted_at: now,
        updated_at: now
      }

      assert profile.summary =~ "Elixir"
      assert profile.metadata["expertise_level"] == "senior"
    end
  end
end
