defmodule PhoenixAI.Store.Adapter.FactStore do
  @moduledoc """
  Sub-behaviour for adapters that support long-term memory fact storage.

  Adapters implementing this behaviour can store, retrieve, and delete
  per-user key-value facts. `save_fact/2` uses upsert semantics —
  writing to the same `{user_id, key}` overwrites the previous value.
  """

  alias PhoenixAI.Store.LongTermMemory.Fact

  @callback save_fact(Fact.t(), keyword()) :: {:ok, Fact.t()} | {:error, term()}
  @callback get_facts(user_id :: String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  @callback delete_fact(user_id :: String.t(), key :: String.t(), keyword()) ::
              :ok | {:error, term()}
  @callback count_facts(user_id :: String.t(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
