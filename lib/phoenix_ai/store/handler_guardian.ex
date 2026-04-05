defmodule PhoenixAI.Store.HandlerGuardian do
  @moduledoc """
  Supervised GenServer that ensures the telemetry handler stays attached.

  On init, attaches `TelemetryHandler`. Periodically checks that the handler
  is still registered with `:telemetry` and reattaches if missing.

  ## Options

    * `:name` — GenServer name (required)
    * `:handler_opts` — options passed to `TelemetryHandler.attach/1` (default: `[]`)
    * `:interval` — check interval in ms (default: `30_000`)

  ## Usage

      # As part of a supervision tree:
      children = [
        {HandlerGuardian, name: :my_guardian, interval: 30_000}
      ]
  """

  use GenServer

  alias PhoenixAI.Store.TelemetryHandler

  require Logger

  @default_interval 30_000

  @doc "Starts the HandlerGuardian GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    handler_opts = Keyword.get(opts, :handler_opts, [])
    interval = Keyword.get(opts, :interval, @default_interval)

    # Attach handler (idempotent — handles :already_exists gracefully)
    case TelemetryHandler.attach(handler_opts) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

    schedule_check(interval)

    {:ok, %{handler_opts: handler_opts, interval: interval}}
  end

  @impl true
  def handle_info(:check_handlers, state) do
    ensure_handler_attached(state.handler_opts)
    schedule_check(state.interval)
    {:noreply, state}
  end

  # -- Private --

  defp ensure_handler_attached(handler_opts) do
    handler_id = TelemetryHandler.handler_id()
    handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

    handler_present =
      Enum.any?(handlers, fn handler -> handler.id == handler_id end)

    unless handler_present do
      Logger.info("HandlerGuardian: reattaching telemetry handler")

      case TelemetryHandler.attach(handler_opts) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_handlers, interval)
  end
end
