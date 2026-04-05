defmodule PhoenixAI.Store.TelemetryHandlerTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store.TelemetryHandler

  require Logger

  setup do
    # Ensure handler is detached before each test
    TelemetryHandler.detach()
    on_exit(fn -> TelemetryHandler.detach() end)
    :ok
  end

  describe "attach/1" do
    test "attaches to phoenix_ai events" do
      assert :ok = TelemetryHandler.attach()

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      assert Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)
    end

    test "returns {:error, :already_exists} when already attached" do
      assert :ok = TelemetryHandler.attach()
      assert {:error, :already_exists} = TelemetryHandler.attach()
    end
  end

  describe "detach/0" do
    test "removes handler" do
      TelemetryHandler.attach()
      assert :ok = TelemetryHandler.detach()

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      refute Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)
    end

    test "is idempotent — does not crash when not attached" do
      # detach was already called in setup, calling again should be fine
      assert :ok = TelemetryHandler.detach()
    end
  end

  describe "handler_id/0" do
    test "returns a deterministic atom" do
      assert is_atom(TelemetryHandler.handler_id())
      assert TelemetryHandler.handler_id() == TelemetryHandler.handler_id()
    end
  end

  describe "handle_event/4" do
    test "does not crash even without a running store" do
      # Directly call handle_event — should not raise
      assert :ok =
               TelemetryHandler.handle_event(
                 [:phoenix_ai, :chat, :stop],
                 %{duration: 1_000_000},
                 %{provider: :test, model: "test-model", status: :ok, usage: %PhoenixAI.Usage{}},
                 []
               )
    end

    test "does not crash for tool_call event" do
      assert :ok =
               TelemetryHandler.handle_event(
                 [:phoenix_ai, :tool_call, :stop],
                 %{duration: 500_000},
                 %{tool: "my_tool"},
                 []
               )
    end

    test "records cost and logs event when Logger.metadata context is set" do
      # Start a store for the handler to use
      store_name = :"telemetry_handler_ctx_test_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        PhoenixAI.Store.start_link(
          name: store_name,
          adapter: PhoenixAI.Store.Adapters.ETS,
          event_log: [enabled: true]
        )

      # Create a conversation for context
      {:ok, conv} =
        PhoenixAI.Store.save_conversation(
          %PhoenixAI.Store.Conversation{metadata: %{}},
          store: store_name
        )

      # Set Logger metadata as a real user would
      Logger.metadata(
        phoenix_ai_store: %{
          conversation_id: conv.id,
          user_id: "test-user-1",
          store: store_name
        }
      )

      # Call handle_event with valid metadata
      assert :ok =
               TelemetryHandler.handle_event(
                 [:phoenix_ai, :chat, :stop],
                 %{duration: 1_000_000},
                 %{
                   provider: :test,
                   model: "test-model",
                   status: :ok,
                   usage: %PhoenixAI.Usage{
                     input_tokens: 10,
                     output_tokens: 20,
                     total_tokens: 30
                   }
                 },
                 []
               )

      # Give Task.start time to complete
      Process.sleep(100)

      # Verify event was logged
      {:ok, %{events: events}} =
        PhoenixAI.Store.list_events(
          [conversation_id: conv.id],
          store: store_name
        )

      assert Enum.any?(events, fn e -> e.type == :response_received end)

      # Clean up Logger metadata
      Logger.metadata(phoenix_ai_store: nil)
    end

    test "skips processing when no Logger.metadata context is set" do
      # Ensure no metadata is set
      Logger.metadata(phoenix_ai_store: nil)

      # Should return :ok without spawning tasks
      assert :ok =
               TelemetryHandler.handle_event(
                 [:phoenix_ai, :chat, :stop],
                 %{duration: 1_000_000},
                 %{provider: :test, model: "test-model", status: :ok, usage: %PhoenixAI.Usage{}},
                 []
               )
    end
  end
end
