defmodule PhoenixAI.Store.Events.UATTest do
  @moduledoc """
  Automated UAT for Phase 7 — Event Log.
  Covers all 4 success criteria from ROADMAP.md.
  """
  use ExUnit.Case

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.EventLog.Event
  alias PhoenixAI.Store.Guardrails.TokenBudget

  setup do
    store = :"events_uat_#{System.unique_integer([:positive])}"

    {:ok, _} =
      Store.start_link(
        name: store,
        adapter: PhoenixAI.Store.Adapters.ETS,
        event_log: [enabled: true]
      )

    conv = %Conversation{
      id: Uniq.UUID.uuid7(),
      user_id: "uat_user",
      title: "UAT Event",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store)

    {:ok, store: store, conv_id: conv.id}
  end

  # ── UAT 1: Automatic recording of all core event types (SC #1) ──

  describe "UAT 1: Automatic recording without extra developer code" do
    test "conversation_created logged on save_conversation", %{store: store, conv_id: conv_id} do
      {:ok, %{events: events}} =
        Store.list_events([conversation_id: conv_id, type: :conversation_created], store: store)

      assert length(events) == 1
      assert hd(events).type == :conversation_created
      # user_id is on the Event struct, not in data
      event = hd(events)
      assert event.user_id == "uat_user" || event.data[:user_id] == "uat_user"
    end

    test "message_sent logged on add_message", %{store: store, conv_id: conv_id} do
      {:ok, _} =
        Store.add_message(conv_id, %Message{role: :user, content: "Hello UAT", token_count: 10},
          store: store
        )

      {:ok, %{events: events}} =
        Store.list_events([conversation_id: conv_id, type: :message_sent], store: store)

      assert length(events) == 1
      event = hd(events)
      assert event.data[:role] == :user
      assert event.data[:content] == "Hello UAT"
    end

    test "policy_violation logged on guardrail halt", %{store: store, conv_id: conv_id} do
      # Add messages so TokenBudget has something to count
      {:ok, _} =
        Store.add_message(conv_id, %Message{role: :user, content: "msg", token_count: 500},
          store: store
        )

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "test"}],
        conversation_id: conv_id,
        user_id: "uat_user"
      }

      # TokenBudget with very low max → violation
      {:error, %PolicyViolation{}} =
        Store.check_guardrails(request, [{TokenBudget, scope: :conversation, max: 1}],
          store: store
        )

      {:ok, %{events: events}} =
        Store.list_events([conversation_id: conv_id, type: :policy_violation], store: store)

      assert length(events) >= 1
      event = hd(events)
      assert event.data[:reason] =~ "Token budget"
    end

    test "cost_recorded logged on record_cost", %{store: store, conv_id: conv_id} do
      pricing = %{{:openai, "gpt-4o"} => {"0.0000025", "0.00001"}}
      Application.put_env(:phoenix_ai_store, :pricing, pricing)

      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "uat_user")

      {:ok, %{events: events}} =
        Store.list_events([conversation_id: conv_id, type: :cost_recorded], store: store)

      assert length(events) == 1
      event = hd(events)
      assert event.data[:provider] == :openai || event.data[:provider] == "openai"
      assert event.data[:model] == "gpt-4o"

      Application.delete_env(:phoenix_ai_store, :pricing)
    end

    test "no extra developer code needed — just enabled: true", %{store: store, conv_id: conv_id} do
      # The setup only set event_log: [enabled: true] — nothing else.
      # Verify events were logged automatically.
      {:ok, %{events: events}} = Store.list_events([conversation_id: conv_id], store: store)
      # At minimum: conversation_created from setup
      assert length(events) >= 1
    end
  end

  # ── UAT 2: Append-only, immutable (SC #2) ──

  describe "UAT 2: Events are immutable — no update or delete API" do
    test "EventStore has no update callback" do
      refute function_exported?(PhoenixAI.Store.Adapters.ETS, :update_event, 2)
    end

    test "EventStore has no delete callback" do
      refute function_exported?(PhoenixAI.Store.Adapters.ETS, :delete_event, 2)
    end

    test "Store facade has no update/delete event functions" do
      refute function_exported?(PhoenixAI.Store, :update_event, 2)
      refute function_exported?(PhoenixAI.Store, :delete_event, 2)
    end
  end

  # ── UAT 3: Cursor-based pagination on (inserted_at, id) (SC #3) ──

  describe "UAT 3: Cursor-based pagination in correct chronological order" do
    test "paginate through events with cursor", %{store: store, conv_id: conv_id} do
      # Add several messages to generate events
      for i <- 1..4 do
        {:ok, _} =
          Store.add_message(
            conv_id,
            %Message{role: :user, content: "msg #{i}", token_count: i},
            store: store
          )
      end

      # Total: 1 conversation_created + 4 message_sent = 5 events

      # Page 1: first 2
      {:ok, %{events: page1, next_cursor: cursor1}} =
        Store.list_events([conversation_id: conv_id, limit: 2], store: store)

      assert length(page1) == 2
      assert cursor1 != nil
      # First event should be conversation_created (earliest)
      assert hd(page1).type == :conversation_created

      # Page 2: next 2
      {:ok, %{events: page2, next_cursor: cursor2}} =
        Store.list_events([conversation_id: conv_id, limit: 2, cursor: cursor1], store: store)

      assert length(page2) == 2
      assert cursor2 != nil

      # Page 3: last 1
      {:ok, %{events: page3, next_cursor: cursor3}} =
        Store.list_events([conversation_id: conv_id, limit: 2, cursor: cursor2], store: store)

      assert length(page3) == 1
      # last page
      assert cursor3 == nil

      # Verify chronological order across all pages
      all_events = page1 ++ page2 ++ page3
      timestamps = Enum.map(all_events, & &1.inserted_at)
      assert timestamps == Enum.sort(timestamps, {:asc, DateTime})
    end
  end

  # ── UAT 4: Redaction strips PII before persistence (SC #4) ──

  describe "UAT 4: Configurable redact_fn strips PII" do
    test "message content is redacted before persistence" do
      store = :"redact_uat_#{System.unique_integer([:positive])}"

      redact_fn = fn
        %Event{type: :message_sent, data: data} = event ->
          %{event | data: Map.put(data, :content, "[REDACTED]")}

        event ->
          event
      end

      {:ok, _} =
        Store.start_link(
          name: store,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: true, redact_fn: redact_fn]
        )

      conv = %Conversation{
        id: Uniq.UUID.uuid7(),
        user_id: "pii_user",
        title: "PII Test",
        messages: []
      }

      {:ok, _} = Store.save_conversation(conv, store: store)

      # Send a message with PII
      {:ok, _} =
        Store.add_message(
          conv.id,
          %Message{role: :user, content: "My SSN is 123-45-6789", token_count: 10},
          store: store
        )

      # Verify the event has redacted content
      {:ok, %{events: events}} =
        Store.list_events([conversation_id: conv.id, type: :message_sent], store: store)

      assert length(events) == 1
      assert hd(events).data[:content] == "[REDACTED]"

      # Verify conversation_created was NOT redacted (different type)
      {:ok, %{events: conv_events}} =
        Store.list_events([conversation_id: conv.id, type: :conversation_created], store: store)

      assert length(conv_events) == 1
      assert hd(conv_events).data[:title] == "PII Test"
    end
  end
end
