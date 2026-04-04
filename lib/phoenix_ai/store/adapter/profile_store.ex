defmodule PhoenixAI.Store.Adapter.ProfileStore do
  @moduledoc """
  Sub-behaviour for adapters that support long-term memory profile storage.

  Adapters implementing this behaviour can store, retrieve, and delete
  per-user profile summaries. `save_profile/2` uses upsert semantics —
  writing for the same `user_id` overwrites the previous profile.
  """

  alias PhoenixAI.Store.LongTermMemory.Profile

  @callback save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  @callback load_profile(user_id :: String.t(), keyword()) ::
              {:ok, Profile.t()} | {:error, :not_found | term()}
  @callback delete_profile(user_id :: String.t(), keyword()) :: :ok | {:error, term()}
end
