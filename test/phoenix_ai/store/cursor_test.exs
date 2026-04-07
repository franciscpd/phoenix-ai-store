defmodule PhoenixAI.Store.CursorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Cursor

  describe "encode/2 and decode/1" do
    test "round-trips a DateTime and id" do
      ts = ~U[2026-04-06 12:00:00.000000Z]
      id = "01912345-6789-7abc-def0-123456789abc"

      cursor = Cursor.encode(ts, id)
      assert is_binary(cursor)
      assert {:ok, {^ts, ^id}} = Cursor.decode(cursor)
    end

    test "encode produces URL-safe base64 without padding" do
      ts = ~U[2026-01-01 00:00:00Z]
      cursor = Cursor.encode(ts, "some-id")
      refute String.contains?(cursor, "=")
      refute String.contains?(cursor, "+")
      refute String.contains?(cursor, "/")
    end
  end

  describe "decode/1 error handling" do
    test "returns error for invalid base64" do
      assert {:error, :invalid_cursor} = Cursor.decode("not-valid-base64!!!")
    end

    test "returns error for valid base64 but missing pipe separator" do
      cursor = Base.url_encode64("no-pipe-here", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor)
    end

    test "returns error for valid base64 with pipe but invalid datetime" do
      cursor = Base.url_encode64("not-a-datetime|some-id", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor)
    end

    test "returns error for empty string" do
      assert {:error, :invalid_cursor} = Cursor.decode("")
    end
  end
end
