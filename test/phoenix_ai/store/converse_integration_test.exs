defmodule PhoenixAI.Store.ConverseIntegrationTest do
  # async: false — uses Application.put_env/3 for pricing config which is global state;
  # concurrent execution would cause pricing lookups in other tests to see wrong values.
  use ExUnit.Case, async: false

  alias PhoenixAI.Providers.TestProvider
  alias PhoenixAI.Store
  alias PhoenixAI.Store.Conversation
  alias PhoenixAI.Store.EventLog.Event

  setup do
    {:ok, _} = TestProvider.start_state(self())

    on_exit(fn ->
      try do
        TestProvider.stop_state(self())
      rescue
        _ -> :ok
      end
    end)

    store = :"converse_int_#{System.unique_integer([:positive])}"
    pricing = %{{:test, "test-model"} => {"0.001", "0.002"}}
    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    {:ok, _} =
      Store.start_link(
        name: store,
        adapter: PhoenixAI.Store.Adapters.ETS,
        event_log: [enabled: true],
        cost_tracking: [enabled: true]
      )

    conv = %Conversation{
      id: Uniq.UUID.uuid7(),
      user_id: "int_user",
      title: "Integration",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store)

    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    {:ok, store: store, conv_id: conv.id}
  end

  defp set_responses(responses) do
    TestProvider.put_responses(self(), responses)
  end

  describe "converse/3 via facade" do
    test "runs full pipeline and returns Response", %{store: store, conv_id: conv_id} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Integration response!",
           usage: %PhoenixAI.Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15}
         }}
      ])

      assert {:ok, %PhoenixAI.Response{content: "Integration response!"}} =
               Store.converse(conv_id, "Hello from integration",
                 provider: :test,
                 model: "test-model",
                 api_key: "test-key",
                 store: store
               )
    end

    test "persists user and assistant messages after converse", %{store: store, conv_id: conv_id} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Stored reply",
           usage: %PhoenixAI.Usage{input_tokens: 8, output_tokens: 4, total_tokens: 12}
         }}
      ])

      {:ok, _} =
        Store.converse(conv_id, "Save me",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store
        )

      {:ok, messages} = Store.get_messages(conv_id, store: store)

      roles = Enum.map(messages, & &1.role)
      assert :user in roles
      assert :assistant in roles

      user_msg = Enum.find(messages, &(&1.role == :user))
      assert user_msg.content == "Save me"

      assistant_msg = Enum.find(messages, &(&1.role == :assistant))
      assert assistant_msg.content == "Stored reply"
    end

    test "logs events automatically", %{store: store, conv_id: conv_id} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Event test",
           usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 3, total_tokens: 8}
         }}
      ])

      {:ok, _} =
        Store.converse(conv_id, "Trigger events",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store
        )

      # Allow async post-processing task to complete
      Process.sleep(100)

      {:ok, %{events: events}} = Store.list_events([], store: store)

      event_types = Enum.map(events, & &1.type)
      # conversation_created from setup + response_received from converse pipeline
      assert :conversation_created in event_types
      assert :response_received in event_types
    end

    test "returns error when both on_chunk and to are given", %{store: store, conv_id: conv_id} do
      assert {:error, :conflicting_streaming_options} =
               Store.converse(conv_id, "Hello",
                 provider: :test,
                 model: "test-model",
                 api_key: "test-key",
                 store: store,
                 on_chunk: fn _chunk -> :ok end,
                 to: self()
               )
    end

    test "dispatches chunks via on_chunk callback during streaming", %{
      store: store,
      conv_id: conv_id
    } do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Hi!",
           usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 3, total_tokens: 8}
         }}
      ])

      test_pid = self()

      {:ok, response} =
        Store.converse(conv_id, "Hello",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store,
          on_chunk: fn chunk -> send(test_pid, {:test_chunk, chunk}) end
        )

      assert response.content == "Hi!"

      # TestProvider.stream/3 splits "Hi!" into graphemes: "H", "i", "!"
      assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "H"}}
      assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "i"}}
      assert_received {:test_chunk, %PhoenixAI.StreamChunk{delta: "!"}}
      # Final chunk with finish_reason
      assert_received {:test_chunk, %PhoenixAI.StreamChunk{finish_reason: "stop"}}
    end

    test "sends chunks to PID via :to option", %{store: store, conv_id: conv_id} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Ok",
           usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
         }}
      ])

      {:ok, response} =
        Store.converse(conv_id, "Hello",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store,
          to: self()
        )

      assert response.content == "Ok"

      # AI.stream/2 with :to wraps chunks in {:phoenix_ai, {:chunk, chunk}}
      assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "O"}}}
      assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "k"}}}
      assert_received {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{finish_reason: "stop"}}}
    end
  end

  describe "converse/3 streaming telemetry" do
    test "includes streaming: true in telemetry span metadata when on_chunk given", %{
      store: store,
      conv_id: conv_id
    } do
      ref = make_ref()

      :telemetry.attach(
        "test-streaming-meta-#{inspect(ref)}",
        [:phoenix_ai_store, :converse, :stop],
        fn _event, _measurements, metadata, test_pid ->
          send(test_pid, {:telemetry_meta, metadata})
        end,
        self()
      )

      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Hi",
           usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
         }}
      ])

      {:ok, _} =
        Store.converse(conv_id, "Hello",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store,
          on_chunk: fn _chunk -> :ok end
        )

      assert_received {:telemetry_meta, metadata}
      assert metadata.streaming == true

      :telemetry.detach("test-streaming-meta-#{inspect(ref)}")
    end

    test "includes streaming: false in telemetry span metadata when no streaming opts", %{
      store: store,
      conv_id: conv_id
    } do
      ref = make_ref()

      :telemetry.attach(
        "test-no-streaming-meta-#{inspect(ref)}",
        [:phoenix_ai_store, :converse, :stop],
        fn _event, _measurements, metadata, test_pid ->
          send(test_pid, {:telemetry_meta, metadata})
        end,
        self()
      )

      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Hi",
           usage: %PhoenixAI.Usage{input_tokens: 5, output_tokens: 2, total_tokens: 7}
         }}
      ])

      {:ok, _} =
        Store.converse(conv_id, "Hello",
          provider: :test,
          model: "test-model",
          api_key: "test-key",
          store: store
        )

      assert_received {:telemetry_meta, metadata}
      assert metadata.streaming == false

      :telemetry.detach("test-no-streaming-meta-#{inspect(ref)}")
    end
  end

  describe "track/1" do
    test "logs custom event via simplified map API", %{store: store, conv_id: conv_id} do
      assert {:ok, %Event{type: :custom_action}} =
               Store.track(%{
                 type: :custom_action,
                 data: %{detail: "something"},
                 conversation_id: conv_id,
                 user_id: "int_user",
                 store: store
               })

      {:ok, %{events: events}} = Store.list_events([], store: store)
      custom = Enum.find(events, &(&1.type == :custom_action))
      assert custom
      assert custom.data.detail == "something"
    end

    test "works without optional fields", %{store: store} do
      assert {:ok, %Event{type: :bare_event}} =
               Store.track(%{
                 type: :bare_event,
                 store: store
               })

      {:ok, %{events: events}} = Store.list_events([], store: store)
      bare = Enum.find(events, &(&1.type == :bare_event))
      assert bare
      assert bare.conversation_id == nil
      assert bare.user_id == nil
    end
  end
end
