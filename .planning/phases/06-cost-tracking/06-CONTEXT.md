# Phase 6: Cost Tracking - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Track and report token consumption and dollar costs per conversation and per user, using configurable pricing tables and Decimal arithmetic. Includes a CostBudget guardrail that blocks calls before they exceed cost limits. Cost records are persisted via the adapter sub-behaviour pattern. Telemetry events enable real-time cost monitoring.

Note: COST-V2-01 (cost forecasting) and COST-V2-02 (auto-update pricing) are out of scope — future version.

</domain>

<decisions>
## Implementation Decisions

### Decimal Dependency
- **D-01:** Decimal is a **required** (not optional) dependency in mix.exs. COST-08 mandates Decimal arithmetic for all cost calculations. Decimal is lightweight (zero transitive deps) and already pulled transitively via Ecto — making it explicit ensures ETS adapter users also have it.

### CostRecord Struct & Storage
- **D-02:** New `PhoenixAI.Store.Adapter.CostStore` sub-behaviour following the established pattern (FactStore, ProfileStore, TokenUsage). Dedicated `cost_records` table/ETS namespace.
- **D-03:** `CostRecord` struct fields: `id`, `conversation_id`, `user_id`, `provider` (atom), `model` (string), `input_tokens` (integer), `output_tokens` (integer), `input_cost` (Decimal), `output_cost` (Decimal), `total_cost` (Decimal), `metadata` (map), `recorded_at` (DateTime).
- **D-04:** CostStore callbacks: `save_cost_record/2`, `get_cost_records/2` (by conversation), `sum_cost/2` (aggregation with filters: user_id, conversation_id, provider, model, time range). The `sum_cost/2` callback returns `{:ok, Decimal.t()}`.

### Pricing Table Configuration
- **D-05:** Dual approach — static config via NimbleOptions (covers 90% of users) + `PricingProvider` behaviour for custom lookup (enterprise/dynamic pricing).
- **D-06:** Static config structure in NimbleOptions: `pricing: [{provider, model} => {input_price_per_token, output_price_per_token}]` where prices are strings parseable by `Decimal.new/1` (e.g., `"0.000003"`). NimbleOptions uses `{:custom, mod, fun, args}` to validate Decimal strings.
- **D-07:** `PricingProvider` behaviour has a single callback: `price_for(provider, model) :: {:ok, {input_price :: Decimal.t(), output_price :: Decimal.t()}} | {:error, :unknown_model}`. Default implementation reads from static config. Developer can replace with DB-backed or API-backed provider.
- **D-08:** When pricing lookup fails (unknown model), `record_cost/3` returns `{:error, :pricing_not_found}` — never silently records $0.

### Cost Calculation
- **D-09:** Cost formula: `input_cost = input_tokens * input_price_per_token`, `output_cost = output_tokens * output_price_per_token`, `total_cost = input_cost + output_cost`. All arithmetic via `Decimal.mult/2` and `Decimal.add/2`.
- **D-10:** When PhoenixAI passes a raw (non-normalized) usage map (not a `%Usage{}` struct), `record_cost/3` returns `{:error, :usage_not_normalized}` — per success criteria #6.

### CostBudget Guardrail (GUARD-02)
- **D-11:** `PhoenixAI.Store.Guardrails.CostBudget` follows the **exact same pattern** as TokenBudget — implements `PhoenixAI.Guardrails.Policy`, reads from adapter via `request.assigns`, supports scopes `:conversation`, `:user`, `:time_window`.
- **D-12:** CostBudget uses `CostStore.sum_cost/2` to query accumulated cost. Max is a Decimal value (e.g., `Decimal.new("10.00")` for $10 budget).

### Usage Integration
- **D-13:** PhoenixAI v0.3.1 `Response` struct now has `provider` atom field. Cost tracking reads `response.provider` + `response.model` + `response.usage` — no extra config needed from the developer.
- **D-14:** Dual recording approach — **explicit API** (`Store.record_cost/3`) as primary + **TelemetryHandler** capturing `[:phoenix_ai, :chat, :stop]` as automatic alternative. Same pattern as LTM `extract_facts` (manual + trigger modes).

### Telemetry
- **D-15:** Emit `[:phoenix_ai_store, :cost, :recorded]` after each cost record is written. Metadata includes: `conversation_id`, `user_id`, `provider`, `model`, `total_cost`, `input_tokens`, `output_tokens`.

### Claude's Discretion
- Exact NimbleOptions schema structure for pricing config
- CostStore Ecto migration column types (precision/scale for Decimal)
- ETS key format for cost records
- Query filter API design for `sum_cost/2` (keyword list vs struct)
- TelemetryHandler implementation details

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (Phases 1, 3, 4, 5)
- `lib/phoenix_ai/store/adapter.ex` — Adapter behaviour + sub-behaviours pattern (FactStore, ProfileStore, TokenUsage)
- `lib/phoenix_ai/store/adapters/ets.ex` — ETS adapter (all sub-behaviours implemented)
- `lib/phoenix_ai/store/adapters/ecto.ex` — Ecto adapter (all sub-behaviours implemented)
- `lib/phoenix_ai/store/guardrails/token_budget.ex` — TokenBudget policy (model for CostBudget)
- `lib/phoenix_ai/store/guardrails/token_budget/rate_limiter.ex` — Hammer integration for time-window
- `lib/phoenix_ai/store/config.ex` — NimbleOptions config schema
- `lib/phoenix_ai/store.ex` — Public API facade (check_guardrails/3, record patterns)
- `lib/phoenix_ai/store/long_term_memory.ex` — LTM orchestrator (model for dual recording: explicit + trigger)
- `lib/phoenix_ai/store/message.ex` — Message struct with token_count
- `test/support/token_usage_contract_test.ex` — Contract test pattern for sub-behaviours

### PhoenixAI Peer Dependency (v0.3.1)
- `deps/phoenix_ai/lib/phoenix_ai/response.ex` — Response struct with provider, model, usage fields
- `deps/phoenix_ai/lib/phoenix_ai/usage.ex` — Usage struct with input_tokens, output_tokens, total_tokens

### Planning
- `.planning/REQUIREMENTS.md` — COST-01 through COST-08, GUARD-02
- `.planning/phases/05-guardrails/05-CONTEXT.md` — Phase 5 decisions (TokenBudget, CostBudget deferred here)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TokenBudget` policy — direct template for CostBudget (same scopes, same adapter injection pattern)
- `TokenUsage` sub-behaviour — direct template for CostStore (sum callbacks, contract tests)
- `TokenUsageContractTest` — template for CostStore contract tests
- `LongTermMemory` orchestrator — template for dual recording (explicit API + trigger mode)
- `Config` NimbleOptions schema — extend with pricing and cost_tracking sections

### Established Patterns
- Sub-behaviours checked via `function_exported?/3` for optional adapter capabilities
- `{:ok, result} | {:error, term()}` return types everywhere
- Telemetry spans for all public operations
- Contract tests via `__using__` macro shared across ETS and Ecto adapters
- Ecto adapter wrapped in `if Code.ensure_loaded?(Ecto)`
- Dynamic table names via `prefix` option

### Integration Points
- `Store.record_cost/3` — new facade function (explicit recording)
- `Store.get_cost_records/2` — query cost records for a conversation
- `Store.sum_cost/2` — aggregate cost with filters
- `Store.check_guardrails/3` — CostBudget plugs into existing guardrails pipeline
- Ecto migration generator — needs `cost_records` table added

</code_context>

<specifics>
## Specific Ideas

- Pricing config should accept string values for Decimal (e.g., `"0.000003"`) since Elixir config files don't have Decimal literals
- The migration generator (`mix phoenix_ai_store.gen.migration`) should gain a `--cost` flag for existing installs, similar to `--ltm` flag from Phase 4
- CostBudget max should accept both Decimal and string (converted to Decimal at validation time)
- `sum_cost/2` filters: `[user_id: "x", provider: :openai, model: "gpt-4o", after: ~U[...], before: ~U[...]]`

</specifics>

<deferred>
## Deferred Ideas

- **COST-V2-01**: Cost forecasting and trend analysis — future version
- **COST-V2-02**: Provider-specific pricing auto-update from API — future version
- Cache-aware pricing (discount for cache_read_tokens) — could be added via PricingProvider behaviour but not in v1

</deferred>

---

*Phase: 06-cost-tracking*
*Context gathered: 2026-04-05*
