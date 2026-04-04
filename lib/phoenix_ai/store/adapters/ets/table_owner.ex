defmodule PhoenixAI.Store.Adapters.ETS.TableOwner do
  @moduledoc """
  A GenServer that owns an ETS table for the in-memory adapter.

  The table is created on init and deleted on termination, ensuring
  proper lifecycle management of the ETS resource.
  """

  use GenServer

  # -- Client API --

  @doc "Starts the TableOwner GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc "Returns the ETS table reference owned by this server."
  @spec table(GenServer.server()) :: :ets.table()
  def table(server) do
    GenServer.call(server, :table)
  end

  # -- Server Callbacks --

  @impl true
  def init([]) do
    table =
      :ets.new(:phoenix_ai_store, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:table, _from, state) do
    {:reply, state.table, state}
  end

  @impl true
  def terminate(_reason, %{table: table}) do
    :ets.delete(table)
    :ok
  end
end
