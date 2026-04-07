defmodule PhoenixAI.Store.Instance do
  @moduledoc """
  GenServer that holds per-store state: adapter module, resolved config,
  and adapter-specific opts.

  The Instance name is the store name itself (e.g., `:my_store`).
  """

  use GenServer

  alias PhoenixAI.Store.Adapters.ETS, as: ETSAdapter
  alias PhoenixAI.Store.Adapters.ETS.TableOwner
  alias PhoenixAI.Store.Config

  # -- Client API --

  @doc "Starts the Instance GenServer with the given config opts."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the resolved config keyword list."
  @spec get_config(GenServer.server()) :: keyword()
  def get_config(server) do
    GenServer.call(server, :get_config)
  end

  @doc "Returns opts to pass to adapter callbacks."
  @spec get_adapter_opts(GenServer.server()) :: keyword()
  def get_adapter_opts(server) do
    GenServer.call(server, :get_adapter_opts)
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    # Skip validation if already resolved by PhoenixAI.Store.start_link/1
    config =
      if Keyword.has_key?(opts, :prefix),
        do: opts,
        else: Config.resolve(opts)

    adapter_opts = build_adapter_opts(config)
    {:ok, %{config: config, adapter_opts: adapter_opts}}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:get_adapter_opts, _from, state) do
    {:reply, state.adapter_opts, state}
  end

  # -- Private --

  defp build_adapter_opts(config) do
    case config[:adapter] do
      ETSAdapter ->
        table_owner_name = :"#{config[:name]}_table_owner"
        [table: TableOwner.table(table_owner_name)]

      _other ->
        Keyword.take(config, [:repo, :prefix, :soft_delete])
    end
  end
end
