defmodule PhoenixAI.Store do
  @moduledoc """
  Supervisor and public API facade for PhoenixAI conversation storage.

  `PhoenixAI.Store` is both a Supervisor (managing adapter-specific children
  and an `Instance` GenServer) and the public API facade that delegates to the
  configured adapter.

  ## Starting a store

      {:ok, _pid} = PhoenixAI.Store.start_link(
        name: :my_store,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

  ## Using the API

      {:ok, conv} = PhoenixAI.Store.save_conversation(conversation, store: :my_store)
      {:ok, conv} = PhoenixAI.Store.load_conversation(conv.id, store: :my_store)
  """

  use Supervisor

  alias PhoenixAI.Store.{Config, Conversation, Instance, Message}
  alias PhoenixAI.Store.ConversePipeline
  alias PhoenixAI.Guardrails.Pipeline, as: GuardrailsPipeline
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Memory.Pipeline
  alias PhoenixAI.Store.CostTracking
  alias PhoenixAI.Store.CostTracking.CostRecord
  alias PhoenixAI.Store.EventLog
  alias PhoenixAI.Store.EventLog.Event

  require Logger

  # -- Supervisor --

  @doc "Starts the store supervisor with the given options."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, :phoenix_ai_store_default)
    opts = Keyword.put(opts, :name, name)
    config = Config.resolve(opts)
    Supervisor.start_link(__MODULE__, config, name: :"#{name}_supervisor")
  end

  @impl true
  def init(config) do
    children =
      [{Task.Supervisor, name: :"#{config[:name]}_task_supervisor"}] ++
        adapter_children(config[:adapter], config) ++
        [{Instance, config}]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp adapter_children(PhoenixAI.Store.Adapters.ETS, config) do
    [{PhoenixAI.Store.Adapters.ETS.TableOwner, name: :"#{config[:name]}_table_owner"}]
  end

  defp adapter_children(_adapter, _config), do: []

  # -- Public API Facade --

  @doc """
  Saves a conversation. Generates a UUID v7 if `id` is nil and injects timestamps.
  """
  @spec save_conversation(Conversation.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def save_conversation(%Conversation{} = conv, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :save], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      if config[:user_id_required] && is_nil(conv.user_id) do
        {{:error, :user_id_required}, %{}}
      else
        now = DateTime.utc_now()

        conv =
          conv
          |> maybe_generate_id()
          |> maybe_set_inserted_at(now)
          |> Map.put(:updated_at, now)

        result = adapter.save_conversation(conv, adapter_opts)

        with {:ok, saved} <- result do
          maybe_log_event(
            :conversation_created,
            %{
              conversation_id: saved.id,
              user_id: saved.user_id,
              title: saved.title
            },
            opts
          )
        end

        {result, %{}}
      end
    end)
  end

  @doc """
  Loads a conversation by ID, including its messages.
  """
  @spec load_conversation(String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_found | term()}
  def load_conversation(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :load], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      result = adapter.load_conversation(id, adapter_opts)

      result =
        with {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) <- result,
             true <- config[:soft_delete] do
          {:error, :not_found}
        else
          _ -> result
        end

      {result, %{}}
    end)
  end

  @doc """
  Lists conversations matching the given filters.
  """
  @spec list_conversations(keyword(), keyword()) ::
          {:ok, [Conversation.t()]} | {:error, term()}
  def list_conversations(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :list], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      filters =
        if config[:soft_delete],
          do: Keyword.put_new(filters, :exclude_deleted, true),
          else: filters

      result = adapter.list_conversations(filters, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Deletes a conversation by ID.
  """
  @spec delete_conversation(String.t(), keyword()) :: :ok | {:error, :not_found | term()}
  def delete_conversation(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :delete], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      result =
        if config[:soft_delete] do
          case adapter.load_conversation(id, adapter_opts) do
            {:ok, conv} ->
              adapter.save_conversation(%{conv | deleted_at: DateTime.utc_now()}, adapter_opts)
              |> case do
                {:ok, _} -> :ok
                error -> error
              end

            {:error, _} = error ->
              error
          end
        else
          adapter.delete_conversation(id, adapter_opts)
        end

      {result, %{}}
    end)
  end

  @doc """
  Counts conversations matching the given filters.
  """
  @spec count_conversations(keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_conversations(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :count], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      filters =
        if config[:soft_delete],
          do: Keyword.put_new(filters, :exclude_deleted, true),
          else: filters

      result = adapter.count_conversations(filters, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Checks whether a conversation with the given ID exists.
  """
  @spec conversation_exists?(String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def conversation_exists?(id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :conversation, :exists], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)
      result = adapter.conversation_exists?(id, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Adds a message to a conversation. Generates a UUID v7 if `id` is nil
  and injects `inserted_at`.
  """
  @spec add_message(String.t(), Message.t(), keyword()) ::
          {:ok, Message.t()} | {:error, term()}
  def add_message(conversation_id, %Message{} = msg, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :message, :add], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      msg =
        msg
        |> maybe_generate_id()
        |> maybe_set_inserted_at(DateTime.utc_now())
        |> Map.put(:conversation_id, conversation_id)

      result = adapter.add_message(conversation_id, msg, adapter_opts)

      with {:ok, saved_msg} <- result do
        maybe_log_event(
          :message_sent,
          %{
            conversation_id: conversation_id,
            role: saved_msg.role,
            content: saved_msg.content,
            token_count: saved_msg.token_count
          },
          opts
        )
      end

      {result, %{}}
    end)
  end

  @doc """
  Gets all messages for a conversation, ordered by `inserted_at`.
  """
  @spec get_messages(String.t(), keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def get_messages(conversation_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :message, :get], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)
      result = adapter.get_messages(conversation_id, adapter_opts)
      {result, %{}}
    end)
  end

  @doc """
  Applies a memory pipeline to a conversation's messages.

  Fetches raw messages from the adapter, runs the pipeline (which handles
  pinned message extraction, strategy sorting/execution, and re-injection),
  then converts the result to `%PhoenixAI.Message{}` structs.

  ## Options

    * `:store` - the store name (default: `:phoenix_ai_store_default`)
    * `:model` - model override for strategy context
    * `:provider` - provider override for strategy context
    * `:max_tokens` - token budget override
    * `:token_counter` - token counter module override
  """
  @spec apply_memory(String.t(), Pipeline.t(), keyword()) ::
          {:ok, [PhoenixAI.Message.t()]} | {:error, term()}
  def apply_memory(conversation_id, %Pipeline{} = pipeline, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :memory, :apply], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      context = %{
        conversation_id: conversation_id,
        model: Keyword.get(opts, :model, config[:model]),
        provider: Keyword.get(opts, :provider, config[:provider]),
        max_tokens: Keyword.get(opts, :max_tokens),
        token_counter:
          Keyword.get(opts, :token_counter, PhoenixAI.Store.Memory.TokenCounter.Default)
      }

      case adapter.get_messages(conversation_id, adapter_opts) do
        {:ok, messages} ->
          before_count = length(messages)
          messages = maybe_inject_ltm(messages, adapter, adapter_opts, opts)

          case Pipeline.run(pipeline, messages, context) do
            {:ok, filtered} ->
              result = {:ok, Enum.map(filtered, &Message.to_phoenix_ai/1)}

              maybe_log_event(
                :memory_trimmed,
                %{
                  conversation_id: conversation_id,
                  before_count: before_count,
                  after_count: length(filtered)
                },
                opts
              )

              {result, %{}}

            {:error, _} = error ->
              {error, %{}}
          end

        {:error, _} = error ->
          {error, %{}}
      end
    end)
  end

  # -- Guardrails Facade --

  @doc """
  Runs guardrail policies against a request, with store adapter injection.

  Resolves the adapter from opts, injects it into `request.assigns`
  (so stateful policies like `TokenBudget` can query the store), then
  delegates to `PhoenixAI.Guardrails.Pipeline.run/2`.

  ## Example

      request = %Request{
        messages: messages,
        conversation_id: conv_id,
        user_id: user_id
      }

      policies = [
        {PhoenixAI.Store.Guardrails.TokenBudget, [max: 100_000, scope: :conversation]},
        {PhoenixAI.Guardrails.Policies.JailbreakDetection, [threshold: 0.7]}
      ]

      case Store.check_guardrails(request, policies, store: :my_store) do
        {:ok, request} -> AI.chat(request.messages, opts)
        {:error, violation} -> handle_violation(violation)
      end
  """
  @spec check_guardrails(Request.t(), [GuardrailsPipeline.policy_entry()], keyword()) ::
          {:ok, Request.t()} | {:error, PolicyViolation.t()}
  def check_guardrails(%Request{} = request, policies, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :guardrails, :check], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      request = %{
        request
        | assigns: Map.merge(request.assigns, %{adapter: adapter, adapter_opts: adapter_opts})
      }

      result = GuardrailsPipeline.run(policies, request)

      with {:error, %PhoenixAI.Guardrails.PolicyViolation{} = v} <- result do
        maybe_log_event(
          :policy_violation,
          %{
            conversation_id: request.conversation_id,
            user_id: request.user_id,
            policy: inspect(v.policy),
            reason: v.reason
          },
          opts
        )
      end

      {result, %{}}
    end)
  end

  # -- Cost Tracking Facade --

  @doc """
  Records the cost of a single AI provider call.

  Resolves the adapter and pricing provider from the store config,
  delegates to `CostTracking.record/3`, and wraps the call in a
  telemetry span `[:phoenix_ai_store, :cost, :record]`.

  ## Options

    * `:store` — the store name (default: `:phoenix_ai_store_default`)
    * `:user_id` — user to attribute cost to
    * `:pricing_provider` — module override for pricing lookup
    * `:metadata` — extra metadata map
  """
  @spec record_cost(String.t(), PhoenixAI.Response.t(), keyword()) ::
          {:ok, CostRecord.t()} | {:error, term()}
  def record_cost(conversation_id, %PhoenixAI.Response{} = response, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :cost, :record], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      cost_opts =
        opts
        |> Keyword.merge(adapter: adapter, adapter_opts: adapter_opts)
        |> Keyword.put_new(
          :pricing_provider,
          get_in(config, [:cost_tracking, :pricing_provider]) ||
            CostTracking.PricingProvider.Static
        )

      result = CostTracking.record(conversation_id, response, cost_opts)

      with {:ok, record} <- result do
        maybe_log_event(
          :cost_recorded,
          %{
            conversation_id: conversation_id,
            user_id: record.user_id,
            provider: record.provider,
            model: record.model,
            total_cost: Decimal.to_string(record.total_cost)
          },
          opts
        )
      end

      {result, %{}}
    end)
  end

  @doc """
  Returns all cost records for a conversation.

  Delegates to `adapter.get_cost_records/2` if the adapter supports CostStore.
  """
  @spec get_cost_records(String.t(), keyword()) ::
          {:ok, [CostRecord.t()]} | {:error, term()}
  def get_cost_records(conversation_id, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :cost, :get_records], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      result =
        if function_exported?(adapter, :get_cost_records, 2) do
          adapter.get_cost_records(conversation_id, adapter_opts)
        else
          {:error, :cost_store_not_supported}
        end

      {result, %{}}
    end)
  end

  @doc """
  Aggregates cost across records matching the given filters.

  Delegates to `adapter.sum_cost/2` if the adapter supports CostStore.

  ## Filters

    * `:user_id` — filter by user
    * `:conversation_id` — filter by conversation
    * `:provider` — filter by provider atom (e.g. `:openai`)
    * `:model` — filter by model string (e.g. `"gpt-4o"`)
    * `:after` — include only records with `recorded_at >= dt`
    * `:before` — include only records with `recorded_at <= dt`
  """
  @spec sum_cost(keyword(), keyword()) ::
          {:ok, Decimal.t()} | {:error, term()}
  def sum_cost(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :cost, :sum], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      result =
        if function_exported?(adapter, :sum_cost, 2) do
          adapter.sum_cost(filters, adapter_opts)
        else
          {:error, :cost_store_not_supported}
        end

      {result, %{}}
    end)
  end

  # -- Event Log Facade --

  @doc """
  Logs an event through the EventLog orchestrator.

  Resolves the adapter, injects `redact_fn` from config, and delegates
  to `EventLog.log/3`.
  """
  @spec log_event(Event.t(), keyword()) ::
          {:ok, Event.t()} | {:error, term()}
  def log_event(%Event{type: type, data: data} = event, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :event, :log_event], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      event_opts = [
        adapter: adapter,
        adapter_opts: adapter_opts,
        conversation_id: event.conversation_id,
        user_id: event.user_id,
        redact_fn: get_in(config, [:event_log, :redact_fn])
      ]

      result = EventLog.log(type, data, event_opts)
      {result, %{}}
    end)
  end

  @doc """
  Lists events matching the given filters.

  Delegates to `adapter.list_events/2` if the adapter supports EventStore.
  """
  @spec list_events(keyword(), keyword()) ::
          {:ok, %{events: [Event.t()], next_cursor: String.t() | nil}} | {:error, term()}
  def list_events(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :event, :list], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      result =
        if function_exported?(adapter, :list_events, 2) do
          adapter.list_events(filters, adapter_opts)
        else
          {:error, :event_store_not_supported}
        end

      {result, %{}}
    end)
  end

  @doc """
  Counts events matching the given filters.

  Delegates to `adapter.count_events/2` if the adapter supports EventStore.
  """
  @spec count_events(keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_events(filters \\ [], opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :event, :count], %{}, fn ->
      {adapter, adapter_opts, _config} = resolve_adapter(opts)

      result =
        if function_exported?(adapter, :count_events, 2) do
          adapter.count_events(filters, adapter_opts)
        else
          {:error, :event_store_not_supported}
        end

      {result, %{}}
    end)
  end

  # -- Converse Facade --

  @doc """
  Sends a user message to an AI provider within a persisted conversation.

  Resolves the adapter, merges per-call options over config-level `:converse`
  defaults, and delegates to `ConversePipeline.run/3` which handles:

    1. Saving the user message
    2. Loading conversation history
    3. Applying memory pipeline (if configured)
    4. Running guardrail checks (if configured)
    5. Calling the AI provider
    6. Saving the assistant response
    7. Recording cost (if cost tracking enabled)
    8. Extracting LTM facts (if enabled)

  ## Options

    * `:store` — store instance name (default: `:phoenix_ai_store_default`)
    * `:provider` — AI provider atom (e.g. `:openai`, `:test`)
    * `:model` — model string (e.g. `"gpt-4o"`)
    * `:api_key` — API key for the provider
    * `:system` — system prompt
    * `:tools` — tool definitions for function calling
    * `:memory_pipeline` — `%Pipeline{}` for memory management
    * `:guardrails` — list of guardrail policy entries
    * `:user_id` — user identifier
    * `:extract_facts` — whether to auto-extract LTM facts (default from config)
  """
  @spec converse(String.t(), String.t(), keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def converse(conversation_id, message, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :converse], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)
      converse_defaults = Keyword.get(config, :converse, [])

      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: Keyword.get(opts, :provider, converse_defaults[:provider]),
        model: Keyword.get(opts, :model, converse_defaults[:model]),
        api_key: Keyword.get(opts, :api_key, converse_defaults[:api_key]),
        system: Keyword.get(opts, :system, converse_defaults[:system]),
        tools: Keyword.get(opts, :tools),
        memory_pipeline: Keyword.get(opts, :memory_pipeline),
        guardrails: Keyword.get(opts, :guardrails),
        user_id: Keyword.get(opts, :user_id),
        extract_facts:
          Keyword.get(opts, :extract_facts, converse_defaults[:extract_facts] || false),
        store: Keyword.get(opts, :store, :phoenix_ai_store_default),
        on_chunk: Keyword.get(opts, :on_chunk),
        to: Keyword.get(opts, :to),
        streaming:
          not is_nil(Keyword.get(opts, :on_chunk)) or not is_nil(Keyword.get(opts, :to))
      }

      result = ConversePipeline.run(conversation_id, message, context)
      {result, %{streaming: context.streaming}}
    end)
  end

  @doc """
  Logs a custom event through the EventLog using a simplified map API.

  Builds an `%Event{}` from the given map and delegates to `log_event/2`.

  ## Required keys

    * `:type` — event type atom

  ## Optional keys

    * `:data` — event data map (default: `%{}`)
    * `:conversation_id` — associated conversation ID
    * `:user_id` — associated user ID
    * `:store` — store instance name (default: `:phoenix_ai_store_default`)

  ## Example

      Store.track(%{type: :user_feedback, data: %{rating: 5}, user_id: "u1"})
  """
  @spec track(map()) :: {:ok, Event.t()} | {:error, term()}
  def track(params) when is_map(params) do
    event = %Event{
      type: Map.fetch!(params, :type),
      data: Map.get(params, :data, %{}),
      conversation_id: Map.get(params, :conversation_id),
      user_id: Map.get(params, :user_id)
    }

    store = Map.get(params, :store, :phoenix_ai_store_default)
    log_event(event, store: store)
  end

  # -- Long-Term Memory Facade --

  alias PhoenixAI.Store.LongTermMemory
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}

  @doc "Persists a long-term memory fact for a user."
  @spec save_fact(Fact.t(), keyword()) :: {:ok, Fact.t()} | {:error, term()}
  def save_fact(fact, opts \\ []), do: LongTermMemory.save_fact(fact, opts)

  @doc "Returns all stored facts for a user."
  @spec get_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def get_facts(user_id, opts \\ []), do: LongTermMemory.get_facts(user_id, opts)

  @doc "Deletes a specific fact by key for a user."
  @spec delete_fact(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_fact(user_id, key, opts \\ []), do: LongTermMemory.delete_fact(user_id, key, opts)

  @doc "Extracts new facts from a conversation's unprocessed messages and persists them."
  @spec extract_facts(String.t(), keyword()) ::
          {:ok, [Fact.t()]} | {:ok, :async} | {:error, term()}
  def extract_facts(conversation_id, opts \\ []),
    do: LongTermMemory.extract_facts(conversation_id, opts)

  @doc "Persists a user profile."
  @spec save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def save_profile(profile, opts \\ []), do: LongTermMemory.save_profile(profile, opts)

  @doc "Loads the profile for a user by ID."
  @spec get_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, :not_found | term()}
  def get_profile(user_id, opts \\ []), do: LongTermMemory.get_profile(user_id, opts)

  @doc "Deletes the profile for a user."
  @spec delete_profile(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_profile(user_id, opts \\ []), do: LongTermMemory.delete_profile(user_id, opts)

  @doc "Regenerates and saves a user profile summary from their stored facts."
  @spec update_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def update_profile(user_id, opts \\ []), do: LongTermMemory.update_profile(user_id, opts)

  # -- Private Helpers --

  defp maybe_inject_ltm(messages, adapter, adapter_opts, opts) do
    user_id = Keyword.get(opts, :user_id)
    inject? = Keyword.get(opts, :inject_long_term_memory, false)

    if inject? && user_id && function_exported?(adapter, :save_fact, 2) do
      facts =
        case adapter.get_facts(user_id, adapter_opts) do
          {:ok, f} -> f
          {:error, _} -> []
        end

      profile =
        if function_exported?(adapter, :load_profile, 2) do
          case adapter.load_profile(user_id, adapter_opts) do
            {:ok, p} -> p
            _ -> nil
          end
        end

      PhoenixAI.Store.LongTermMemory.Injector.inject(facts, profile, messages)
    else
      messages
    end
  end

  defp resolve_adapter(opts) do
    store = Keyword.get(opts, :store, :phoenix_ai_store_default)
    config = Instance.get_config(store)
    adapter_opts = Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts, config}
  end

  defp maybe_log_event(type, data, opts) do
    {adapter, adapter_opts, config} = resolve_adapter(opts)

    if get_in(config, [:event_log, :enabled]) do
      event_opts = [
        adapter: adapter,
        adapter_opts: adapter_opts,
        conversation_id: data[:conversation_id],
        user_id: data[:user_id],
        redact_fn: get_in(config, [:event_log, :redact_fn])
      ]

      try do
        EventLog.log(type, Map.drop(data, [:conversation_id, :user_id]), event_opts)
      rescue
        e -> Logger.warning("Event log failed: #{inspect(e)}")
      end
    end

    :ok
  end

  defp maybe_generate_id(%{id: nil} = struct) do
    %{struct | id: Uniq.UUID.uuid7()}
  end

  defp maybe_generate_id(struct), do: struct

  defp maybe_set_inserted_at(%{inserted_at: nil} = struct, now) do
    %{struct | inserted_at: now}
  end

  defp maybe_set_inserted_at(struct, _now), do: struct
end
