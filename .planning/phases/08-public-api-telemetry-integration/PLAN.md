# Phase 8: Public API & Telemetry Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire everything together: `converse/3` as the full pipeline entry point, `Store.track/1` as ergonomic event capture, and `TelemetryHandler` + `HandlerGuardian` for automatic PhoenixAI event capture.

**Architecture:** `ConversePipeline` is a dedicated module that resolves the adapter once and runs all steps (load → memory → guardrails → AI.chat → save → cost → events). `TelemetryHandler` is a plain module that attaches to PhoenixAI events and persists via async Tasks. `HandlerGuardian` is a supervised GenServer that polls every 30s and reattaches the handler if detached.

**Tech Stack:** Elixir, phoenix_ai ~> 0.3.1, Telemetry, NimbleOptions

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/converse_pipeline.ex` | Create | Full conversation pipeline |
| `test/phoenix_ai/store/converse_pipeline_test.exs` | Create | Pipeline unit tests |
| `lib/phoenix_ai/store/telemetry_handler.ex` | Create | PhoenixAI event handler |
| `test/phoenix_ai/store/telemetry_handler_test.exs` | Create | Handler tests |
| `lib/phoenix_ai/store/handler_guardian.ex` | Create | Supervised reattachment GenServer |
| `test/phoenix_ai/store/handler_guardian_test.exs` | Create | Guardian tests |
| `lib/phoenix_ai/store/config.ex` | Modify | Add converse config section |
| `lib/phoenix_ai/store.ex` | Modify | Add converse/3, track/1 |
| `test/phoenix_ai/store/converse_integration_test.exs` | Create | End-to-end integration tests |

---

## Task 1: ConversePipeline Module

**Files:**
- Create: `lib/phoenix_ai/store/converse_pipeline.ex`
- Create: `test/phoenix_ai/store/converse_pipeline_test.exs`

- [ ] **Step 1: Write tests with stub provider**

Create `test/phoenix_ai/store/converse_pipeline_test.exs`:

```elixir
defmodule PhoenixAI.Store.ConversePipelineTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.ConversePipeline

  setup do
    store = :"pipeline_test_#{System.unique_integer([:positive])}"

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
      user_id: "pipeline_user",
      title: "Pipeline Test",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store)

    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    {:ok, store: store, conv_id: conv.id}
  end

  describe "run/3" do
    test "executes full pipeline and returns response", %{store: store, conv_id: conv_id} do
      {adapter, adapter_opts, config} = resolve(store)

      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        system: nil,
        tools: nil,
        memory_pipeline: nil,
        guardrails: nil,
        user_id: "pipeline_user",
        extract_facts: false,
        store: store
      }

      assert {:ok, %PhoenixAI.Response{} = response} =
               ConversePipeline.run(conv_id, "Hello AI", context)

      assert response.content != nil
      assert response.provider == :test
    end

    test "saves user and assistant messages", %{store: store, conv_id: conv_id} do
      {adapter, adapter_opts, config} = resolve(store)

      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        system: nil,
        tools: nil,
        memory_pipeline: nil,
        guardrails: nil,
        user_id: "pipeline_user",
        extract_facts: false,
        store: store
      }

      {:ok, _} = ConversePipeline.run(conv_id, "Hello AI", context)

      {:ok, messages} = Store.get_messages(conv_id, store: store)
      assert length(messages) >= 2
      roles = Enum.map(messages, & &1.role)
      assert :user in roles
      assert :assistant in roles
    end

    test "returns error for nonexistent conversation", %{store: store} do
      {adapter, adapter_opts, config} = resolve(store)

      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        system: nil,
        tools: nil,
        memory_pipeline: nil,
        guardrails: nil,
        user_id: nil,
        extract_facts: false,
        store: store
      }

      assert {:error, :not_found} =
               ConversePipeline.run("nonexistent", "Hello", context)
    end

    test "respects guardrails and returns violation", %{store: store, conv_id: conv_id} do
      # Add a message with high token count
      {:ok, _} = Store.add_message(conv_id, %Message{role: :user, content: "x", token_count: 10_000}, store: store)

      {adapter, adapter_opts, config} = resolve(store)

      context = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        config: config,
        provider: :test,
        model: "test-model",
        api_key: "test-key",
        system: nil,
        tools: nil,
        memory_pipeline: nil,
        guardrails: [{PhoenixAI.Store.Guardrails.TokenBudget, scope: :conversation, max: 1}],
        user_id: "pipeline_user",
        extract_facts: false,
        store: store
      }

      assert {:error, %PhoenixAI.Guardrails.PolicyViolation{}} =
               ConversePipeline.run(conv_id, "Hello", context)
    end
  end

  defp resolve(store) do
    config = PhoenixAI.Store.Instance.get_config(store)
    adapter_opts = PhoenixAI.Store.Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts, config}
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/converse_pipeline_test.exs`
Expected: FAIL — `ConversePipeline` not defined

- [ ] **Step 3: Implement ConversePipeline**

Create `lib/phoenix_ai/store/converse_pipeline.ex`:

```elixir
defmodule PhoenixAI.Store.ConversePipeline do
  @moduledoc """
  Orchestrates the full conversation pipeline in a single pass.

  Resolves the adapter once and runs all steps sequentially:
  load → user message → memory → guardrails → AI call → assistant message → cost → events → LTM.

  Steps 1-6 abort on error. Steps 7-9 are fire-and-forget.
  """

  require Logger

  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.Memory.Pipeline, as: MemoryPipeline
  alias PhoenixAI.Guardrails.Pipeline, as: GuardrailsPipeline
  alias PhoenixAI.Guardrails.Request
  alias PhoenixAI.Store.{CostTracking, EventLog}

  @spec run(String.t(), String.t(), map()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def run(conversation_id, message, context) do
    adapter = context.adapter
    adapter_opts = context.adapter_opts

    with {:ok, _conv} <- load_conversation(adapter, adapter_opts, conversation_id),
         {:ok, _user_msg} <- save_user_message(adapter, adapter_opts, conversation_id, message, context),
         {:ok, ai_messages} <- prepare_messages(adapter, adapter_opts, conversation_id, context),
         :ok <- check_guardrails(ai_messages, conversation_id, context),
         {:ok, response} <- call_ai(ai_messages, context),
         {:ok, _asst_msg} <- save_assistant_message(adapter, adapter_opts, conversation_id, response, context) do
      post_process(conversation_id, response, context)
      {:ok, response}
    end
  end

  # -- Pipeline Steps --

  defp load_conversation(adapter, adapter_opts, conversation_id) do
    adapter.load_conversation(conversation_id, adapter_opts)
  end

  defp save_user_message(adapter, adapter_opts, conversation_id, message, context) do
    msg = %Message{
      role: :user,
      content: message,
      metadata: %{}
    }

    adapter.add_message(conversation_id, msg, adapter_opts)
  end

  defp prepare_messages(adapter, adapter_opts, conversation_id, context) do
    with {:ok, messages} <- adapter.get_messages(conversation_id, adapter_opts) do
      messages =
        if context[:memory_pipeline] do
          mem_context = %{
            conversation_id: conversation_id,
            model: context[:model],
            provider: context[:provider],
            max_tokens: nil,
            token_counter: PhoenixAI.Store.Memory.TokenCounter.Default
          }

          case MemoryPipeline.run(context.memory_pipeline, messages, mem_context) do
            {:ok, filtered} -> filtered
            {:error, _} -> messages
          end
        else
          messages
        end

      ai_messages = Enum.map(messages, &Message.to_phoenix_ai/1)

      # Prepend system message if configured
      ai_messages =
        if context[:system] do
          [%PhoenixAI.Message{role: :system, content: context.system} | ai_messages]
        else
          ai_messages
        end

      {:ok, ai_messages}
    end
  end

  defp check_guardrails(_messages, _conversation_id, %{guardrails: nil}), do: :ok
  defp check_guardrails(_messages, _conversation_id, %{guardrails: []}), do: :ok

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
      {:ok, _request} -> :ok
      {:error, _violation} = error -> error
    end
  end

  defp call_ai(messages, context) do
    opts =
      [
        provider: context.provider,
        model: context.model,
        api_key: context.api_key
      ]
      |> maybe_add(:tools, context[:tools])

    AI.chat(messages, opts)
  end

  defp save_assistant_message(adapter, adapter_opts, conversation_id, response, context) do
    msg = %Message{
      role: :assistant,
      content: response.content,
      token_count:
        if(response.usage, do: response.usage.output_tokens, else: nil),
      tool_calls: if(response.tool_calls != [], do: response.tool_calls, else: nil),
      metadata: %{}
    }

    adapter.add_message(conversation_id, msg, adapter_opts)
  end

  # -- Post-Processing (fire-and-forget) --

  defp post_process(conversation_id, response, context) do
    maybe_record_cost(conversation_id, response, context)
    maybe_log_events(conversation_id, response, context)
    maybe_extract_facts(conversation_id, context)
  end

  defp maybe_record_cost(conversation_id, response, context) do
    if response.usage && function_exported?(context.adapter, :save_cost_record, 2) do
      try do
        CostTracking.record(conversation_id, response,
          adapter: context.adapter,
          adapter_opts: context.adapter_opts,
          user_id: context[:user_id]
        )
      rescue
        e -> Logger.warning("ConversePipeline cost recording failed: #{inspect(e)}")
      end
    end
  end

  defp maybe_log_events(conversation_id, response, context) do
    if get_in(context.config, [:event_log, :enabled]) &&
         function_exported?(context.adapter, :log_event, 2) do
      try do
        EventLog.log(:response_received, %{
          provider: response.provider,
          model: response.model,
          content: response.content
        },
          adapter: context.adapter,
          adapter_opts: context.adapter_opts,
          conversation_id: conversation_id,
          user_id: context[:user_id],
          redact_fn: get_in(context.config, [:event_log, :redact_fn])
        )
      rescue
        e -> Logger.warning("ConversePipeline event logging failed: #{inspect(e)}")
      end
    end
  end

  defp maybe_extract_facts(conversation_id, context) do
    if context[:extract_facts] && function_exported?(context.adapter, :save_fact, 2) do
      try do
        PhoenixAI.Store.LongTermMemory.extract_facts(conversation_id,
          adapter: context.adapter,
          adapter_opts: context.adapter_opts,
          store: context[:store]
        )
      rescue
        e -> Logger.warning("ConversePipeline fact extraction failed: #{inspect(e)}")
      end
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/converse_pipeline_test.exs --trace`
Expected: All pass (TestProvider returns a canned response)

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All 353+ tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/converse_pipeline.ex test/phoenix_ai/store/converse_pipeline_test.exs
git commit -m "feat(api): add ConversePipeline with full conversation orchestration"
```

---

## Task 2: TelemetryHandler

**Files:**
- Create: `lib/phoenix_ai/store/telemetry_handler.ex`
- Create: `test/phoenix_ai/store/telemetry_handler_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/telemetry_handler_test.exs`:

```elixir
defmodule PhoenixAI.Store.TelemetryHandlerTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store.TelemetryHandler

  setup do
    # Detach any existing handler from prior tests
    try do
      :telemetry.detach(:phoenix_ai_store_telemetry_handler)
    rescue
      _ -> :ok
    end

    :ok
  end

  describe "attach/1" do
    test "attaches to phoenix_ai events" do
      assert :ok = TelemetryHandler.attach(store: :default)

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
      assert Enum.any?(handlers, &(&1.id == :phoenix_ai_store_telemetry_handler))

      :telemetry.detach(:phoenix_ai_store_telemetry_handler)
    end
  end

  describe "detach/0" do
    test "detaches the handler" do
      TelemetryHandler.attach(store: :default)
      assert :ok = TelemetryHandler.detach()

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
      refute Enum.any?(handlers, &(&1.id == :phoenix_ai_store_telemetry_handler))
    end
  end

  describe "handler_id/0" do
    test "returns deterministic atom" do
      assert TelemetryHandler.handler_id() == :phoenix_ai_store_telemetry_handler
    end
  end

  describe "handle_event/4" do
    test "handles chat stop event without crashing" do
      # Even without a running store, the handler should not crash
      # (fire-and-forget via Task.start)
      metadata = %{provider: :test, model: "test", status: :ok, usage: %PhoenixAI.Usage{}}
      measurements = %{duration: 1000}

      assert :ok =
               TelemetryHandler.handle_event(
                 [:phoenix_ai, :chat, :stop],
                 measurements,
                 metadata,
                 [store: :nonexistent_store]
               )
    end
  end
end
```

- [ ] **Step 2: Implement TelemetryHandler**

Create `lib/phoenix_ai/store/telemetry_handler.ex`:

```elixir
defmodule PhoenixAI.Store.TelemetryHandler do
  @moduledoc """
  Telemetry handler that automatically captures PhoenixAI events
  and persists them to the Store (cost records + event log).

  Attaches to `[:phoenix_ai, :chat, :stop]` and `[:phoenix_ai, :tool_call, :stop]`.
  Uses `Task.start/1` for async fire-and-forget persistence.

  ## Usage

  Add `HandlerGuardian` to your supervision tree for automatic
  attachment and crash recovery:

      {PhoenixAI.Store.HandlerGuardian, handler_opts: [store: :my_store]}

  Or attach manually:

      PhoenixAI.Store.TelemetryHandler.attach(store: :my_store)

  ## Context Propagation

  Set conversation context via Logger metadata before AI calls:

      Logger.metadata(phoenix_ai_store: %{conversation_id: id, user_id: uid})
  """

  require Logger

  alias PhoenixAI.Store
  alias PhoenixAI.Store.EventLog.Event

  @handler_id :phoenix_ai_store_telemetry_handler

  @events [
    [:phoenix_ai, :chat, :stop],
    [:phoenix_ai, :tool_call, :stop]
  ]

  @doc "Returns the deterministic handler ID."
  @spec handler_id() :: atom()
  def handler_id, do: @handler_id

  @doc "Attaches the handler to PhoenixAI telemetry events."
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, opts)
  end

  @doc "Detaches the handler."
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), keyword()) :: :ok
  def handle_event([:phoenix_ai, :chat, :stop], _measurements, metadata, opts) do
    ctx = get_context()
    store_opts = [store: opts[:store] || :phoenix_ai_store_default]

    Task.start(fn ->
      try do
        # Record cost if usage and conversation available
        if metadata[:usage] && ctx[:conversation_id] do
          response = %PhoenixAI.Response{
            provider: metadata[:provider],
            model: metadata[:model],
            usage: metadata[:usage],
            content: nil
          }

          Store.record_cost(ctx[:conversation_id], response,
            Keyword.merge(store_opts, user_id: ctx[:user_id]))
        end

        # Log response_received event
        Store.log_event(%Event{
          type: :response_received,
          conversation_id: ctx[:conversation_id],
          user_id: ctx[:user_id],
          data: %{
            provider: metadata[:provider],
            model: metadata[:model],
            status: metadata[:status]
          }
        }, store_opts)
      rescue
        e -> Logger.warning("TelemetryHandler chat event failed: #{inspect(e)}")
      end
    end)

    :ok
  end

  def handle_event([:phoenix_ai, :tool_call, :stop], _measurements, metadata, opts) do
    ctx = get_context()
    store_opts = [store: opts[:store] || :phoenix_ai_store_default]

    Task.start(fn ->
      try do
        Store.log_event(%Event{
          type: :tool_called,
          conversation_id: ctx[:conversation_id],
          user_id: ctx[:user_id],
          data: %{tool: metadata[:tool]}
        }, store_opts)
      rescue
        e -> Logger.warning("TelemetryHandler tool_call event failed: #{inspect(e)}")
      end
    end)

    :ok
  end

  defp get_context do
    Logger.metadata()[:phoenix_ai_store] || %{}
  end
end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/phoenix_ai/store/telemetry_handler_test.exs --trace`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/telemetry_handler.ex test/phoenix_ai/store/telemetry_handler_test.exs
git commit -m "feat(api): add TelemetryHandler for automatic PhoenixAI event capture"
```

---

## Task 3: HandlerGuardian

**Files:**
- Create: `lib/phoenix_ai/store/handler_guardian.ex`
- Create: `test/phoenix_ai/store/handler_guardian_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/handler_guardian_test.exs`:

```elixir
defmodule PhoenixAI.Store.HandlerGuardianTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store.{HandlerGuardian, TelemetryHandler}

  setup do
    try do
      :telemetry.detach(:phoenix_ai_store_telemetry_handler)
    rescue
      _ -> :ok
    end

    :ok
  end

  describe "start_link/1" do
    test "attaches TelemetryHandler on init" do
      {:ok, pid} =
        HandlerGuardian.start_link(
          name: :"guardian_test_#{System.unique_integer([:positive])}",
          handler_opts: [store: :default],
          interval: 60_000
        )

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
      assert Enum.any?(handlers, &(&1.id == :phoenix_ai_store_telemetry_handler))

      GenServer.stop(pid)
      :telemetry.detach(:phoenix_ai_store_telemetry_handler)
    end
  end

  describe "reattachment" do
    test "reattaches handler after detachment" do
      {:ok, pid} =
        HandlerGuardian.start_link(
          name: :"guardian_reattach_#{System.unique_integer([:positive])}",
          handler_opts: [store: :default],
          interval: 100
        )

      # Detach the handler manually
      TelemetryHandler.detach()

      # Verify detached
      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
      refute Enum.any?(handlers, &(&1.id == :phoenix_ai_store_telemetry_handler))

      # Wait for guardian to reattach (interval is 100ms)
      Process.sleep(200)

      # Should be reattached
      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])
      assert Enum.any?(handlers, &(&1.id == :phoenix_ai_store_telemetry_handler))

      GenServer.stop(pid)
      :telemetry.detach(:phoenix_ai_store_telemetry_handler)
    end
  end
end
```

- [ ] **Step 2: Implement HandlerGuardian**

Create `lib/phoenix_ai/store/handler_guardian.ex`:

```elixir
defmodule PhoenixAI.Store.HandlerGuardian do
  @moduledoc """
  Supervised GenServer that ensures the TelemetryHandler stays attached.

  Periodically polls `:telemetry.list_handlers/1` and reattaches the
  handler if it was silently detached (e.g., due to a handler crash).

  ## Usage

  Add to your supervision tree:

      {PhoenixAI.Store.HandlerGuardian,
        handler_opts: [store: :my_store],
        interval: 30_000}

  ## Options

    * `:handler_opts` — keyword options passed to `TelemetryHandler.attach/1`
    * `:interval` — polling interval in milliseconds (default: 30_000)
    * `:name` — GenServer name registration
  """

  use GenServer

  require Logger

  alias PhoenixAI.Store.TelemetryHandler

  @default_interval 30_000

  @doc "Starts the HandlerGuardian."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    handler_opts = Keyword.get(opts, :handler_opts, [])
    interval = Keyword.get(opts, :interval, @default_interval)

    # Attach on startup
    case TelemetryHandler.attach(handler_opts) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

    schedule_check(interval)
    {:ok, %{handler_opts: handler_opts, interval: interval}}
  end

  @impl true
  def handle_info(:check_handlers, state) do
    handler_id = TelemetryHandler.handler_id()
    handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

    unless Enum.any?(handlers, &(&1.id == handler_id)) do
      Logger.warning("PhoenixAI.Store.TelemetryHandler was detached, reattaching...")

      case TelemetryHandler.attach(state.handler_opts) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end

    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_handlers, interval)
  end
end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/phoenix_ai/store/handler_guardian_test.exs --trace`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/handler_guardian.ex test/phoenix_ai/store/handler_guardian_test.exs
git commit -m "feat(api): add HandlerGuardian for telemetry handler reattachment"
```

---

## Task 4: Store Facade — converse/3 + track/1 + Config

**Files:**
- Modify: `lib/phoenix_ai/store/config.ex`
- Modify: `lib/phoenix_ai/store.ex`
- Create: `test/phoenix_ai/store/converse_integration_test.exs`

- [ ] **Step 1: Write integration tests**

Create `test/phoenix_ai/store/converse_integration_test.exs`:

```elixir
defmodule PhoenixAI.Store.ConverseIntegrationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.EventLog.Event

  setup do
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
      title: "Integration Test",
      messages: []
    }

    {:ok, _} = Store.save_conversation(conv, store: store)

    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    {:ok, store: store, conv_id: conv.id}
  end

  describe "converse/3" do
    test "runs full pipeline via facade", %{store: store, conv_id: conv_id} do
      assert {:ok, %PhoenixAI.Response{} = response} =
               Store.converse(conv_id, "Hello from integration test",
                 store: store,
                 provider: :test,
                 model: "test-model",
                 api_key: "test-key"
               )

      assert response.content != nil
    end

    test "persists both user and assistant messages", %{store: store, conv_id: conv_id} do
      {:ok, _} =
        Store.converse(conv_id, "Test message",
          store: store,
          provider: :test,
          model: "test-model",
          api_key: "test-key"
        )

      {:ok, messages} = Store.get_messages(conv_id, store: store)
      roles = Enum.map(messages, & &1.role)
      assert :user in roles
      assert :assistant in roles
    end

    test "logs events automatically", %{store: store, conv_id: conv_id} do
      {:ok, _} =
        Store.converse(conv_id, "Event test",
          store: store,
          provider: :test,
          model: "test-model",
          api_key: "test-key"
        )

      # Wait for async event logging
      Process.sleep(50)

      {:ok, %{events: events}} = Store.list_events([conversation_id: conv_id], store: store)
      types = Enum.map(events, & &1.type)
      # Should have at least conversation_created (from setup) + message_sent + response_received
      assert :conversation_created in types
      assert :message_sent in types
    end
  end

  describe "track/1" do
    test "logs custom event via simplified API", %{store: store, conv_id: conv_id} do
      assert {:ok, %Event{type: :custom_action}} =
               Store.track(%{
                 type: :custom_action,
                 data: %{action: "manual_track"},
                 conversation_id: conv_id,
                 user_id: "int_user",
                 store: store
               })
    end

    test "works without optional fields", %{store: store} do
      assert {:ok, %Event{type: :system_event}} =
               Store.track(%{
                 type: :system_event,
                 data: %{info: "test"},
                 store: store
               })
    end
  end
end
```

- [ ] **Step 2: Add converse config section**

In `lib/phoenix_ai/store/config.ex`, add after the `event_log` key:

```elixir
converse: [
  type: :keyword_list,
  default: [],
  doc: "Default options for converse/3.",
  keys: [
    provider: [type: :atom, doc: "Default AI provider."],
    model: [type: :string, doc: "Default model."],
    api_key: [type: :string, doc: "Default API key."],
    system: [type: :string, doc: "Default system prompt."],
    extract_facts: [
      type: :boolean,
      default: false,
      doc: "Auto-extract LTM facts after each converse call."
    ]
  ]
]
```

- [ ] **Step 3: Add converse/3 and track/1 to Store facade**

Add aliases: `alias PhoenixAI.Store.ConversePipeline`

Add after the Event Log Facade section:

```elixir
# -- Converse Pipeline --

@doc """
Runs the full conversation pipeline: load → memory → guardrails →
AI call → save → cost → events → return.

## Options

  * `:store` — store instance name
  * `:provider` — AI provider atom (e.g., `:openai`)
  * `:model` — model string (e.g., `"gpt-4o"`)
  * `:api_key` — API key
  * `:system` — system prompt
  * `:tools` — list of tool modules
  * `:memory_pipeline` — `%Pipeline{}` for memory management
  * `:guardrails` — list of `{policy, opts}` tuples
  * `:user_id` — user to attribute the conversation to
  * `:extract_facts` — extract LTM facts after the call (default: false)
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
      extract_facts: Keyword.get(opts, :extract_facts, converse_defaults[:extract_facts] || false),
      store: Keyword.get(opts, :store, :phoenix_ai_store_default)
    }

    result = ConversePipeline.run(conversation_id, message, context)
    {result, %{}}
  end)
end

# -- Track (ergonomic event capture) --

@doc """
Logs an event using a simplified map interface.

## Parameters

  * `params` — map with `:type` (required), `:data`, `:conversation_id`, `:user_id`, `:store`

## Example

    Store.track(%{
      type: :user_exported_report,
      data: %{format: "csv"},
      conversation_id: conv.id,
      store: :my_store
    })
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
```

- [ ] **Step 4: Run integration tests**

Run: `mix test test/phoenix_ai/store/converse_integration_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/config.ex lib/phoenix_ai/store.ex test/phoenix_ai/store/converse_integration_test.exs
git commit -m "feat(api): add converse/3 pipeline, track/1, and config extension"
```

---

## Task 5: Final Verification

- [ ] **Step 1: Full test suite**

Run: `mix test`
Expected: All tests pass (353 + ~20 new)

- [ ] **Step 2: Credo**

Run: `mix credo --strict`
Expected: No new issues in Phase 8 files

- [ ] **Step 3: Clean compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 4: Commit any cleanup**

Only if needed.

---

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| INTG-01 (explicit API: track/1) | Task 4: Store.track/1 |
| INTG-02 (telemetry handler) | Task 2: TelemetryHandler |
| INTG-03 (handler guardian) | Task 3: HandlerGuardian with 30s polling |
| INTG-04 (normalized Usage) | Task 1: ConversePipeline uses Response.usage |
| INTG-06 (telemetry events) | Task 4: converse/3 span + existing spans |
| SC #1 (converse pipeline) | Task 1 + Task 4 |
| SC #2 (Store.track/1) | Task 4 |
| SC #3 (TelemetryHandler + Guardian) | Tasks 2 + 3 |
| SC #4 (Usage struct works) | Task 1: AI.chat returns Response with Usage |
| SC #5 (all ops emit telemetry) | Verified in Task 5 |
