defmodule PhoenixAI.Store.Adapter do
  @moduledoc """
  Behaviour for storage backends.

  The base behaviour defines conversation and message callbacks that every
  adapter must implement. Sub-behaviours (`FactStore`, `ProfileStore`) are
  optional — adapters implement them to support long-term memory.
  """

  alias PhoenixAI.Store.{Conversation, Message}

  @callback save_conversation(Conversation.t(), opts :: keyword()) ::
              {:ok, Conversation.t()} | {:error, term()}

  @callback load_conversation(id :: String.t(), opts :: keyword()) ::
              {:ok, Conversation.t()} | {:error, :not_found | term()}

  @callback list_conversations(filters :: keyword(), opts :: keyword()) ::
              {:ok, [Conversation.t()]} | {:error, term()}

  @callback delete_conversation(id :: String.t(), opts :: keyword()) ::
              :ok | {:error, :not_found | term()}

  @callback count_conversations(filters :: keyword(), opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @callback conversation_exists?(id :: String.t(), opts :: keyword()) ::
              {:ok, boolean()} | {:error, term()}

  @callback add_message(conversation_id :: String.t(), Message.t(), opts :: keyword()) ::
              {:ok, Message.t()} | {:error, term()}

  @callback get_messages(conversation_id :: String.t(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}

  # -- Sub-behaviours --

  defmodule FactStore do
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

  defmodule ProfileStore do
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

  defmodule CostStore do
    @moduledoc """
    Sub-behaviour for adapters that support cost record persistence.
    """

    alias PhoenixAI.Store.CostTracking.CostRecord

    @callback save_cost_record(CostRecord.t(), keyword()) ::
                {:ok, CostRecord.t()} | {:error, term()}

    @callback list_cost_records(filters :: keyword(), keyword()) ::
                {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}
                | {:error, term()}

    @callback count_cost_records(filters :: keyword(), keyword()) ::
                {:ok, non_neg_integer()}

    @callback sum_cost(filters :: keyword(), keyword()) ::
                {:ok, Decimal.t()} | {:error, term()}
  end

  defmodule EventStore do
    @moduledoc """
    Sub-behaviour for adapters that support the append-only event log.
    No update or delete callbacks — events are immutable once written.

    ## Audit trail preservation

    Events are intentionally NOT deleted when a conversation is deleted.
    The event log is an audit trail that persists beyond the lifecycle of
    individual conversations. This is by design — if a conversation is
    soft-deleted or hard-deleted, its associated events remain queryable
    for compliance, debugging, and cost attribution purposes.
    """

    alias PhoenixAI.Store.EventLog.Event

    @callback log_event(Event.t(), keyword()) ::
                {:ok, Event.t()} | {:error, term()}

    @callback list_events(filters :: keyword(), keyword()) ::
                {:ok, %{events: [Event.t()], next_cursor: String.t() | nil}}

    @callback count_events(filters :: keyword(), keyword()) ::
                {:ok, non_neg_integer()}
  end

  defmodule TokenUsage do
    @moduledoc """
    Sub-behaviour for adapters that support token usage aggregation.

    Used by the TokenBudget guardrail policy to efficiently query
    accumulated token counts without loading full message lists.
    """

    @callback sum_conversation_tokens(conversation_id :: String.t(), keyword()) ::
                {:ok, non_neg_integer()} | {:error, term()}

    @callback sum_user_tokens(user_id :: String.t(), keyword()) ::
                {:ok, non_neg_integer()} | {:error, term()}
  end
end
