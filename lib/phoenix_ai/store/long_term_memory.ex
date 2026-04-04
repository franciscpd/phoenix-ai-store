defmodule PhoenixAI.Store.LongTermMemory do
  @moduledoc """
  Orchestrates long-term memory: fact CRUD, extraction, profile updates,
  and context injection.

  All functions accept a `:store` option to specify which store instance
  to use (default: `:phoenix_ai_store_default`).
  """

  alias PhoenixAI.Store.Instance
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}

  # -- Manual CRUD: Facts --

  @spec save_fact(Fact.t(), keyword()) :: {:ok, Fact.t()} | {:error, term()}
  def save_fact(%Fact{} = fact, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.save_fact(fact, adapter_opts)
  end

  @spec get_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def get_facts(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.get_facts(user_id, adapter_opts)
  end

  @spec delete_fact(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_fact(user_id, key, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)
    adapter.delete_fact(user_id, key, adapter_opts)
  end

  # -- Manual CRUD: Profiles --

  @spec save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def save_profile(%Profile{} = profile, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.save_profile(profile, adapter_opts)
  end

  @spec get_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, :not_found | term()}
  def get_profile(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.load_profile(user_id, adapter_opts)
  end

  @spec delete_profile(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_profile(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    adapter.delete_profile(user_id, adapter_opts)
  end

  # -- Private --

  defp resolve_adapter(opts) do
    store = Keyword.get(opts, :store, :phoenix_ai_store_default)
    config = Instance.get_config(store)
    adapter_opts = Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts}
  end

  defp check_fact_store!(adapter) do
    Code.ensure_loaded(adapter)

    unless function_exported?(adapter, :save_fact, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.FactStore. " <>
              "Long-term memory requires an adapter that supports fact storage."
    end
  end

  defp check_profile_store!(adapter) do
    Code.ensure_loaded(adapter)

    unless function_exported?(adapter, :save_profile, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.ProfileStore. " <>
              "Long-term memory requires an adapter that supports profile storage."
    end
  end
end
