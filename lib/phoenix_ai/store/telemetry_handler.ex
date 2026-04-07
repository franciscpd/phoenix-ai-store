defmodule PhoenixAI.Store.TelemetryHandler do
  @moduledoc """
  Plain module (not a GenServer) with handler functions for automatic
  PhoenixAI telemetry event capture.

  Listens to `[:phoenix_ai, :chat, :stop]` and `[:phoenix_ai, :tool_call, :stop]`
  events and asynchronously records cost and logs events through the Store.

  ## Usage

      # Attach (usually done by HandlerGuardian or in application start)
      TelemetryHandler.attach()

      # Detach
      TelemetryHandler.detach()

  ## Context Propagation

  The handler reads `Logger.metadata()[:phoenix_ai_store]` to get
  `%{conversation_id: ..., user_id: ...}` for attributing events to
  the correct conversation.
  """

  require Logger

  @handler_id :phoenix_ai_store_telemetry_handler
  @events [[:phoenix_ai, :chat, :stop], [:phoenix_ai, :tool_call, :stop]]

  @doc "Attaches the telemetry handler to PhoenixAI events."
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    case :telemetry.attach_many(
           @handler_id,
           @events,
           &__MODULE__.handle_event/4,
           opts
         ) do
      :ok -> :ok
      {:error, :already_exists} -> {:error, :already_exists}
    end
  end

  @doc "Detaches the telemetry handler."
  @spec detach() :: :ok
  def detach do
    :telemetry.detach(@handler_id)
    :ok
  rescue
    _ -> :ok
  end

  @doc "Returns the deterministic handler ID."
  @spec handler_id() :: atom()
  def handler_id, do: @handler_id

  @doc """
  Handles a telemetry event.

  For `:chat` stop events, asynchronously records cost and logs a
  `:response_received` event. For `:tool_call` stop events, logs
  a `:tool_called` event.

  All persistence is async via `Task.start/1`. Never crashes —
  all errors are caught and logged.
  """
  @spec handle_event([atom()], map(), map(), keyword()) :: :ok
  def handle_event([:phoenix_ai, :chat, :stop], measurements, metadata, opts) do
    context = get_store_context()

    if context do
      Task.start(fn ->
        try do
          handle_chat_stop(measurements, metadata, context, opts)
        rescue
          e -> Logger.warning("TelemetryHandler chat:stop failed: #{inspect(e)}")
        end
      end)
    end

    :ok
  end

  def handle_event([:phoenix_ai, :tool_call, :stop], _measurements, metadata, opts) do
    context = get_store_context()

    if context do
      Task.start(fn ->
        try do
          handle_tool_call_stop(metadata, context, opts)
        rescue
          e -> Logger.warning("TelemetryHandler tool_call:stop failed: #{inspect(e)}")
        end
      end)
    end

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _opts), do: :ok

  # -- Private --

  defp get_store_context do
    Logger.metadata()[:phoenix_ai_store]
  end

  defp handle_chat_stop(_measurements, metadata, context, _opts) do
    store_opts = [store: context[:store]]

    # Record cost if usage is available
    if metadata[:usage] && metadata[:status] == :ok do
      response = %PhoenixAI.Response{
        usage: metadata[:usage],
        provider: metadata[:provider],
        model: metadata[:model],
        content: nil
      }

      try do
        PhoenixAI.Store.record_cost(
          context[:conversation_id],
          response,
          Keyword.merge(store_opts, user_id: context[:user_id])
        )
      rescue
        _ -> :ok
      end
    end

    # Log event
    try do
      PhoenixAI.Store.log_event(
        %PhoenixAI.Store.EventLog.Event{
          type: :response_received,
          data: %{
            provider: metadata[:provider],
            model: metadata[:model]
          },
          conversation_id: context[:conversation_id],
          user_id: context[:user_id]
        },
        store_opts
      )
    rescue
      _ -> :ok
    end
  end

  defp handle_tool_call_stop(metadata, context, _opts) do
    PhoenixAI.Store.log_event(
      %PhoenixAI.Store.EventLog.Event{
        type: :tool_called,
        data: %{tool: metadata[:tool]},
        conversation_id: context[:conversation_id],
        user_id: context[:user_id]
      },
      store: context[:store]
    )
  rescue
    _ -> :ok
  end
end
