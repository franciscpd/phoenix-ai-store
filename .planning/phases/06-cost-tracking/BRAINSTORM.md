# Phase 6: Cost Tracking — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Requirements:** COST-01, COST-02, COST-03, COST-04, COST-05, COST-06, COST-07, COST-08, GUARD-02

## Summary

Thin-layer cost tracking that records per-turn costs using Decimal arithmetic, configurable pricing tables, and a CostBudget guardrail. Follows the established adapter sub-behaviour pattern (like FactStore, TokenUsage). Dual recording: explicit API + telemetry handler.

## Architecture

```
Response → record_cost/3 → PricingProvider.price_for → CostRecord → CostStore.save
                                                                   → telemetry emit
```

No GenServer, no batching. 1 CostRecord per API call. Each write is synchronous through the adapter. CostBudget is an independent Policy that reads accumulated cost via `sum_cost/2`.

## Module Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/phoenix_ai/store/cost_tracking/cost_record.ex` | Create | CostRecord struct with Decimal fields |
| `lib/phoenix_ai/store/cost_tracking/pricing_provider.ex` | Create | PricingProvider behaviour |
| `lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex` | Create | Default impl reading from Application config |
| `lib/phoenix_ai/store/cost_tracking.ex` | Create | Orchestrator (record, validate, calculate) |
| `lib/phoenix_ai/store/guardrails/cost_budget.ex` | Create | CostBudget guardrail policy |
| `lib/phoenix_ai/store/schemas/cost_record.ex` | Create | Ecto schema (compiled only with Ecto) |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Add CostStore sub-behaviour |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement CostStore callbacks |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement CostStore callbacks |
| `lib/phoenix_ai/store/config.ex` | Modify | Add cost_tracking config section |
| `lib/phoenix_ai/store.ex` | Modify | Add record_cost/3, get_cost_records/2, sum_cost/2 |
| `mix.exs` | Modify | Add decimal ~> 2.0 as required dep |

**7 new files, 5 modified files.**

## CostRecord Struct

```elixir
defmodule PhoenixAI.Store.CostTracking.CostRecord do
  @type t :: %__MODULE__{
    id: String.t() | nil,
    conversation_id: String.t(),
    user_id: String.t() | nil,
    provider: atom(),
    model: String.t(),
    input_tokens: non_neg_integer(),
    output_tokens: non_neg_integer(),
    input_cost: Decimal.t(),
    output_cost: Decimal.t(),
    total_cost: Decimal.t(),
    metadata: map(),
    recorded_at: DateTime.t() | nil
  }

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :provider,
    :model,
    :recorded_at,
    input_tokens: 0,
    output_tokens: 0,
    input_cost: Decimal.new(0),
    output_cost: Decimal.new(0),
    total_cost: Decimal.new(0),
    metadata: %{}
  ]
end
```

## CostStore Sub-behaviour

```elixir
defmodule CostStore do
  @moduledoc """
  Sub-behaviour for adapters that support cost record persistence.
  """

  @callback save_cost_record(CostRecord.t(), keyword()) ::
              {:ok, CostRecord.t()} | {:error, term()}

  @callback get_cost_records(conversation_id :: String.t(), keyword()) ::
              {:ok, [CostRecord.t()]} | {:error, term()}

  @callback sum_cost(filters :: keyword(), keyword()) ::
              {:ok, Decimal.t()} | {:error, term()}
end
```

### sum_cost filters

Keyword list with optional keys:
- `:user_id` — filter by user
- `:conversation_id` — filter by conversation
- `:provider` — filter by provider atom
- `:model` — filter by model string
- `:after` — DateTime, records with recorded_at >= value
- `:before` — DateTime, records with recorded_at <= value

Returns `{:ok, Decimal.t()}` — the SUM of `total_cost` across matching records. Returns `{:ok, Decimal.new(0)}` when no records match.

### ETS Implementation

- Key format: `{{:cost_record, conversation_id, record_id}, %CostRecord{}}`
- `save_cost_record/2`: insert into ETS
- `get_cost_records/2`: match_object by conversation_id, sort by recorded_at
- `sum_cost/2`: match all cost records, filter by keyword criteria, reduce with `Decimal.add/2`

### Ecto Implementation

- Schema: `PhoenixAI.Store.Schemas.CostRecord` mapping to `phoenix_ai_store_cost_records` table
- `save_cost_record/2`: `repo.insert/1` (no upsert — cost records are append-only)
- `get_cost_records/2`: `SELECT * WHERE conversation_id = ? ORDER BY recorded_at`
- `sum_cost/2`: `SELECT COALESCE(SUM(total_cost), 0) WHERE <filters>` — single SQL query

### Ecto Migration

Table: `phoenix_ai_store_cost_records`

| Column | Type | Notes |
|--------|------|-------|
| `id` | `:binary_id` | PK, UUID v7 |
| `conversation_id` | `:binary_id` | FK to conversations, indexed |
| `user_id` | `:string` | Indexed |
| `provider` | `:string` | Stored as string, cast to atom on read |
| `model` | `:string` | |
| `input_tokens` | `:integer` | |
| `output_tokens` | `:integer` | |
| `input_cost` | `:decimal` | precision: 20, scale: 10 |
| `output_cost` | `:decimal` | precision: 20, scale: 10 |
| `total_cost` | `:decimal` | precision: 20, scale: 10 |
| `metadata` | `:map` | jsonb |
| `recorded_at` | `:utc_datetime_usec` | Indexed |

Indexes: `conversation_id`, `user_id`, `recorded_at`, `{user_id, recorded_at}` composite.

Generator: `mix phoenix_ai_store.gen.migration --cost` for existing installs.

## PricingProvider

### Behaviour

```elixir
defmodule PhoenixAI.Store.CostTracking.PricingProvider do
  @callback price_for(provider :: atom(), model :: String.t()) ::
              {:ok, {input_price :: Decimal.t(), output_price :: Decimal.t()}}
              | {:error, :unknown_model}
end
```

### Static Default Implementation

Reads from Application config:

```elixir
# In config/config.exs:
config :phoenix_ai_store, :pricing, %{
  {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
  {:openai, "gpt-4o-mini"} => {"0.00000015", "0.0000006"},
  {:anthropic, "claude-sonnet-4-5"} => {"0.000003", "0.000015"},
  {:anthropic, "claude-haiku-4-5"} => {"0.0000008", "0.000004"}
}
```

Values are strings parsed to Decimal at lookup time. When key not found: `{:error, :unknown_model}`.

### Custom Implementation Example

```elixir
defmodule MyApp.DbPricingProvider do
  @behaviour PhoenixAI.Store.CostTracking.PricingProvider

  @impl true
  def price_for(provider, model) do
    case MyApp.Repo.get_by(MyApp.Pricing, provider: provider, model: model) do
      %{input_price: ip, output_price: op} -> {:ok, {ip, op}}
      nil -> {:error, :unknown_model}
    end
  end
end
```

Configured via: `cost_tracking: [pricing_provider: MyApp.DbPricingProvider]`

## Cost Calculation & Recording

### Orchestrator: `PhoenixAI.Store.CostTracking`

```elixir
def record(conversation_id, %PhoenixAI.Response{} = response, opts) do
  with :ok <- validate_usage(response),
       {:ok, {input_price, output_price}} <- lookup_pricing(response, opts),
       cost_record <- build_record(conversation_id, response, input_price, output_price, opts),
       {adapter, adapter_opts} <- resolve_adapter(opts),
       :ok <- check_cost_store_support(adapter),
       {:ok, saved} <- adapter.save_cost_record(cost_record, adapter_opts) do
    emit_telemetry(saved)
    {:ok, saved}
  end
end
```

### Validation

- `validate_usage/1`: checks `response.usage` is `%PhoenixAI.Usage{}` (not raw map). Returns `:ok` or `{:error, :usage_not_normalized}`.
- `check_cost_store_support/1`: checks `function_exported?(adapter, :save_cost_record, 2)`. Returns `:ok` or `{:error, :cost_store_not_supported}`.

### Cost Formula

```elixir
input_cost  = Decimal.mult(Decimal.new(input_tokens), input_price)
output_cost = Decimal.mult(Decimal.new(output_tokens), output_price)
total_cost  = Decimal.add(input_cost, output_cost)
```

All arithmetic via Decimal. No Float anywhere in the cost path.

### Telemetry

Event: `[:phoenix_ai_store, :cost, :recorded]`

Measurements: `%{total_cost: Decimal.t()}`

Metadata: `%{conversation_id, user_id, provider, model, input_tokens, output_tokens, input_cost, output_cost}`

## CostBudget Guardrail

Mirrors TokenBudget exactly. Implements `PhoenixAI.Guardrails.Policy`.

### Options

- `:max` — maximum cost as string or Decimal (e.g., `"10.00"`)
- `:scope` — `:conversation` | `:user` | `:time_window`
- `:rate_limiter` — for time_window scope (same Hammer integration as TokenBudget)
- `:window_ms` — for time_window scope

### Flow

1. Extract adapter from `request.assigns`
2. Check adapter supports CostStore (`function_exported?`)
3. Validate scope requirements (conversation_id / user_id)
4. Query `adapter.sum_cost(filters, adapter_opts)` → accumulated Decimal
5. Compare with `Decimal.compare(accumulated, max)` — if `:gt` → halt with violation
6. Return `{:ok, request}` or `{:halt, %PolicyViolation{}}`

### Violation

```elixir
%PolicyViolation{
  policy: CostBudget,
  reason: "Cost budget exceeded: $12.50 / $10.00 (scope: user)",
  metadata: %{accumulated: Decimal.new("12.50"), max: Decimal.new("10.00"), scope: :user}
}
```

## Store Facade API

```elixir
# Record cost from a response
Store.record_cost(conversation_id, response, store: :my_store)
# → {:ok, %CostRecord{}} | {:error, :usage_not_normalized | :pricing_not_found | :cost_store_not_supported}

# Get cost records for a conversation
Store.get_cost_records(conversation_id, store: :my_store)
# → {:ok, [%CostRecord{}]}

# Aggregate cost with filters
Store.sum_cost([user_id: "x", provider: :openai], store: :my_store)
# → {:ok, Decimal.new("4.52")}
```

All three wrapped in telemetry spans (`[:phoenix_ai_store, :cost, :*]`).

## Config Extension

```elixir
cost_tracking: [
  type: :keyword_list,
  default: [],
  keys: [
    enabled: [type: :boolean, default: false],
    pricing_provider: [
      type: :atom,
      default: PhoenixAI.Store.CostTracking.PricingProvider.Static
    ]
  ]
]
```

Pricing map stays in `Application.get_env(:phoenix_ai_store, :pricing)` — separate from NimbleOptions since `{atom, string}` tuple keys don't validate well.

## Requirements Coverage

| Requirement | Covered By |
|-------------|------------|
| COST-01 (pricing tables) | PricingProvider behaviour + Static default |
| COST-02 (per-conversation cost) | record_cost/3 + CostRecord linked to conversation |
| COST-03 (per-user cost) | sum_cost with user_id filter |
| COST-04 (telemetry events) | [:phoenix_ai_store, :cost, :recorded] |
| COST-05 (query by time/provider/model/user/conversation) | sum_cost keyword filters |
| COST-06 (Ecto schema) | Schemas.CostRecord + migration generator |
| COST-07 (guardrail integration) | CostBudget policy in check_guardrails pipeline |
| COST-08 (Decimal arithmetic) | Decimal required dep, all cost math via Decimal |
| GUARD-02 (cost budget) | CostBudget with conversation/user/time_window scopes |
