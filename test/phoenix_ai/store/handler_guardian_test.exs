defmodule PhoenixAI.Store.HandlerGuardianTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Store.{HandlerGuardian, TelemetryHandler}

  setup do
    # Clean up any existing handler and guardian
    TelemetryHandler.detach()

    on_exit(fn ->
      TelemetryHandler.detach()
    end)

    :ok
  end

  describe "start_link/1" do
    test "attaches telemetry handler on init" do
      name = :"guardian_test_#{System.unique_integer([:positive])}"

      {:ok, pid} = HandlerGuardian.start_link(name: name, interval: 60_000)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end)

      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      assert Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)
    end
  end

  describe "reattachment" do
    test "reattaches handler after manual detach" do
      name = :"guardian_reattach_#{System.unique_integer([:positive])}"

      {:ok, pid} = HandlerGuardian.start_link(name: name, interval: 100)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end)

      # Verify handler is attached
      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      assert Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)

      # Manually detach the handler
      TelemetryHandler.detach()

      # Verify it's gone
      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      refute Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)

      # Wait for guardian to notice and reattach (interval is 100ms)
      Process.sleep(200)

      # Verify handler is back
      handlers = :telemetry.list_handlers([:phoenix_ai, :chat, :stop])

      assert Enum.any?(handlers, fn handler ->
               handler.id == TelemetryHandler.handler_id()
             end)
    end
  end
end
