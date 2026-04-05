defmodule PhoenixAI.Store.ConversePipeline do
  @moduledoc """
  Orchestrates the full conversation pipeline: load, save user message,
  prepare messages (memory + system prompt), check guardrails, call AI,
  save assistant message, and fire-and-forget post-processing.

  ## Usage

      context = %{
        adapter: MyAdapter,
        adapter_opts: [...],
        config: [...],
        provider: :openai,
        model: "gpt-4o",
        api_key: "sk-...",
        system: "You are helpful.",
        tools: nil,
        memory_pipeline: nil,
        guardrails: nil,
        user_id: "user-1",
        extract_facts: false,
        store: :my_store
      }

      {:ok, response} = ConversePipeline.run(conversation_id, "Hello", context)
  """

  alias PhoenixAI.Guardrails.Pipeline, as: GuardrailsPipeline
  alias PhoenixAI.Guardrails.Request
  alias PhoenixAI.Store.{CostTracking, EventLog, LongTermMemory, Message}
  alias PhoenixAI.Store.Memory.Pipeline, as: MemoryPipeline

  require Logger

  @doc """
  Runs the full conversation pipeline.

  Steps 1-6 in a `with` chain (fail-fast). Step 7 is fire-and-forget.

  Returns `{:ok, %PhoenixAI.Response{}}` or `{:error, term()}`.
  """
  @spec run(String.t(), String.t(), map()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def run(conversation_id, message, context) do
    with :ok <- validate_context(context) do
      run_pipeline(conversation_id, message, context)
    end
  end

  defp validate_context(context) do
    cond do
      is_nil(context[:provider]) -> {:error, {:missing_option, :provider}}
      is_nil(context[:model]) -> {:error, {:missing_option, :model}}
      true -> :ok
    end
  end

  defp run_pipeline(conversation_id, message, context) do
    adapter = context.adapter
    adapter_opts = context.adapter_opts

    with {:ok, _conv} <- load_conversation(adapter, conversation_id, adapter_opts),
         {:ok, _user_msg} <- save_user_message(adapter, conversation_id, message, adapter_opts),
         {:ok, messages} <- prepare_messages(adapter, conversation_id, adapter_opts, context),
         {:ok, messages} <- check_guardrails(messages, conversation_id, context),
         {:ok, response} <- call_ai(messages, context),
         {:ok, _asst_msg} <-
           save_assistant_message(adapter, conversation_id, response, adapter_opts) do
      post_process(conversation_id, response, context)
      {:ok, response}
    end
  end

  # Step 1: Load conversation (abort if not found)
  defp load_conversation(adapter, conversation_id, adapter_opts) do
    adapter.load_conversation(conversation_id, adapter_opts)
  end

  # Step 2: Save user message
  defp save_user_message(adapter, conversation_id, content, adapter_opts) do
    msg = %Message{role: :user, content: content}

    msg =
      msg
      |> maybe_generate_id()
      |> maybe_set_inserted_at(DateTime.utc_now())
      |> Map.put(:conversation_id, conversation_id)

    adapter.add_message(conversation_id, msg, adapter_opts)
  end

  # Step 3: Prepare messages — get from store, apply memory pipeline, convert, prepend system
  defp prepare_messages(adapter, conversation_id, adapter_opts, context) do
    with {:ok, store_messages} <- adapter.get_messages(conversation_id, adapter_opts) do
      messages = maybe_apply_memory(store_messages, context)
      phoenix_messages = Enum.map(messages, &Message.to_phoenix_ai/1)
      phoenix_messages = maybe_prepend_system(phoenix_messages, context[:system])
      {:ok, phoenix_messages}
    end
  end

  defp maybe_apply_memory(messages, %{memory_pipeline: nil}), do: messages

  defp maybe_apply_memory(messages, %{memory_pipeline: %MemoryPipeline{} = pipeline} = context) do
    memory_context = %{
      conversation_id: nil,
      model: context[:model],
      provider: context[:provider],
      max_tokens: nil,
      token_counter: PhoenixAI.Store.Memory.TokenCounter.Default
    }

    case MemoryPipeline.run(pipeline, messages, memory_context) do
      {:ok, filtered} -> filtered
      {:error, _} -> messages
    end
  end

  defp maybe_apply_memory(messages, _context), do: messages

  defp maybe_prepend_system(messages, nil), do: messages

  defp maybe_prepend_system(messages, system) do
    [%PhoenixAI.Message{role: :system, content: system} | messages]
  end

  # Step 4: Check guardrails (skip if nil/empty)
  defp check_guardrails(messages, _conversation_id, %{guardrails: nil}), do: {:ok, messages}
  defp check_guardrails(messages, _conversation_id, %{guardrails: []}), do: {:ok, messages}

  defp check_guardrails(messages, conversation_id, context) do
    request = %Request{
      messages: messages,
      conversation_id: conversation_id,
      user_id: context[:user_id],
      assigns: %{
        adapter: context.adapter,
        adapter_opts: context.adapter_opts
      }
    }

    case GuardrailsPipeline.run(context.guardrails, request) do
      {:ok, %Request{messages: updated_messages}} -> {:ok, updated_messages}
      {:error, _violation} = error -> error
    end
  end

  # Step 5: Call AI
  defp call_ai(messages, context) do
    opts =
      [provider: context.provider, model: context.model, api_key: context.api_key]
      |> maybe_add_tools(context[:tools])

    AI.chat(messages, opts)
  end

  defp maybe_add_tools(opts, nil), do: opts
  defp maybe_add_tools(opts, []), do: opts
  defp maybe_add_tools(opts, tools), do: Keyword.put(opts, :tools, tools)

  # Step 6: Save assistant message
  defp save_assistant_message(adapter, conversation_id, response, adapter_opts) do
    msg = %Message{
      role: :assistant,
      content: response.content
    }

    msg =
      msg
      |> maybe_generate_id()
      |> maybe_set_inserted_at(DateTime.utc_now())
      |> Map.put(:conversation_id, conversation_id)

    adapter.add_message(conversation_id, msg, adapter_opts)
  end

  # Step 7: Post-processing (fire-and-forget, truly async via Task.start)
  defp post_process(conversation_id, response, context) do
    Task.start(fn ->
      try do
        maybe_record_cost(conversation_id, response, context)
      rescue
        e -> Logger.warning("Post-process cost recording failed: #{inspect(e)}")
      end

      try do
        maybe_log_event(conversation_id, response, context)
      rescue
        e -> Logger.warning("Post-process event logging failed: #{inspect(e)}")
      end

      try do
        maybe_extract_facts(conversation_id, context)
      rescue
        e -> Logger.warning("Post-process fact extraction failed: #{inspect(e)}")
      end
    end)

    :ok
  end

  defp maybe_record_cost(conversation_id, %{usage: %PhoenixAI.Usage{}} = response, context) do
    if function_exported?(context.adapter, :save_cost_record, 2) do
      cost_opts = [
        adapter: context.adapter,
        adapter_opts: context.adapter_opts,
        user_id: context[:user_id],
        pricing_provider:
          get_in(context.config, [:cost_tracking, :pricing_provider]) ||
            CostTracking.PricingProvider.Static
      ]

      CostTracking.record(conversation_id, response, cost_opts)
    end
  end

  defp maybe_record_cost(_, _, _), do: :ok

  defp maybe_log_event(conversation_id, _response, context) do
    if get_in(context.config, [:event_log, :enabled]) &&
         function_exported?(context.adapter, :log_event, 2) do
      event_opts = [
        adapter: context.adapter,
        adapter_opts: context.adapter_opts,
        conversation_id: conversation_id,
        user_id: context[:user_id]
      ]

      EventLog.log(:response_received, %{}, event_opts)
    end
  end

  defp maybe_extract_facts(conversation_id, %{extract_facts: true} = context) do
    opts = [store: context.store, user_id: context[:user_id]]
    LongTermMemory.extract_facts(conversation_id, opts)
  end

  defp maybe_extract_facts(_, _), do: :ok

  # -- Helpers --

  defp maybe_generate_id(%{id: nil} = struct) do
    %{struct | id: Uniq.UUID.uuid7()}
  end

  defp maybe_generate_id(struct), do: struct

  defp maybe_set_inserted_at(%{inserted_at: nil} = struct, now) do
    %{struct | inserted_at: now}
  end

  defp maybe_set_inserted_at(struct, _now), do: struct
end
