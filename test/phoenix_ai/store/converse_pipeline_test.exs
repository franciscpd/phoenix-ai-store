defmodule PhoenixAI.Store.ConversePipelineTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.TestProvider
  alias PhoenixAI.Store
  alias PhoenixAI.Store.Adapters.ETS, as: ETSAdapter
  alias PhoenixAI.Store.{Conversation, ConversePipeline, Instance, Message}
  alias PhoenixAI.Store.Guardrails.TokenBudget

  setup do
    {:ok, _} = TestProvider.start_state(self())

    on_exit(fn ->
      try do
        TestProvider.stop_state(self())
      rescue
        _ -> :ok
      end
    end)

    name = :"converse_pipeline_test_#{System.unique_integer([:positive])}"
    {:ok, _} = Store.start_link(name: name, adapter: ETSAdapter)

    {:ok, conv} =
      Store.save_conversation(
        %Conversation{title: "Pipeline Test", user_id: "user-1"},
        store: name
      )

    context = %{
      adapter: ETSAdapter,
      adapter_opts: Instance.get_adapter_opts(name),
      config: Instance.get_config(name),
      provider: :test,
      model: "test-model",
      api_key: "test-key",
      system: nil,
      tools: nil,
      memory_pipeline: nil,
      guardrails: nil,
      user_id: "user-1",
      extract_facts: false,
      store: name
    }

    {:ok, store: name, conv: conv, context: context}
  end

  defp set_responses(responses) do
    TestProvider.put_responses(self(), responses)
  end

  defp get_calls do
    TestProvider.get_calls(self())
  end

  describe "run/3" do
    test "runs full pipeline and returns Response", %{conv: conv, context: context} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "Hello from AI!",
           usage: %PhoenixAI.Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15}
         }}
      ])

      assert {:ok, %PhoenixAI.Response{content: "Hello from AI!"}} =
               ConversePipeline.run(conv.id, "Hi there", context)
    end

    test "saves both user and assistant messages", %{store: store, conv: conv, context: context} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "I'm the assistant",
           usage: %PhoenixAI.Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15}
         }}
      ])

      {:ok, _response} = ConversePipeline.run(conv.id, "User message", context)

      # Allow async post-processing to complete
      Process.sleep(50)

      {:ok, messages} = Store.get_messages(conv.id, store: store)
      assert length(messages) == 2

      [user_msg, assistant_msg] = messages
      assert user_msg.role == :user
      assert user_msg.content == "User message"
      assert assistant_msg.role == :assistant
      assert assistant_msg.content == "I'm the assistant"
    end

    test "returns :not_found for nonexistent conversation", %{context: context} do
      assert {:error, :not_found} =
               ConversePipeline.run("nonexistent-id", "Hello", context)
    end

    test "returns error when provider is missing", %{conv: conv, context: context} do
      context_no_provider = %{context | provider: nil}

      assert {:error, {:missing_option, :provider}} =
               ConversePipeline.run(conv.id, "Hello", context_no_provider)
    end

    test "returns error when model is missing", %{conv: conv, context: context} do
      context_no_model = %{context | model: nil}

      assert {:error, {:missing_option, :model}} =
               ConversePipeline.run(conv.id, "Hello", context_no_model)
    end

    test "respects guardrails — TokenBudget with max: 1 triggers violation", %{
      store: store,
      conv: conv,
      context: context
    } do
      # Add a message with tokens so accumulated > 1
      {:ok, _} =
        Store.add_message(
          conv.id,
          %Message{role: :user, content: "existing", token_count: 100},
          store: store
        )

      context_with_guardrails = %{
        context
        | guardrails: [{TokenBudget, [max: 1, scope: :conversation]}]
      }

      assert {:error, %PhoenixAI.Guardrails.PolicyViolation{policy: TokenBudget}} =
               ConversePipeline.run(conv.id, "New message", context_with_guardrails)
    end

    test "prepends system prompt when configured", %{conv: conv, context: context} do
      set_responses([
        {:ok,
         %PhoenixAI.Response{
           content: "System-aware response",
           usage: %PhoenixAI.Usage{input_tokens: 15, output_tokens: 8, total_tokens: 23}
         }}
      ])

      context_with_system = %{context | system: "You are a helpful assistant."}
      {:ok, _response} = ConversePipeline.run(conv.id, "Hello", context_with_system)

      # Verify the system message was sent to AI.chat
      [{messages, _opts}] = get_calls()
      assert hd(messages).role == :system
      assert hd(messages).content == "You are a helpful assistant."
    end
  end
end
