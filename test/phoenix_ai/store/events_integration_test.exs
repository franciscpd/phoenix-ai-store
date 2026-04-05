defmodule PhoenixAI.Store.EventsIntegrationTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.EventLog.Event

  @store_name :events_integration_test_store

  setup do
    {:ok, _pid} =
      Store.start_link(
        name: @store_name,
        adapter: PhoenixAI.Store.Adapters.ETS,
        event_log: [enabled: true]
      )

    conv = %Conversation{
      id: "conv-evt-1",
      title: "Event test",
      user_id: "user-evt-1"
    }

    {:ok, _} = Store.save_conversation(conv, store: @store_name)

    %{conv: conv}
  end

  describe "save_conversation logs :conversation_created" do
    test "auto-logs event on save", %{conv: _conv} do
      # The setup already saved a conversation, so there should be an event
      assert {:ok, %{events: events}} =
               Store.list_events([type: :conversation_created], store: @store_name)

      assert length(events) >= 1
      event = List.last(events)
      assert event.type == :conversation_created
      assert event.data.title == "Event test"
    end
  end

  describe "add_message logs :message_sent" do
    test "auto-logs event with correct data", %{conv: conv} do
      msg = %Message{role: :user, content: "Hello world", token_count: 5}
      {:ok, _} = Store.add_message(conv.id, msg, store: @store_name)

      assert {:ok, %{events: events}} =
               Store.list_events([type: :message_sent], store: @store_name)

      assert length(events) >= 1
      event = List.last(events)
      assert event.type == :message_sent
      assert event.data.role == :user
      assert event.data.content == "Hello world"
      assert event.data.token_count == 5
    end
  end

  describe "explicit log_event/2" do
    test "works for custom events", %{conv: conv} do
      custom_event = %Event{
        conversation_id: conv.id,
        user_id: conv.user_id,
        type: :custom_action,
        data: %{action: "exported_pdf"}
      }

      assert {:ok, %Event{} = saved} =
               Store.log_event(custom_event, store: @store_name)

      assert saved.type == :custom_action
      assert saved.data.action == "exported_pdf"
      assert is_binary(saved.id)
    end
  end

  describe "cursor pagination through list_events" do
    test "paginates events correctly", %{conv: conv} do
      # Add several messages to generate events
      for i <- 1..5 do
        msg = %Message{role: :user, content: "msg #{i}"}
        {:ok, _} = Store.add_message(conv.id, msg, store: @store_name)
      end

      # Page 1 (limit 2)
      assert {:ok, %{events: page1, next_cursor: cursor1}} =
               Store.list_events(
                 [type: :message_sent, limit: 2],
                 store: @store_name
               )

      assert length(page1) == 2
      assert cursor1 != nil

      # Page 2
      assert {:ok, %{events: page2, next_cursor: cursor2}} =
               Store.list_events(
                 [type: :message_sent, limit: 2, cursor: cursor1],
                 store: @store_name
               )

      assert length(page2) == 2
      assert cursor2 != nil

      # Page 3 (last)
      assert {:ok, %{events: page3, next_cursor: cursor3}} =
               Store.list_events(
                 [type: :message_sent, limit: 2, cursor: cursor2],
                 store: @store_name
               )

      assert length(page3) == 1
      assert cursor3 == nil

      # All distinct
      all_ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(Enum.uniq(all_ids)) == 5
    end
  end

  describe "redact_fn strips PII" do
    test "redacts event data before persistence" do
      redact_fn = fn %Event{} = e ->
        %{e | data: Map.put(e.data, :content, "[REDACTED]")}
      end

      {:ok, _pid} =
        Store.start_link(
          name: :redact_test_store,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: true, redact_fn: redact_fn]
        )

      conv = %Conversation{id: "conv-redact", title: "Redact test", user_id: "user-r"}
      {:ok, _} = Store.save_conversation(conv, store: :redact_test_store)

      msg = %Message{role: :user, content: "my SSN is 123-45-6789"}
      {:ok, _} = Store.add_message(conv.id, msg, store: :redact_test_store)

      assert {:ok, %{events: events}} =
               Store.list_events([type: :message_sent], store: :redact_test_store)

      assert length(events) >= 1
      event = List.last(events)
      assert event.data.content == "[REDACTED]"
    end
  end

  describe "event logging disabled" do
    test "no events logged when enabled: false" do
      {:ok, _pid} =
        Store.start_link(
          name: :disabled_events_store,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: false]
        )

      conv = %Conversation{id: "conv-disabled", title: "No events", user_id: "user-d"}
      {:ok, _} = Store.save_conversation(conv, store: :disabled_events_store)

      msg = %Message{role: :user, content: "hello"}
      {:ok, _} = Store.add_message(conv.id, msg, store: :disabled_events_store)

      assert {:ok, %{events: []}} =
               Store.list_events([conversation_id: conv.id], store: :disabled_events_store)
    end
  end
end
