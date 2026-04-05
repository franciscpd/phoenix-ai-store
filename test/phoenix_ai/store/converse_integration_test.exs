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
