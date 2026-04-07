defmodule PhoenixAI.Store.EventLogTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.EventLog
  alias PhoenixAI.Store.EventLog.Event

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.EventStore

    @impl true
    def log_event(event, _opts), do: {:ok, event}

    @impl true
    def list_events(_filters, _opts), do: {:ok, %{events: [], next_cursor: nil}}

    @impl true
    def count_events(_filters, _opts), do: {:ok, 0}
  end

  defmodule NoEventAdapter do
    # Does NOT implement EventStore — has no log_event/2
  end

  defp default_opts(overrides \\ []) do
    Keyword.merge(
      [adapter: StubAdapter, adapter_opts: []],
      overrides
    )
  end

  describe "log/3" do
    test "builds and saves event with correct type and data" do
      opts = default_opts(conversation_id: "conv-1", user_id: "user-1")

      assert {:ok, %Event{} = event} =
               EventLog.log(:message_sent, %{content: "hello"}, opts)

      assert event.type == :message_sent
      assert event.data == %{content: "hello"}
      assert event.conversation_id == "conv-1"
      assert event.user_id == "user-1"
      assert is_binary(event.id)
      assert %DateTime{} = event.inserted_at
    end

    test "applies redact_fn before saving" do
      redact = fn %Event{} = e ->
        %{e | data: Map.put(e.data, :content, "[REDACTED]")}
      end

      opts = default_opts(redact_fn: redact, conversation_id: "conv-2")

      assert {:ok, %Event{} = event} =
               EventLog.log(:message_sent, %{content: "secret stuff"}, opts)

      assert event.data.content == "[REDACTED]"
    end

    test "passes through when redact_fn is nil" do
      opts = default_opts(redact_fn: nil, conversation_id: "conv-3")

      assert {:ok, %Event{} = event} =
               EventLog.log(:message_sent, %{content: "visible"}, opts)

      assert event.data.content == "visible"
    end

    test "returns error for adapter without event store support" do
      opts = [adapter: NoEventAdapter, adapter_opts: []]

      assert {:error, :event_store_not_supported} =
               EventLog.log(:message_sent, %{content: "hello"}, opts)
    end

    test "passes conversation_id and user_id from opts" do
      opts = default_opts(conversation_id: "my-conv", user_id: "my-user")

      assert {:ok, %Event{} = event} =
               EventLog.log(:test_event, %{key: "val"}, opts)

      assert event.conversation_id == "my-conv"
      assert event.user_id == "my-user"
    end
  end

  describe "encode_cursor/1 and decode_cursor/1" do
    test "round-trips correctly" do
      now = DateTime.utc_now()
      id = Uniq.UUID.uuid7()

      event = %Event{
        id: id,
        type: :test,
        data: %{},
        inserted_at: now
      }

      cursor = EventLog.encode_cursor(event)
      assert is_binary(cursor)

      {:ok, {decoded_ts, decoded_id}} = EventLog.decode_cursor(cursor)
      assert decoded_id == id
      assert DateTime.compare(decoded_ts, now) == :eq
    end
  end
end
