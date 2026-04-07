defmodule PhoenixAI.Store.EventLog do
  @moduledoc """
  Orchestrator for the append-only event log.

  `log/3` builds an `%Event{}`, optionally redacts sensitive data,
  and persists through the adapter's `EventStore` sub-behaviour.

  ## Flow

  1. Resolve adapter from opts
  2. Check adapter supports `log_event/2`
  3. Build `%Event{}` with UUID v7, timestamps, and context
  4. Apply optional `redact_fn`
  5. Persist through adapter, wrapped in a telemetry span
  """

  alias PhoenixAI.Store.EventLog.Event

  @doc """
  Logs an event of the given `type` with `data` through the configured adapter.

  ## Options

    * `:adapter` — adapter module (required)
    * `:adapter_opts` — adapter options (required)
    * `:conversation_id` — conversation to associate the event with
    * `:user_id` — user to associate the event with
    * `:redact_fn` — optional `(Event.t() -> Event.t())` function applied before persistence
  """
  @spec log(atom(), map(), keyword()) :: {:ok, Event.t()} | {:error, term()}
  def log(type, data, opts) do
    with {:ok, adapter, adapter_opts} <- resolve_adapter(opts),
         :ok <- check_event_store_support(adapter) do
      event = build_event(type, data, opts)
      event = maybe_redact(event, opts)

      :telemetry.span([:phoenix_ai_store, :event, :log], %{type: type}, fn ->
        result = adapter.log_event(event, adapter_opts)
        {result, %{type: type}}
      end)
    end
  end

  @doc """
  Encodes an event into a cursor string for pagination.
  """
  @spec encode_cursor(Event.t()) :: String.t()
  def encode_cursor(%Event{inserted_at: ts, id: id}) do
    PhoenixAI.Store.Cursor.encode(ts, id)
  end

  @doc """
  Decodes a cursor string back into `{:ok, {DateTime.t(), id}}` or `{:error, :invalid_cursor}`.
  """
  @spec decode_cursor(String.t()) :: {:ok, {DateTime.t(), String.t()}} | {:error, :invalid_cursor}
  def decode_cursor(cursor) do
    PhoenixAI.Store.Cursor.decode(cursor)
  end

  # -- Private --

  defp resolve_adapter(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])
    {:ok, adapter, adapter_opts}
  end

  defp check_event_store_support(adapter) do
    if function_exported?(adapter, :log_event, 2) do
      :ok
    else
      {:error, :event_store_not_supported}
    end
  end

  defp build_event(type, data, opts) do
    %Event{
      id: Uniq.UUID.uuid7(),
      conversation_id: Keyword.get(opts, :conversation_id),
      user_id: Keyword.get(opts, :user_id),
      type: type,
      data: data,
      metadata: %{},
      inserted_at: DateTime.utc_now()
    }
  end

  defp maybe_redact(event, opts) do
    case Keyword.get(opts, :redact_fn) do
      fun when is_function(fun, 1) -> fun.(event)
      _ -> event
    end
  end
end
