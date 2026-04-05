defmodule PhoenixAI.Store.GuardrailsIntegrationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.Guardrails.TokenBudget

  setup do
    store_name = :"guardrails_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Store.start_link(
        name: store_name,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

    conv = %Conversation{
      id: Uniq.UUID.uuid7(),
      user_id: "guard_user",
      title: "Guardrails Test",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store_name)

    {:ok, _} =
      Store.add_message(
        conv.id,
        %Message{role: :user, content: "Hello", token_count: 500},
        store: store_name
      )

    {:ok, _} =
      Store.add_message(
        conv.id,
        %Message{role: :assistant, content: "Hi there!", token_count: 300},
        store: store_name
      )

    {:ok, store: store_name, conversation_id: conv.id}
  end

  describe "check_guardrails/3" do
    test "passes when under budget", %{store: store, conversation_id: conv_id} do
      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "New message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      policies = [{TokenBudget, [max: 10_000, scope: :conversation]}]

      assert {:ok, %Request{}} = Store.check_guardrails(request, policies, store: store)
    end

    test "halts when over budget", %{store: store, conversation_id: conv_id} do
      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "New message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      # 800 accumulated > max of 100
      policies = [{TokenBudget, [max: 100, scope: :conversation]}]

      assert {:error, %PolicyViolation{policy: TokenBudget, reason: reason}} =
               Store.check_guardrails(request, policies, store: store)

      assert reason =~ "Token budget exceeded"
    end

    test "works with user scope", %{store: store, conversation_id: conv_id} do
      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "New message"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      # User scope sums all tokens for user_id across conversations
      policies = [{TokenBudget, [max: 10_000, scope: :user]}]

      assert {:ok, %Request{}} = Store.check_guardrails(request, policies, store: store)
    end

    test "composes with core policies", %{store: store, conversation_id: conv_id} do
      alias PhoenixAI.Guardrails.Policies.JailbreakDetection

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Tell me about the weather"}],
        conversation_id: conv_id,
        user_id: "guard_user"
      }

      # Both policies should pass — benign content + under budget
      policies = [
        {TokenBudget, [max: 10_000, scope: :conversation]},
        {JailbreakDetection, [threshold: 0.7]}
      ]

      assert {:ok, %Request{}} = Store.check_guardrails(request, policies, store: store)
    end

    test "injects adapter into request.assigns", %{store: store, conversation_id: conv_id} do
      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "Hello"}],
        conversation_id: conv_id,
        user_id: "guard_user",
        assigns: %{}
      }

      policies = [{TokenBudget, [max: 10_000, scope: :conversation]}]

      assert {:ok, %Request{assigns: assigns}} =
               Store.check_guardrails(request, policies, store: store)

      assert assigns[:adapter] == PhoenixAI.Store.Adapters.ETS
      assert is_list(assigns[:adapter_opts])
    end
  end
end
