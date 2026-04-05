# Phase 6: Cost Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-conversation and per-user cost tracking with Decimal arithmetic, configurable pricing tables, and a CostBudget guardrail that blocks calls before they exceed cost limits.

**Architecture:** Thin-layer: Response → PricingProvider lookup → CostRecord built with Decimal math → saved via CostStore adapter sub-behaviour → telemetry emitted. CostBudget guardrail mirrors TokenBudget, querying accumulated cost via `sum_cost/2`. Pricing is pluggable via `PricingProvider` behaviour with a static-config default.

**Tech Stack:** Elixir, Decimal ~> 2.0, phoenix_ai ~> 0.3.1, Ecto (optional), NimbleOptions, Telemetry

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `mix.exs` | Modify | Add decimal ~> 2.0 required dep |
| `lib/phoenix_ai/store/cost_tracking/cost_record.ex` | Create | CostRecord struct |
| `lib/phoenix_ai/store/adapter.ex` | Modify | Add CostStore sub-behaviour |
| `test/support/cost_store_contract_test.ex` | Create | Shared contract tests |
| `lib/phoenix_ai/store/adapters/ets.ex` | Modify | Implement CostStore |
| `lib/phoenix_ai/store/schemas/cost_record.ex` | Create | Ecto schema |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Modify | Implement CostStore |
| `priv/templates/cost_migration.exs.eex` | Create | Migration template |
| `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` | Modify | Add --cost flag |
| `lib/phoenix_ai/store/cost_tracking/pricing_provider.ex` | Create | PricingProvider behaviour |
| `lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex` | Create | Default static impl |
| `lib/phoenix_ai/store/cost_tracking.ex` | Create | Orchestrator (record/3) |
| `lib/phoenix_ai/store/guardrails/cost_budget.ex` | Create | CostBudget policy |
| `lib/phoenix_ai/store/config.ex` | Modify | Add cost_tracking section |
| `lib/phoenix_ai/store.ex` | Modify | Add record_cost/3, get_cost_records/2, sum_cost/2 |

---

## Task 1: Add Decimal Dependency

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Add decimal to deps**

In `mix.exs`, add after the `{:telemetry, ...}` line:

```elixir
{:decimal, "~> 2.0"},
```

- [ ] **Step 2: Fetch and compile**

Run: `mix deps.get && mix compile`
Expected: Clean compilation

- [ ] **Step 3: Verify tests pass**

Run: `mix test`
Expected: 244 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore(deps): add decimal ~> 2.0 as required dep for cost tracking"
```

---

## Task 2: CostRecord Struct

**Files:**
- Create: `lib/phoenix_ai/store/cost_tracking/cost_record.ex`

- [ ] **Step 1: Create the CostRecord struct**

```elixir
defmodule PhoenixAI.Store.CostTracking.CostRecord do
  @moduledoc """
  A cost record linked to a conversation turn.

  Records the token usage and computed cost for a single AI provider
  call, using `Decimal` for all monetary values.
  """

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

- [ ] **Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean compilation

- [ ] **Step 3: Commit**

```bash
git add lib/phoenix_ai/store/cost_tracking/cost_record.ex
git commit -m "feat(cost): add CostRecord struct with Decimal fields"
```

---

## Task 3: CostStore Sub-behaviour + Contract Tests

**Files:**
- Modify: `lib/phoenix_ai/store/adapter.ex`
- Create: `test/support/cost_store_contract_test.ex`

- [ ] **Step 1: Write contract tests**

Create `test/support/cost_store_contract_test.ex`:

```elixir
defmodule PhoenixAI.Store.CostStoreContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.CostStore`.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.{Conversation, Message}
      alias PhoenixAI.Store.CostTracking.CostRecord

      @adapter unquote(macro_opts[:adapter])

      defp build_cost_record(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          conversation_id: Uniq.UUID.uuid7(),
          user_id: "cost_user",
          provider: :openai,
          model: "gpt-4o",
          input_tokens: 100,
          output_tokens: 50,
          input_cost: Decimal.new("0.00025"),
          output_cost: Decimal.new("0.0005"),
          total_cost: Decimal.new("0.00075"),
          metadata: %{},
          recorded_at: DateTime.utc_now()
        }

        struct(CostRecord, Map.merge(defaults, attrs))
      end

      describe "CostStore: save_cost_record/2" do
        test "saves and returns a cost record", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          record = build_cost_record(%{conversation_id: conv.id})
          assert {:ok, %CostRecord{} = saved} = @adapter.save_cost_record(record, opts)
          assert saved.conversation_id == conv.id
          assert saved.provider == :openai
          assert Decimal.equal?(saved.total_cost, Decimal.new("0.00075"))
        end
      end

      describe "CostStore: get_cost_records/2" do
        test "returns records for a conversation ordered by recorded_at", %{opts: opts} do
          conv = build_conversation()
          {:ok, _} = @adapter.save_conversation(conv, opts)

          now = DateTime.utc_now()
          r1 = build_cost_record(%{conversation_id: conv.id, recorded_at: now, model: "gpt-4o"})
          r2 = build_cost_record(%{conversation_id: conv.id, recorded_at: DateTime.add(now, 1, :second), model: "gpt-4o-mini"})

          {:ok, _} = @adapter.save_cost_record(r1, opts)
          {:ok, _} = @adapter.save_cost_record(r2, opts)

          assert {:ok, records} = @adapter.get_cost_records(conv.id, opts)
          assert length(records) == 2
          assert hd(records).model == "gpt-4o"
          assert List.last(records).model == "gpt-4o-mini"
        end

        test "returns empty list for conversation with no records", %{opts: opts} do
          assert {:ok, []} = @adapter.get_cost_records("nonexistent", opts)
        end
      end

      describe "CostStore: sum_cost/2" do
        setup %{opts: opts} do
          conv1 = build_conversation(%{user_id: "sum_user"})
          conv2 = build_conversation(%{user_id: "sum_user"})
          conv3 = build_conversation(%{user_id: "other_user"})
          {:ok, _} = @adapter.save_conversation(conv1, opts)
          {:ok, _} = @adapter.save_conversation(conv2, opts)
          {:ok, _} = @adapter.save_conversation(conv3, opts)

          now = DateTime.utc_now()

          {:ok, _} = @adapter.save_cost_record(
            build_cost_record(%{conversation_id: conv1.id, user_id: "sum_user", provider: :openai, model: "gpt-4o", total_cost: Decimal.new("1.50"), recorded_at: now}),
            opts
          )
          {:ok, _} = @adapter.save_cost_record(
            build_cost_record(%{conversation_id: conv2.id, user_id: "sum_user", provider: :anthropic, model: "claude-sonnet-4-5", total_cost: Decimal.new("2.00"), recorded_at: DateTime.add(now, 1, :second)}),
            opts
          )
          {:ok, _} = @adapter.save_cost_record(
            build_cost_record(%{conversation_id: conv3.id, user_id: "other_user", provider: :openai, model: "gpt-4o", total_cost: Decimal.new("0.75"), recorded_at: DateTime.add(now, 2, :second)}),
            opts
          )

          {:ok, conv1_id: conv1.id, conv2_id: conv2.id, now: now}
        end

        test "sums all records when no filters", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([], opts)
          assert Decimal.equal?(total, Decimal.new("4.25"))
        end

        test "filters by user_id", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([user_id: "sum_user"], opts)
          assert Decimal.equal?(total, Decimal.new("3.50"))
        end

        test "filters by conversation_id", %{opts: opts, conv1_id: conv1_id} do
          {:ok, total} = @adapter.sum_cost([conversation_id: conv1_id], opts)
          assert Decimal.equal?(total, Decimal.new("1.50"))
        end

        test "filters by provider", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([provider: :openai], opts)
          assert Decimal.equal?(total, Decimal.new("2.25"))
        end

        test "filters by model", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([model: "gpt-4o"], opts)
          assert Decimal.equal?(total, Decimal.new("2.25"))
        end

        test "filters by time range", %{opts: opts, now: now} do
          {:ok, total} = @adapter.sum_cost([after: DateTime.add(now, 1, :second)], opts)
          assert Decimal.equal?(total, Decimal.new("2.75"))
        end

        test "returns zero when no records match", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([user_id: "nobody"], opts)
          assert Decimal.equal?(total, Decimal.new("0"))
        end

        test "combines multiple filters", %{opts: opts} do
          {:ok, total} = @adapter.sum_cost([user_id: "sum_user", provider: :openai], opts)
          assert Decimal.equal?(total, Decimal.new("1.50"))
        end
      end
    end
  end
end
```

- [ ] **Step 2: Add CostStore sub-behaviour to adapter.ex**

Add inside `lib/phoenix_ai/store/adapter.ex`, after the `TokenUsage` sub-behaviour:

```elixir
defmodule CostStore do
  @moduledoc """
  Sub-behaviour for adapters that support cost record persistence.

  Used by the cost tracking system to store, retrieve, and aggregate
  cost records linked to conversations.
  """

  alias PhoenixAI.Store.CostTracking.CostRecord

  @callback save_cost_record(CostRecord.t(), keyword()) ::
              {:ok, CostRecord.t()} | {:error, term()}

  @callback get_cost_records(conversation_id :: String.t(), keyword()) ::
              {:ok, [CostRecord.t()]} | {:error, term()}

  @callback sum_cost(filters :: keyword(), keyword()) ::
              {:ok, Decimal.t()} | {:error, term()}
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile`
Expected: Clean compilation

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/adapter.ex test/support/cost_store_contract_test.ex
git commit -m "feat(cost): add CostStore sub-behaviour + contract tests"
```

---

## Task 4: ETS Adapter — CostStore Implementation

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex`
- Modify: `test/phoenix_ai/store/adapters/ets_test.exs`

- [ ] **Step 1: Wire contract tests into ETS test**

Add to `test/phoenix_ai/store/adapters/ets_test.exs`:

```elixir
use PhoenixAI.Store.CostStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep "CostStore"`
Expected: FAIL — callbacks not implemented

- [ ] **Step 3: Implement CostStore in ETS adapter**

Add `@behaviour PhoenixAI.Store.Adapter.CostStore` at the top with other behaviours.

Add after the TokenUsage callbacks:

```elixir
# -- CostStore callbacks --

@impl PhoenixAI.Store.Adapter.CostStore
def save_cost_record(%CostRecord{} = record, opts) do
  table = Keyword.fetch!(opts, :table)

  record = %{
    record
    | id: record.id || Uniq.UUID.uuid7(),
      recorded_at: record.recorded_at || DateTime.utc_now()
  }

  :ets.insert(table, {{:cost_record, record.conversation_id, record.id}, record})
  {:ok, record}
end

@impl PhoenixAI.Store.Adapter.CostStore
def get_cost_records(conversation_id, opts) do
  table = Keyword.fetch!(opts, :table)

  records =
    :ets.match_object(table, {{:cost_record, conversation_id, :_}, :_})
    |> Enum.map(fn {_key, record} -> record end)
    |> Enum.sort_by(& &1.recorded_at, {:asc, DateTime})

  {:ok, records}
end

@impl PhoenixAI.Store.Adapter.CostStore
def sum_cost(filters, opts) do
  table = Keyword.fetch!(opts, :table)

  total =
    :ets.match_object(table, {{:cost_record, :_, :_}, :_})
    |> Enum.map(fn {_key, record} -> record end)
    |> filter_cost_records(filters)
    |> Enum.reduce(Decimal.new(0), fn record, acc -> Decimal.add(acc, record.total_cost) end)

  {:ok, total}
end

defp filter_cost_records(records, []), do: records

defp filter_cost_records(records, [{:user_id, user_id} | rest]) do
  records |> Enum.filter(&(&1.user_id == user_id)) |> filter_cost_records(rest)
end

defp filter_cost_records(records, [{:conversation_id, conv_id} | rest]) do
  records |> Enum.filter(&(&1.conversation_id == conv_id)) |> filter_cost_records(rest)
end

defp filter_cost_records(records, [{:provider, provider} | rest]) do
  records |> Enum.filter(&(&1.provider == provider)) |> filter_cost_records(rest)
end

defp filter_cost_records(records, [{:model, model} | rest]) do
  records |> Enum.filter(&(&1.model == model)) |> filter_cost_records(rest)
end

defp filter_cost_records(records, [{:after, dt} | rest]) do
  records
  |> Enum.filter(&(DateTime.compare(&1.recorded_at, dt) in [:gt, :eq]))
  |> filter_cost_records(rest)
end

defp filter_cost_records(records, [{:before, dt} | rest]) do
  records
  |> Enum.filter(&(DateTime.compare(&1.recorded_at, dt) in [:lt, :eq]))
  |> filter_cost_records(rest)
end

defp filter_cost_records(records, [_ | rest]), do: filter_cost_records(records, rest)
```

Add the alias at the top of the module:

```elixir
alias PhoenixAI.Store.CostTracking.CostRecord
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs --trace 2>&1 | grep -E "(CostStore|passed|failed)"`
Expected: All CostStore tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex test/phoenix_ai/store/adapters/ets_test.exs
git commit -m "feat(cost): implement CostStore in ETS adapter"
```

---

## Task 5: Ecto Schema + Adapter + Migration

**Files:**
- Create: `lib/phoenix_ai/store/schemas/cost_record.ex`
- Create: `priv/templates/cost_migration.exs.eex`
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex`
- Modify: `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`
- Modify: `test/phoenix_ai/store/adapters/ecto_test.exs`

- [ ] **Step 1: Create Ecto schema**

Create `lib/phoenix_ai/store/schemas/cost_record.ex`:

```elixir
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.CostRecord do
    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.CostTracking.CostRecord, as: StoreCostRecord

    @primary_key {:id, :binary_id, autogenerate: false}

    schema "phoenix_ai_store_cost_records" do
      field :conversation_id, :binary_id
      field :user_id, :string
      field :provider, :string
      field :model, :string
      field :input_tokens, :integer
      field :output_tokens, :integer
      field :input_cost, :decimal
      field :output_cost, :decimal
      field :total_cost, :decimal
      field :metadata, :map, default: %{}
      field :recorded_at, :utc_datetime_usec
    end

    @cast_fields ~w(id conversation_id user_id provider model input_tokens output_tokens input_cost output_cost total_cost metadata recorded_at)a
    @required_fields ~w(conversation_id provider model input_tokens output_tokens input_cost output_cost total_cost recorded_at)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreCostRecord{
        id: schema.id,
        conversation_id: schema.conversation_id,
        user_id: schema.user_id,
        provider: safe_to_atom(schema.provider),
        model: schema.model,
        input_tokens: schema.input_tokens,
        output_tokens: schema.output_tokens,
        input_cost: schema.input_cost,
        output_cost: schema.output_cost,
        total_cost: schema.total_cost,
        metadata: schema.metadata || %{},
        recorded_at: schema.recorded_at
      }
    end

    def from_store_struct(%StoreCostRecord{} = record) do
      %{
        id: record.id,
        conversation_id: record.conversation_id,
        user_id: record.user_id,
        provider: to_string(record.provider),
        model: record.model,
        input_tokens: record.input_tokens,
        output_tokens: record.output_tokens,
        input_cost: record.input_cost,
        output_cost: record.output_cost,
        total_cost: record.total_cost,
        metadata: record.metadata,
        recorded_at: record.recorded_at
      }
    end

    defp safe_to_atom(nil), do: nil
    defp safe_to_atom(str) when is_binary(str), do: String.to_existing_atom(str)
    defp safe_to_atom(atom) when is_atom(atom), do: atom
  end
end
```

- [ ] **Step 2: Create migration template**

Create `priv/templates/cost_migration.exs.eex`:

```elixir
defmodule <%= @repo_module %>.Migrations.Add<%= @migration_module %>CostTables do
  use Ecto.Migration

  def change do
    create table(:<%= @prefix %>cost_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:<%= @prefix %>conversations, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :string
      add :provider, :string, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :input_cost, :decimal, precision: 20, scale: 10, null: false
      add :output_cost, :decimal, precision: 20, scale: 10, null: false
      add :total_cost, :decimal, precision: 20, scale: 10, null: false
      add :metadata, :map, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false
    end

    create index(:<%= @prefix %>cost_records, [:conversation_id])
    create index(:<%= @prefix %>cost_records, [:user_id])
    create index(:<%= @prefix %>cost_records, [:recorded_at])
    create index(:<%= @prefix %>cost_records, [:user_id, :recorded_at])
  end
end
```

- [ ] **Step 3: Add --cost flag to migration generator**

In `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`:

Add `cost: :boolean` to the OptionParser strict list.

Add `cost_only = Keyword.get(opts, :cost, false)` after `ltm_only`.

Add a new clause in the `if` chain:

```elixir
cond do
  ltm_only -> generate_ltm_migration(prefix, slug, migrations_path)
  cost_only -> generate_cost_migration(prefix, slug, migrations_path)
  true -> # existing logic for full migration
    ...
end
```

Add `generate_cost_migration/3`:

```elixir
defp generate_cost_migration(prefix, slug, migrations_path) do
  existing =
    Path.wildcard(Path.join(migrations_path, "*_add_#{slug}_cost_tables.exs"))

  if existing != [] do
    Mix.shell().info("Cost migration already exists: #{hd(existing)}")
    :ok
  else
    template_path = find_cost_template()
    timestamp = generate_timestamp()
    migration_module = module_from_prefix(prefix)
    repo_module = detect_repo_module()

    assigns = [prefix: prefix, migration_module: migration_module, repo_module: repo_module]
    content = EEx.eval_file(template_path, assigns: assigns)

    filename = "#{timestamp}_add_#{slug}_cost_tables.exs"
    filepath = Path.join(migrations_path, filename)

    Mix.Generator.create_file(filepath, content)
  end
end

defp find_cost_template do
  case Application.app_dir(:phoenix_ai_store, "priv/templates/cost_migration.exs.eex") do
    path when is_binary(path) ->
      if File.exists?(path), do: path, else: fallback_cost_template_path()
  end
rescue
  _ -> fallback_cost_template_path()
end

defp fallback_cost_template_path do
  Path.join([File.cwd!(), "priv", "templates", "cost_migration.exs.eex"])
end
```

Update `@moduledoc` to include `--cost` option.

- [ ] **Step 4: Generate and run the migration for tests**

Run: `mix phoenix_ai_store.gen.migration --cost`
Then: `mix ecto.migrate`

- [ ] **Step 5: Implement CostStore in Ecto adapter**

Add `@behaviour PhoenixAI.Store.Adapter.CostStore` at the top.

Add alias: `alias PhoenixAI.Store.Schemas.CostRecord, as: CostRecordSchema`
Add alias: `alias PhoenixAI.Store.CostTracking.CostRecord`

Add after the TokenUsage callbacks:

```elixir
# -- CostStore --

@impl PhoenixAI.Store.Adapter.CostStore
def save_cost_record(%CostRecord{} = record, opts) do
  repo = Keyword.fetch!(opts, :repo)
  attrs = CostRecordSchema.from_store_struct(record)

  %CostRecordSchema{}
  |> Ecto.put_meta(source: cost_record_table_name(opts))
  |> CostRecordSchema.changeset(attrs)
  |> repo.insert()
  |> handle_cost_record_result()
end

@impl PhoenixAI.Store.Adapter.CostStore
def get_cost_records(conversation_id, opts) do
  repo = Keyword.fetch!(opts, :repo)

  records =
    from(cr in cost_record_source(opts),
      where: cr.conversation_id == ^conversation_id,
      order_by: [asc: cr.recorded_at]
    )
    |> repo.all()
    |> Enum.map(&CostRecordSchema.to_store_struct/1)

  {:ok, records}
end

@impl PhoenixAI.Store.Adapter.CostStore
def sum_cost(filters, opts) do
  repo = Keyword.fetch!(opts, :repo)

  query =
    from(cr in cost_record_source(opts),
      select: coalesce(sum(cr.total_cost), 0)
    )
    |> apply_cost_filters(filters)

  {:ok, repo.one(query)}
end

defp apply_cost_filters(query, []), do: query

defp apply_cost_filters(query, [{:user_id, user_id} | rest]) do
  query |> where([cr], cr.user_id == ^user_id) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [{:conversation_id, conv_id} | rest]) do
  query |> where([cr], cr.conversation_id == ^conv_id) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [{:provider, provider} | rest]) do
  query |> where([cr], cr.provider == ^to_string(provider)) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [{:model, model} | rest]) do
  query |> where([cr], cr.model == ^model) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [{:after, dt} | rest]) do
  query |> where([cr], cr.recorded_at >= ^dt) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [{:before, dt} | rest]) do
  query |> where([cr], cr.recorded_at <= ^dt) |> apply_cost_filters(rest)
end

defp apply_cost_filters(query, [_ | rest]), do: apply_cost_filters(query, rest)

defp cost_record_source(opts), do: {cost_record_table_name(opts), CostRecordSchema}
defp cost_record_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "cost_records"

defp handle_cost_record_result({:ok, schema}), do: {:ok, CostRecordSchema.to_store_struct(schema)}
defp handle_cost_record_result({:error, changeset}), do: {:error, changeset}
```

- [ ] **Step 6: Wire contract tests into Ecto test**

Add to `test/phoenix_ai/store/adapters/ecto_test.exs`:

```elixir
use PhoenixAI.Store.CostStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
```

- [ ] **Step 7: Run all tests**

Run: `mix test`
Expected: All tests pass (244 + ~10 new contract tests per adapter)

- [ ] **Step 8: Commit**

```bash
git add lib/phoenix_ai/store/schemas/cost_record.ex lib/phoenix_ai/store/adapters/ecto.ex lib/phoenix_ai/store/adapters/ets.ex priv/templates/cost_migration.exs.eex lib/mix/tasks/phoenix_ai_store.gen.migration.ex test/phoenix_ai/store/adapters/ets_test.exs test/phoenix_ai/store/adapters/ecto_test.exs
git commit -m "feat(cost): implement CostStore in ETS and Ecto adapters"
```

---

## Task 6: PricingProvider Behaviour + Static Default

**Files:**
- Create: `lib/phoenix_ai/store/cost_tracking/pricing_provider.ex`
- Create: `lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex`
- Create: `test/phoenix_ai/store/cost_tracking/pricing_provider_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/cost_tracking/pricing_provider_test.exs`:

```elixir
defmodule PhoenixAI.Store.CostTracking.PricingProvider.StaticTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.CostTracking.PricingProvider.Static

  setup do
    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
      {:anthropic, "claude-sonnet-4-5"} => {"0.000003", "0.000015"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)
    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    :ok
  end

  describe "price_for/2" do
    test "returns Decimal prices for known model" do
      assert {:ok, {input, output}} = Static.price_for(:openai, "gpt-4o")
      assert Decimal.equal?(input, Decimal.new("0.0000025"))
      assert Decimal.equal?(output, Decimal.new("0.00001"))
    end

    test "returns error for unknown model" do
      assert {:error, :unknown_model} = Static.price_for(:openai, "nonexistent-model")
    end

    test "returns error when no pricing configured" do
      Application.delete_env(:phoenix_ai_store, :pricing)
      assert {:error, :unknown_model} = Static.price_for(:openai, "gpt-4o")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/cost_tracking/pricing_provider_test.exs`
Expected: FAIL — modules not defined

- [ ] **Step 3: Create PricingProvider behaviour**

Create `lib/phoenix_ai/store/cost_tracking/pricing_provider.ex`:

```elixir
defmodule PhoenixAI.Store.CostTracking.PricingProvider do
  @moduledoc """
  Behaviour for resolving per-token prices for a provider/model combination.

  The default implementation (`Static`) reads from Application config.
  Implement this behaviour for dynamic pricing (database, API, etc.).
  """

  @callback price_for(provider :: atom(), model :: String.t()) ::
              {:ok, {input_price :: Decimal.t(), output_price :: Decimal.t()}}
              | {:error, :unknown_model}
end
```

- [ ] **Step 4: Create Static implementation**

Create `lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex`:

```elixir
defmodule PhoenixAI.Store.CostTracking.PricingProvider.Static do
  @moduledoc """
  Default pricing provider that reads from Application config.

  ## Configuration

      config :phoenix_ai_store, :pricing, %{
        {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
        {:anthropic, "claude-sonnet-4-5"} => {"0.000003", "0.000015"}
      }

  Values are strings parsed to `Decimal` at lookup time.
  """

  @behaviour PhoenixAI.Store.CostTracking.PricingProvider

  @impl true
  def price_for(provider, model) do
    pricing = Application.get_env(:phoenix_ai_store, :pricing, %{})

    case Map.get(pricing, {provider, model}) do
      {input, output} ->
        {:ok, {Decimal.new(input), Decimal.new(output)}}

      nil ->
        {:error, :unknown_model}
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/phoenix_ai/store/cost_tracking/pricing_provider_test.exs --trace`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/cost_tracking/pricing_provider.ex lib/phoenix_ai/store/cost_tracking/pricing_provider/static.ex test/phoenix_ai/store/cost_tracking/pricing_provider_test.exs
git commit -m "feat(cost): add PricingProvider behaviour + Static default"
```

---

## Task 7: CostTracking Orchestrator

**Files:**
- Create: `lib/phoenix_ai/store/cost_tracking.ex`
- Create: `test/phoenix_ai/store/cost_tracking_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/cost_tracking_test.exs`:

```elixir
defmodule PhoenixAI.Store.CostTrackingTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.CostTracking
  alias PhoenixAI.Store.CostTracking.CostRecord

  # Stub adapter
  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.CostStore

    @impl true
    def save_cost_record(record, _opts), do: {:ok, record}

    @impl true
    def get_cost_records(_conv_id, _opts), do: {:ok, []}

    @impl true
    def sum_cost(_filters, _opts), do: {:ok, Decimal.new(0)}
  end

  defmodule NoSupportAdapter do
  end

  setup do
    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"},
      {:anthropic, "claude-sonnet-4-5"} => {"0.000003", "0.000015"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)
    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    :ok
  end

  defp build_response(attrs \\ %{}) do
    defaults = %{
      provider: :openai,
      model: "gpt-4o",
      usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
    }

    struct(PhoenixAI.Response, Map.merge(defaults, attrs))
  end

  describe "record/3" do
    test "records cost with Decimal arithmetic" do
      response = build_response()
      opts = [adapter: StubAdapter, adapter_opts: []]

      assert {:ok, %CostRecord{} = record} =
               CostTracking.record("conv_1", response, opts)

      # input: 1000 * 0.0000025 = 0.0025
      assert Decimal.equal?(record.input_cost, Decimal.new("0.0025000"))
      # output: 500 * 0.00001 = 0.005
      assert Decimal.equal?(record.output_cost, Decimal.new("0.0050000"))
      # total: 0.0075
      assert Decimal.equal?(record.total_cost, Decimal.new("0.0075000"))
      assert record.provider == :openai
      assert record.model == "gpt-4o"
      assert record.conversation_id == "conv_1"
    end

    test "returns error for non-normalized usage" do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %{input_tokens: 100}
      }

      opts = [adapter: StubAdapter, adapter_opts: []]
      assert {:error, :usage_not_normalized} = CostTracking.record("conv_1", response, opts)
    end

    test "returns error for unknown model pricing" do
      response = build_response(%{model: "unknown-model"})
      opts = [adapter: StubAdapter, adapter_opts: []]
      assert {:error, :pricing_not_found} = CostTracking.record("conv_1", response, opts)
    end

    test "returns error when adapter doesn't support CostStore" do
      response = build_response()
      opts = [adapter: NoSupportAdapter, adapter_opts: []]
      assert {:error, :cost_store_not_supported} = CostTracking.record("conv_1", response, opts)
    end

    test "passes user_id through to cost record" do
      response = build_response()
      opts = [adapter: StubAdapter, adapter_opts: [], user_id: "user_1"]

      assert {:ok, %CostRecord{user_id: "user_1"}} =
               CostTracking.record("conv_1", response, opts)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/cost_tracking_test.exs`
Expected: FAIL — `CostTracking` not defined

- [ ] **Step 3: Implement CostTracking orchestrator**

Create `lib/phoenix_ai/store/cost_tracking.ex`:

```elixir
defmodule PhoenixAI.Store.CostTracking do
  @moduledoc """
  Orchestrates cost recording for AI provider calls.

  Takes a `%PhoenixAI.Response{}`, looks up pricing via the configured
  `PricingProvider`, computes cost with `Decimal` arithmetic, and persists
  a `%CostRecord{}` through the adapter's `CostStore` sub-behaviour.
  """

  alias PhoenixAI.Store.CostTracking.{CostRecord, PricingProvider}

  @default_pricing_provider PricingProvider.Static

  @doc """
  Records the cost of a response for a conversation.

  ## Options

    * `:adapter` — adapter module (required)
    * `:adapter_opts` — adapter options (required)
    * `:user_id` — user to attribute cost to
    * `:pricing_provider` — module implementing `PricingProvider` (default: Static)
    * `:metadata` — extra metadata to attach to the cost record
  """
  @spec record(String.t(), PhoenixAI.Response.t(), keyword()) ::
          {:ok, CostRecord.t()} | {:error, term()}
  def record(conversation_id, %PhoenixAI.Response{} = response, opts) do
    with :ok <- validate_usage(response),
         {:ok, adapter, adapter_opts} <- resolve_adapter(opts),
         :ok <- check_cost_store_support(adapter),
         {:ok, {input_price, output_price}} <- lookup_pricing(response, opts) do
      cost_record = build_record(conversation_id, response, input_price, output_price, opts)

      case adapter.save_cost_record(cost_record, adapter_opts) do
        {:ok, saved} ->
          emit_telemetry(saved)
          {:ok, saved}

        {:error, _} = error ->
          error
      end
    end
  end

  # -- Private --

  defp validate_usage(%PhoenixAI.Response{usage: %PhoenixAI.Usage{}}), do: :ok
  defp validate_usage(_response), do: {:error, :usage_not_normalized}

  defp resolve_adapter(opts) do
    case {Keyword.get(opts, :adapter), Keyword.get(opts, :adapter_opts)} do
      {nil, _} -> {:error, :no_adapter}
      {adapter, adapter_opts} -> {:ok, adapter, adapter_opts || []}
    end
  end

  defp check_cost_store_support(adapter) do
    if function_exported?(adapter, :save_cost_record, 2) do
      :ok
    else
      {:error, :cost_store_not_supported}
    end
  end

  defp lookup_pricing(%PhoenixAI.Response{provider: provider, model: model}, opts) do
    pricing_provider = Keyword.get(opts, :pricing_provider, @default_pricing_provider)

    case pricing_provider.price_for(provider, model) do
      {:ok, _} = result -> result
      {:error, :unknown_model} -> {:error, :pricing_not_found}
    end
  end

  defp build_record(conversation_id, response, input_price, output_price, opts) do
    input_tokens = response.usage.input_tokens
    output_tokens = response.usage.output_tokens

    input_cost = Decimal.mult(Decimal.new(input_tokens), input_price)
    output_cost = Decimal.mult(Decimal.new(output_tokens), output_price)
    total_cost = Decimal.add(input_cost, output_cost)

    %CostRecord{
      id: Uniq.UUID.uuid7(),
      conversation_id: conversation_id,
      user_id: Keyword.get(opts, :user_id),
      provider: response.provider,
      model: response.model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      input_cost: input_cost,
      output_cost: output_cost,
      total_cost: total_cost,
      metadata: Keyword.get(opts, :metadata, %{}),
      recorded_at: DateTime.utc_now()
    }
  end

  defp emit_telemetry(%CostRecord{} = record) do
    :telemetry.execute(
      [:phoenix_ai_store, :cost, :recorded],
      %{total_cost: record.total_cost},
      %{
        conversation_id: record.conversation_id,
        user_id: record.user_id,
        provider: record.provider,
        model: record.model,
        input_tokens: record.input_tokens,
        output_tokens: record.output_tokens,
        input_cost: record.input_cost,
        output_cost: record.output_cost
      }
    )
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/cost_tracking_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/cost_tracking.ex test/phoenix_ai/store/cost_tracking_test.exs
git commit -m "feat(cost): add CostTracking orchestrator with Decimal arithmetic"
```

---

## Task 8: CostBudget Guardrail Policy

**Files:**
- Create: `lib/phoenix_ai/store/guardrails/cost_budget.ex`
- Create: `test/phoenix_ai/store/guardrails/cost_budget_test.exs`

- [ ] **Step 1: Write tests**

Create `test/phoenix_ai/store/guardrails/cost_budget_test.exs`:

```elixir
defmodule PhoenixAI.Store.Guardrails.CostBudgetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store.Guardrails.CostBudget

  defmodule StubAdapter do
    @behaviour PhoenixAI.Store.Adapter.CostStore

    @impl true
    def save_cost_record(r, _opts), do: {:ok, r}

    @impl true
    def get_cost_records(_id, _opts), do: {:ok, []}

    @impl true
    def sum_cost(filters, _opts) do
      case Keyword.get(filters, :conversation_id) do
        "conv_over" -> {:ok, Decimal.new("15.00")}
        "conv_under" -> {:ok, Decimal.new("3.00")}
        _ ->
          case Keyword.get(filters, :user_id) do
            "user_over" -> {:ok, Decimal.new("100.00")}
            "user_under" -> {:ok, Decimal.new("5.00")}
            _ -> {:ok, Decimal.new("0")}
          end
      end
    end
  end

  defmodule NoCostAdapter do
  end

  defp request(attrs \\ %{}) do
    defaults = %{
      messages: [%PhoenixAI.Message{role: :user, content: "test"}],
      conversation_id: "conv_under",
      user_id: "user_under",
      assigns: %{adapter: StubAdapter, adapter_opts: []}
    }

    struct(Request, Map.merge(defaults, attrs))
  end

  describe "check/2 with scope: :conversation" do
    test "passes when cost is under budget" do
      req = request(%{conversation_id: "conv_under"})
      assert {:ok, %Request{}} = CostBudget.check(req, scope: :conversation, max: "10.00")
    end

    test "halts when cost exceeds budget" do
      req = request(%{conversation_id: "conv_over"})

      assert {:halt, %PolicyViolation{} = v} =
               CostBudget.check(req, scope: :conversation, max: "10.00")

      assert v.policy == CostBudget
      assert v.reason =~ "Cost budget exceeded"
      assert Decimal.equal?(v.metadata.accumulated, Decimal.new("15.00"))
    end
  end

  describe "check/2 with scope: :user" do
    test "passes when under budget" do
      req = request(%{user_id: "user_under"})
      assert {:ok, %Request{}} = CostBudget.check(req, scope: :user, max: "50.00")
    end

    test "halts when over budget" do
      req = request(%{user_id: "user_over"})

      assert {:halt, %PolicyViolation{} = v} =
               CostBudget.check(req, scope: :user, max: "50.00")

      assert v.metadata.scope == :user
    end

    test "halts when user_id is nil" do
      req = request(%{user_id: nil})

      assert {:halt, %PolicyViolation{} = v} =
               CostBudget.check(req, scope: :user, max: "10.00")

      assert v.reason =~ "user_id"
    end
  end

  describe "check/2 with missing adapter" do
    test "halts with error" do
      req = request(%{assigns: %{}})

      assert {:halt, %PolicyViolation{} = v} =
               CostBudget.check(req, scope: :conversation, max: "10.00")

      assert v.reason =~ "adapter"
    end
  end

  describe "check/2 with unsupported adapter" do
    test "halts with error" do
      req = request(%{assigns: %{adapter: NoCostAdapter, adapter_opts: []}})

      assert {:halt, %PolicyViolation{} = v} =
               CostBudget.check(req, scope: :conversation, max: "10.00")

      assert v.reason =~ "not support"
    end
  end

  describe "check/2 accepts Decimal and string max" do
    test "string max works" do
      req = request(%{conversation_id: "conv_under"})
      assert {:ok, _} = CostBudget.check(req, scope: :conversation, max: "10.00")
    end

    test "Decimal max works" do
      req = request(%{conversation_id: "conv_under"})
      assert {:ok, _} = CostBudget.check(req, scope: :conversation, max: Decimal.new("10.00"))
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/guardrails/cost_budget_test.exs`
Expected: FAIL — `CostBudget` not defined

- [ ] **Step 3: Implement CostBudget policy**

Create `lib/phoenix_ai/store/guardrails/cost_budget.ex`:

```elixir
defmodule PhoenixAI.Store.Guardrails.CostBudget do
  @moduledoc """
  Guardrail policy that enforces cost budget limits.

  Mirrors `TokenBudget` but tracks accumulated dollar cost via
  the adapter's `CostStore.sum_cost/2` callback. All comparisons
  use `Decimal` arithmetic.

  ## Options

    * `:max` (required) — maximum cost as string or `Decimal.t()` (e.g., `"10.00"`)
    * `:scope` — `:conversation` (default), `:user`, or `:time_window`
    * `:window_ms` — for `:time_window` scope
    * `:rate_limiter` — for `:time_window` scope (Hammer module)
    * `:key_prefix` — Hammer key prefix (default: `"cost_budget"`)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  @spec check(Request.t(), keyword()) :: {:ok, Request.t()} | {:halt, PolicyViolation.t()}
  def check(%Request{} = request, opts) do
    scope = Keyword.get(opts, :scope, :conversation)
    max = parse_max(Keyword.fetch!(opts, :max))

    with {:ok, adapter, adapter_opts} <- extract_adapter(request),
         :ok <- validate_cost_store(adapter),
         {:ok, _} <- validate_scope(request, scope),
         {:ok, accumulated} <- fetch_accumulated(adapter, adapter_opts, request, scope) do
      case Decimal.compare(accumulated, max) do
        :gt -> {:halt, budget_violation(accumulated, max, scope)}
        _ -> {:ok, request}
      end
    end
  end

  defp parse_max(%Decimal{} = d), do: d
  defp parse_max(str) when is_binary(str), do: Decimal.new(str)

  defp extract_adapter(%Request{assigns: assigns}) do
    case {Map.get(assigns, :adapter), Map.get(assigns, :adapter_opts)} do
      {nil, _} ->
        {:halt, violation("No adapter in request.assigns. Use Store.check_guardrails/3.")}

      {adapter, opts} ->
        {:ok, adapter, opts || []}
    end
  end

  defp validate_cost_store(adapter) do
    if function_exported?(adapter, :sum_cost, 2) do
      :ok
    else
      {:halt, violation("Adapter #{inspect(adapter)} does not support CostStore.")}
    end
  end

  defp validate_scope(%Request{conversation_id: nil}, :conversation) do
    {:halt, violation("Scope :conversation requires conversation_id.")}
  end

  defp validate_scope(%Request{user_id: nil}, :user) do
    {:halt, violation("Scope :user requires user_id.")}
  end

  defp validate_scope(_request, _scope), do: {:ok, :valid}

  defp fetch_accumulated(adapter, adapter_opts, request, :conversation) do
    adapter.sum_cost([conversation_id: request.conversation_id], adapter_opts)
  end

  defp fetch_accumulated(adapter, adapter_opts, request, :user) do
    adapter.sum_cost([user_id: request.user_id], adapter_opts)
  end

  defp budget_violation(accumulated, max, scope) do
    %PolicyViolation{
      policy: __MODULE__,
      reason: "Cost budget exceeded: $#{accumulated} / $#{max} (scope: #{scope})",
      metadata: %{accumulated: accumulated, max: max, scope: scope}
    }
  end

  defp violation(reason) do
    %PolicyViolation{policy: __MODULE__, reason: reason, metadata: %{}}
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/guardrails/cost_budget_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/guardrails/cost_budget.ex test/phoenix_ai/store/guardrails/cost_budget_test.exs
git commit -m "feat(cost): add CostBudget guardrail policy"
```

---

## Task 9: Config Extension + Store Facade

**Files:**
- Modify: `lib/phoenix_ai/store/config.ex`
- Modify: `lib/phoenix_ai/store.ex`
- Create: `test/phoenix_ai/store/cost_integration_test.exs`

- [ ] **Step 1: Write integration tests**

Create `test/phoenix_ai/store/cost_integration_test.exs`:

```elixir
defmodule PhoenixAI.Store.CostIntegrationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}
  alias PhoenixAI.Store.CostTracking.CostRecord
  alias PhoenixAI.Store.Guardrails.CostBudget

  setup do
    store_name = :"cost_test_#{System.unique_integer([:positive])}"

    pricing = %{
      {:openai, "gpt-4o"} => {"0.0000025", "0.00001"}
    }

    Application.put_env(:phoenix_ai_store, :pricing, pricing)

    {:ok, _pid} =
      Store.start_link(
        name: store_name,
        adapter: PhoenixAI.Store.Adapters.ETS,
        cost_tracking: [enabled: true]
      )

    conv = %Conversation{id: Uniq.UUID.uuid7(), user_id: "cost_user", title: "Cost Test", messages: []}
    {:ok, _} = Store.save_conversation(conv, store: store_name)

    on_exit(fn -> Application.delete_env(:phoenix_ai_store, :pricing) end)
    {:ok, store: store_name, conv_id: conv.id}
  end

  describe "record_cost/3" do
    test "records cost from a Response", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      assert {:ok, %CostRecord{} = record} =
               Store.record_cost(conv_id, response, store: store, user_id: "cost_user")

      assert record.conversation_id == conv_id
      assert record.provider == :openai
      assert Decimal.equal?(record.input_cost, Decimal.new("0.0025000"))
    end
  end

  describe "get_cost_records/2" do
    test "returns records for a conversation", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store)
      {:ok, _} = Store.record_cost(conv_id, response, store: store)

      assert {:ok, records} = Store.get_cost_records(conv_id, store: store)
      assert length(records) == 2
    end
  end

  describe "sum_cost/2" do
    test "aggregates cost with filters", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "cost_user")
      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "cost_user")

      {:ok, total} = Store.sum_cost([user_id: "cost_user"], store: store)
      # 2 records * 0.0075 = 0.015
      assert Decimal.equal?(total, Decimal.new("0.0150000"))
    end
  end

  describe "CostBudget through check_guardrails/3" do
    test "halts when cost exceeds budget", %{store: store, conv_id: conv_id} do
      response = %PhoenixAI.Response{
        provider: :openai,
        model: "gpt-4o",
        usage: %PhoenixAI.Usage{input_tokens: 1000, output_tokens: 500, total_tokens: 1500}
      }

      {:ok, _} = Store.record_cost(conv_id, response, store: store, user_id: "cost_user")

      request = %Request{
        messages: [%PhoenixAI.Message{role: :user, content: "test"}],
        conversation_id: conv_id,
        user_id: "cost_user"
      }

      # Budget of $0.001 < accumulated $0.0075
      assert {:error, %PolicyViolation{policy: CostBudget}} =
               Store.check_guardrails(
                 request,
                 [{CostBudget, scope: :conversation, max: "0.001"}],
                 store: store
               )
    end
  end
end
```

- [ ] **Step 2: Add cost_tracking config section**

In `lib/phoenix_ai/store/config.ex`, add after the `guardrails` key:

```elixir
cost_tracking: [
  type: :keyword_list,
  default: [],
  doc: "Cost tracking configuration.",
  keys: [
    enabled: [type: :boolean, default: false, doc: "Enable cost tracking."],
    pricing_provider: [
      type: :atom,
      default: PhoenixAI.Store.CostTracking.PricingProvider.Static,
      doc: "Module implementing PricingProvider behaviour."
    ]
  ]
]
```

- [ ] **Step 3: Add facade functions to store.ex**

Add after the `check_guardrails/3` function, before the Long-Term Memory section:

```elixir
# -- Cost Tracking Facade --

alias PhoenixAI.Store.CostTracking
alias PhoenixAI.Store.CostTracking.CostRecord

@doc """
Records the cost of an AI response for a conversation.

Looks up pricing via the configured `PricingProvider`, computes cost
with `Decimal` arithmetic, and persists a `CostRecord` through the adapter.

## Options

  * `:store` — store instance name
  * `:user_id` — user to attribute cost to
  * `:metadata` — extra metadata for the cost record
"""
@spec record_cost(String.t(), PhoenixAI.Response.t(), keyword()) ::
        {:ok, CostRecord.t()} | {:error, term()}
def record_cost(conversation_id, %PhoenixAI.Response{} = response, opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :cost, :record], %{}, fn ->
    {adapter, adapter_opts, config} = resolve_adapter(opts)

    cost_opts =
      opts
      |> Keyword.merge(adapter: adapter, adapter_opts: adapter_opts)
      |> Keyword.put_new(
        :pricing_provider,
        get_in(config, [:cost_tracking, :pricing_provider]) ||
          CostTracking.PricingProvider.Static
      )

    result = CostTracking.record(conversation_id, response, cost_opts)
    {result, %{}}
  end)
end

@doc "Returns all cost records for a conversation."
@spec get_cost_records(String.t(), keyword()) ::
        {:ok, [CostRecord.t()]} | {:error, term()}
def get_cost_records(conversation_id, opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :cost, :get], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    result =
      if function_exported?(adapter, :get_cost_records, 2) do
        adapter.get_cost_records(conversation_id, adapter_opts)
      else
        {:error, :cost_store_not_supported}
      end

    {result, %{}}
  end)
end

@doc "Aggregates total cost matching the given filters."
@spec sum_cost(keyword(), keyword()) :: {:ok, Decimal.t()} | {:error, term()}
def sum_cost(filters \\ [], opts \\ []) do
  :telemetry.span([:phoenix_ai_store, :cost, :sum], %{}, fn ->
    {adapter, adapter_opts, _config} = resolve_adapter(opts)

    result =
      if function_exported?(adapter, :sum_cost, 2) do
        adapter.sum_cost(filters, adapter_opts)
      else
        {:error, :cost_store_not_supported}
      end

    {result, %{}}
  end)
end
```

- [ ] **Step 4: Run integration tests**

Run: `mix test test/phoenix_ai/store/cost_integration_test.exs --trace`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/config.ex lib/phoenix_ai/store.ex test/phoenix_ai/store/cost_integration_test.exs
git commit -m "feat(cost): add record_cost/3, get_cost_records/2, sum_cost/2 facade + config"
```

---

## Task 10: Final Verification

- [ ] **Step 1: Full test suite**

Run: `mix test`
Expected: All tests pass (244 original + ~40 new)

- [ ] **Step 2: Credo**

Run: `mix credo --strict`
Expected: No new issues in cost tracking files

- [ ] **Step 3: Clean compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 4: Commit any cleanup**

Only if Steps 1-3 required fixes.

---

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| COST-01 (pricing tables) | Task 6: PricingProvider + Static |
| COST-02 (per-conversation cost) | Task 7: CostTracking.record/3 |
| COST-03 (per-user cost) | Task 4-5: sum_cost with user_id filter |
| COST-04 (telemetry events) | Task 7: emit_telemetry in orchestrator |
| COST-05 (query by time/provider/model) | Task 3-5: sum_cost keyword filters |
| COST-06 (Ecto schema) | Task 5: Schemas.CostRecord + migration |
| COST-07 (guardrail integration) | Task 8: CostBudget policy |
| COST-08 (Decimal arithmetic) | Task 1: dep + Task 7: all math via Decimal |
| GUARD-02 (cost budget) | Task 8: CostBudget with 3 scopes |
