# Long-Term Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cross-conversation long-term memory — key-value fact extraction, AI-powered profile summaries, and automatic injection as pinned system messages.

**Architecture:** LTM as a layer above the existing Adapter. Sub-behaviours (`FactStore`, `ProfileStore`) extend the Adapter contract. An orchestrator module (`LongTermMemory`) coordinates extraction, profile updates, and injection. The `Injector` is a pure module that formats facts/profile as pinned messages.

**Tech Stack:** Elixir, ETS, Ecto (optional), PhoenixAI `AI.chat/2`, NimbleOptions, Telemetry

**Spec:** `.planning/phases/04-long-term-memory/BRAINSTORM.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `lib/phoenix_ai/store/long_term_memory/fact.ex` | Fact struct |
| `lib/phoenix_ai/store/long_term_memory/profile.ex` | Profile struct |
| `lib/phoenix_ai/store/adapter/fact_store.ex` | FactStore sub-behaviour |
| `lib/phoenix_ai/store/adapter/profile_store.ex` | ProfileStore sub-behaviour |
| `lib/phoenix_ai/store/long_term_memory/extractor.ex` | Extractor behaviour |
| `lib/phoenix_ai/store/long_term_memory/extractor/default.ex` | Default AI-powered extractor |
| `lib/phoenix_ai/store/long_term_memory/injector.ex` | Pure injection formatter |
| `lib/phoenix_ai/store/long_term_memory.ex` | Orchestrator (CRUD, extraction, profile) |
| `lib/phoenix_ai/store/schemas/fact.ex` | Ecto schema for facts (gated) |
| `lib/phoenix_ai/store/schemas/profile.ex` | Ecto schema for profiles (gated) |
| `test/phoenix_ai/store/long_term_memory/fact_test.exs` | Fact struct tests |
| `test/phoenix_ai/store/long_term_memory/injector_test.exs` | Injector tests |
| `test/phoenix_ai/store/long_term_memory/extractor/default_test.exs` | Default extractor tests |
| `test/phoenix_ai/store/long_term_memory_test.exs` | Orchestrator tests |
| `test/support/fact_store_contract_test.ex` | Shared contract tests for FactStore |
| `test/support/profile_store_contract_test.ex` | Shared contract tests for ProfileStore |

### Modified Files

| File | Change |
|------|--------|
| `lib/phoenix_ai/store/adapters/ets.ex` | Implement FactStore + ProfileStore |
| `lib/phoenix_ai/store/adapters/ecto.ex` | Implement FactStore + ProfileStore |
| `lib/phoenix_ai/store.ex` | Delegate LTM facade functions, update apply_memory/3 |
| `lib/phoenix_ai/store/config.ex` | Add `:long_term_memory` NimbleOptions schema |
| `priv/templates/migration.exs.eex` | Add facts + profiles tables |
| `test/phoenix_ai/store/adapters/ets_test.exs` | Use FactStore + ProfileStore contract tests |
| `test/phoenix_ai/store/adapters/ecto_test.exs` | Use FactStore + ProfileStore contract tests |

---

### Task 1: Fact struct and FactStore sub-behaviour

**Files:**
- Create: `lib/phoenix_ai/store/long_term_memory/fact.ex`
- Create: `lib/phoenix_ai/store/adapter/fact_store.ex`
- Create: `test/phoenix_ai/store/long_term_memory/fact_test.exs`

- [ ] **Step 1: Write the failing test for Fact struct**

```elixir
# test/phoenix_ai/store/long_term_memory/fact_test.exs
defmodule PhoenixAI.Store.LongTermMemory.FactTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Fact

  describe "struct" do
    test "creates a fact with defaults" do
      fact = %Fact{user_id: "user_1", key: "lang", value: "pt-BR"}
      assert fact.user_id == "user_1"
      assert fact.key == "lang"
      assert fact.value == "pt-BR"
      assert fact.id == nil
      assert fact.inserted_at == nil
      assert fact.updated_at == nil
    end

    test "creates a fact with all fields" do
      now = DateTime.utc_now()

      fact = %Fact{
        id: "abc-123",
        user_id: "user_1",
        key: "lang",
        value: "pt-BR",
        inserted_at: now,
        updated_at: now
      }

      assert fact.id == "abc-123"
      assert fact.inserted_at == now
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/long_term_memory/fact_test.exs`
Expected: Compilation error — `PhoenixAI.Store.LongTermMemory.Fact` not found

- [ ] **Step 3: Implement Fact struct**

```elixir
# lib/phoenix_ai/store/long_term_memory/fact.ex
defmodule PhoenixAI.Store.LongTermMemory.Fact do
  @moduledoc """
  A key-value fact associated with a user, persisted across conversations.

  Facts are simple string pairs — the key identifies what is known, the value
  holds the information. Save is upsert: writing to the same `{user_id, key}`
  silently overwrites the previous value.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          key: String.t(),
          value: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :user_id, :key, :value, :inserted_at, :updated_at]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/store/long_term_memory/fact_test.exs`
Expected: 2 tests, 0 failures

- [ ] **Step 5: Create FactStore sub-behaviour**

```elixir
# lib/phoenix_ai/store/adapter/fact_store.ex
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
```

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory/fact.ex \
        lib/phoenix_ai/store/adapter/fact_store.ex \
        test/phoenix_ai/store/long_term_memory/fact_test.exs
git commit -m "feat(ltm): add Fact struct and FactStore sub-behaviour"
```

---

### Task 2: Profile struct and ProfileStore sub-behaviour

**Files:**
- Create: `lib/phoenix_ai/store/long_term_memory/profile.ex`
- Create: `lib/phoenix_ai/store/adapter/profile_store.ex`

- [ ] **Step 1: Write test for Profile struct**

```elixir
# test/phoenix_ai/store/long_term_memory/fact_test.exs (append)
# OR create a separate file — keeping it in fact_test for now since both are simple structs

# Actually, add to same test file by renaming it or create:
# test/phoenix_ai/store/long_term_memory/profile_test.exs
defmodule PhoenixAI.Store.LongTermMemory.ProfileTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Profile

  describe "struct" do
    test "creates a profile with defaults" do
      profile = %Profile{user_id: "user_1"}
      assert profile.user_id == "user_1"
      assert profile.summary == nil
      assert profile.metadata == %{}
      assert profile.id == nil
    end

    test "creates a profile with all fields" do
      now = DateTime.utc_now()

      profile = %Profile{
        id: "abc-123",
        user_id: "user_1",
        summary: "An Elixir developer who prefers Portuguese.",
        metadata: %{"expertise_level" => "senior", "tags" => ["elixir", "ai"]},
        inserted_at: now,
        updated_at: now
      }

      assert profile.summary =~ "Elixir"
      assert profile.metadata["expertise_level"] == "senior"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/long_term_memory/profile_test.exs`
Expected: Compilation error — `PhoenixAI.Store.LongTermMemory.Profile` not found

- [ ] **Step 3: Implement Profile struct**

```elixir
# lib/phoenix_ai/store/long_term_memory/profile.ex
defmodule PhoenixAI.Store.LongTermMemory.Profile do
  @moduledoc """
  A user profile combining a free-text AI-generated summary with structured metadata.

  The `summary` field is injected into AI calls as a system message.
  The `metadata` map holds structured data (tags, expertise_level, etc.)
  that is queryable but not directly injected.

  One profile per `user_id` — save uses upsert semantics.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t(),
          summary: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :user_id, :summary, :inserted_at, :updated_at, metadata: %{}]
end
```

- [ ] **Step 4: Create ProfileStore sub-behaviour**

```elixir
# lib/phoenix_ai/store/adapter/profile_store.ex
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
```

- [ ] **Step 5: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory/profile_test.exs`
Expected: 2 tests, 0 failures

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory/profile.ex \
        lib/phoenix_ai/store/adapter/profile_store.ex \
        test/phoenix_ai/store/long_term_memory/profile_test.exs
git commit -m "feat(ltm): add Profile struct and ProfileStore sub-behaviour"
```

---

### Task 3: ETS adapter — FactStore + ProfileStore implementation

**Files:**
- Modify: `lib/phoenix_ai/store/adapters/ets.ex`
- Create: `test/support/fact_store_contract_test.ex`
- Create: `test/support/profile_store_contract_test.ex`
- Modify: `test/phoenix_ai/store/adapters/ets_test.exs`

- [ ] **Step 1: Write FactStore contract tests**

```elixir
# test/support/fact_store_contract_test.ex
defmodule PhoenixAI.Store.FactStoreContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.FactStore` implementations.

  Usage:

      defmodule MyAdapterFactTest do
        setup do
          {:ok, opts: [table: table]}
        end
        use PhoenixAI.Store.FactStoreContractTest, adapter: MyAdapter
      end
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.LongTermMemory.Fact

      @adapter unquote(macro_opts[:adapter])

      defp build_fact(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          user_id: "user_1",
          key: "preferred_language",
          value: "pt-BR"
        }

        struct(Fact, Map.merge(defaults, attrs))
      end

      describe "save_fact/2" do
        test "saves a new fact", %{opts: opts} do
          fact = build_fact()
          assert {:ok, saved} = @adapter.save_fact(fact, opts)
          assert saved.user_id == "user_1"
          assert saved.key == "preferred_language"
          assert saved.value == "pt-BR"
          assert saved.id != nil
          assert saved.inserted_at != nil
        end

        test "upserts existing fact (same user_id + key)", %{opts: opts} do
          fact = build_fact()
          {:ok, _} = @adapter.save_fact(fact, opts)

          updated = %{fact | value: "en-US"}
          {:ok, saved} = @adapter.save_fact(updated, opts)
          assert saved.value == "en-US"

          {:ok, facts} = @adapter.get_facts("user_1", opts)
          assert length(facts) == 1
          assert hd(facts).value == "en-US"
        end
      end

      describe "get_facts/2" do
        test "returns empty list for unknown user", %{opts: opts} do
          assert {:ok, []} = @adapter.get_facts("nonexistent", opts)
        end

        test "returns all facts for a user", %{opts: opts} do
          {:ok, _} = @adapter.save_fact(build_fact(%{key: "lang", value: "pt"}), opts)
          {:ok, _} = @adapter.save_fact(build_fact(%{key: "tz", value: "UTC-3"}), opts)

          {:ok, facts} = @adapter.get_facts("user_1", opts)
          assert length(facts) == 2
          keys = Enum.map(facts, & &1.key)
          assert "lang" in keys
          assert "tz" in keys
        end

        test "does not return other users' facts", %{opts: opts} do
          {:ok, _} = @adapter.save_fact(build_fact(%{user_id: "user_1", key: "a"}), opts)
          {:ok, _} = @adapter.save_fact(build_fact(%{user_id: "user_2", key: "b"}), opts)

          {:ok, facts} = @adapter.get_facts("user_1", opts)
          assert length(facts) == 1
          assert hd(facts).key == "a"
        end
      end

      describe "delete_fact/3" do
        test "deletes an existing fact", %{opts: opts} do
          {:ok, _} = @adapter.save_fact(build_fact(%{key: "lang"}), opts)
          assert :ok = @adapter.delete_fact("user_1", "lang", opts)

          {:ok, facts} = @adapter.get_facts("user_1", opts)
          assert facts == []
        end

        test "returns :ok for non-existent fact", %{opts: opts} do
          assert :ok = @adapter.delete_fact("user_1", "nonexistent", opts)
        end
      end

      describe "count_facts/2" do
        test "returns 0 for unknown user", %{opts: opts} do
          assert {:ok, 0} = @adapter.count_facts("nonexistent", opts)
        end

        test "returns correct count", %{opts: opts} do
          {:ok, _} = @adapter.save_fact(build_fact(%{key: "a", value: "1"}), opts)
          {:ok, _} = @adapter.save_fact(build_fact(%{key: "b", value: "2"}), opts)
          assert {:ok, 2} = @adapter.count_facts("user_1", opts)
        end

        test "does not double count on upsert", %{opts: opts} do
          fact = build_fact(%{key: "a", value: "1"})
          {:ok, _} = @adapter.save_fact(fact, opts)
          {:ok, _} = @adapter.save_fact(%{fact | value: "2"}, opts)
          assert {:ok, 1} = @adapter.count_facts("user_1", opts)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Write ProfileStore contract tests**

```elixir
# test/support/profile_store_contract_test.ex
defmodule PhoenixAI.Store.ProfileStoreContractTest do
  @moduledoc """
  Shared contract tests for `PhoenixAI.Store.Adapter.ProfileStore` implementations.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.LongTermMemory.Profile

      @adapter unquote(macro_opts[:adapter])

      defp build_profile(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          user_id: "user_1",
          summary: "An Elixir developer.",
          metadata: %{"tags" => ["elixir"]}
        }

        struct(Profile, Map.merge(defaults, attrs))
      end

      describe "save_profile/2" do
        test "saves a new profile", %{opts: opts} do
          profile = build_profile()
          assert {:ok, saved} = @adapter.save_profile(profile, opts)
          assert saved.user_id == "user_1"
          assert saved.summary == "An Elixir developer."
          assert saved.metadata == %{"tags" => ["elixir"]}
          assert saved.inserted_at != nil
        end

        test "upserts existing profile (same user_id)", %{opts: opts} do
          {:ok, _} = @adapter.save_profile(build_profile(), opts)

          updated = build_profile(%{summary: "A senior Elixir dev.", metadata: %{"level" => "senior"}})
          {:ok, saved} = @adapter.save_profile(updated, opts)
          assert saved.summary == "A senior Elixir dev."
          assert saved.metadata == %{"level" => "senior"}

          # Only one profile exists
          {:ok, loaded} = @adapter.load_profile("user_1", opts)
          assert loaded.summary == "A senior Elixir dev."
        end
      end

      describe "load_profile/2" do
        test "returns :not_found for unknown user", %{opts: opts} do
          assert {:error, :not_found} = @adapter.load_profile("nonexistent", opts)
        end

        test "returns the profile for a user", %{opts: opts} do
          {:ok, _} = @adapter.save_profile(build_profile(), opts)
          {:ok, profile} = @adapter.load_profile("user_1", opts)
          assert profile.summary == "An Elixir developer."
        end
      end

      describe "delete_profile/2" do
        test "deletes an existing profile", %{opts: opts} do
          {:ok, _} = @adapter.save_profile(build_profile(), opts)
          assert :ok = @adapter.delete_profile("user_1", opts)
          assert {:error, :not_found} = @adapter.load_profile("user_1", opts)
        end

        test "returns :ok for non-existent profile", %{opts: opts} do
          assert :ok = @adapter.delete_profile("nonexistent", opts)
        end
      end
    end
  end
end
```

- [ ] **Step 3: Run contract tests to verify they fail**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs`
Expected: Compilation error — ETS adapter doesn't implement FactStore/ProfileStore

- [ ] **Step 4: Implement FactStore in ETS adapter**

Add to `lib/phoenix_ai/store/adapters/ets.ex` — after `@behaviour PhoenixAI.Store.Adapter`:

```elixir
@behaviour PhoenixAI.Store.Adapter.FactStore
@behaviour PhoenixAI.Store.Adapter.ProfileStore
```

Add fact callbacks at the bottom of the module (before the Private Helpers section):

```elixir
  # -- FactStore --

  @impl PhoenixAI.Store.Adapter.FactStore
  def save_fact(%Fact{} = fact, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    fact =
      case :ets.match_object(table, {{:fact, fact.user_id, fact.key}, :_}) do
        [{_key, existing}] ->
          %{fact | id: existing.id, inserted_at: existing.inserted_at, updated_at: now}

        [] ->
          %{fact | id: fact.id || Uniq.UUID.uuid7(), inserted_at: now, updated_at: now}
      end

    :ets.insert(table, {{:fact, fact.user_id, fact.key}, fact})
    {:ok, fact}
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def get_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    facts =
      :ets.match_object(table, {{:fact, user_id, :_}, :_})
      |> Enum.map(fn {_key, fact} -> fact end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:ok, facts}
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def delete_fact(user_id, key, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:fact, user_id, key})
    :ok
  end

  @impl PhoenixAI.Store.Adapter.FactStore
  def count_facts(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    count = :ets.match_object(table, {{:fact, user_id, :_}, :_}) |> length()
    {:ok, count}
  end
```

Add the alias at the top:

```elixir
alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
```

- [ ] **Step 5: Implement ProfileStore in ETS adapter**

Add to the same file:

```elixir
  # -- ProfileStore --

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def save_profile(%Profile{} = profile, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    profile =
      case :ets.lookup(table, {:profile, profile.user_id}) do
        [{_key, existing}] ->
          %{profile | id: existing.id, inserted_at: existing.inserted_at, updated_at: now}

        [] ->
          %{profile | id: profile.id || Uniq.UUID.uuid7(), inserted_at: now, updated_at: now}
      end

    :ets.insert(table, {{:profile, profile.user_id}, profile})
    {:ok, profile}
  end

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def load_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:profile, user_id}) do
      [{_key, profile}] -> {:ok, profile}
      [] -> {:error, :not_found}
    end
  end

  @impl PhoenixAI.Store.Adapter.ProfileStore
  def delete_profile(user_id, opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.delete(table, {:profile, user_id})
    :ok
  end
```

- [ ] **Step 6: Add contract tests to ETS adapter test**

Add to the existing ETS test file (`test/phoenix_ai/store/adapters/ets_test.exs`), after the existing `use AdapterContractTest` line:

```elixir
use PhoenixAI.Store.FactStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
use PhoenixAI.Store.ProfileStoreContractTest, adapter: PhoenixAI.Store.Adapters.ETS
```

- [ ] **Step 7: Run tests**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs`
Expected: All tests pass (existing + new contract tests)

- [ ] **Step 8: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex \
        test/support/fact_store_contract_test.ex \
        test/support/profile_store_contract_test.ex \
        test/phoenix_ai/store/adapters/ets_test.exs
git commit -m "feat(ltm): implement FactStore + ProfileStore in ETS adapter"
```

---

### Task 4: Ecto schemas + Ecto adapter FactStore + ProfileStore

**Files:**
- Create: `lib/phoenix_ai/store/schemas/fact.ex`
- Create: `lib/phoenix_ai/store/schemas/profile.ex`
- Modify: `lib/phoenix_ai/store/adapters/ecto.ex`
- Modify: `priv/templates/migration.exs.eex`
- Modify: `test/phoenix_ai/store/adapters/ecto_test.exs`

- [ ] **Step 1: Create Fact Ecto schema**

```elixir
# lib/phoenix_ai/store/schemas/fact.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Fact do
    @moduledoc """
    Ecto schema for persisting `PhoenixAI.Store.LongTermMemory.Fact` structs.

    This module is only compiled when Ecto is available as a dependency.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.LongTermMemory.Fact, as: StoreFact

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [type: :utc_datetime_usec]

    schema "phoenix_ai_store_facts" do
      field :user_id, :string
      field :key, :string
      field :value, :string

      timestamps()
    end

    @cast_fields ~w(id user_id key value)a
    @required_fields ~w(user_id key value)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
      |> unique_constraint([:user_id, :key])
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreFact{
        id: schema.id,
        user_id: schema.user_id,
        key: schema.key,
        value: schema.value,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }
    end

    def from_store_struct(%StoreFact{} = fact) do
      %{
        id: fact.id,
        user_id: fact.user_id,
        key: fact.key,
        value: fact.value
      }
    end
  end
end
```

- [ ] **Step 2: Create Profile Ecto schema**

```elixir
# lib/phoenix_ai/store/schemas/profile.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Profile do
    @moduledoc """
    Ecto schema for persisting `PhoenixAI.Store.LongTermMemory.Profile` structs.

    This module is only compiled when Ecto is available as a dependency.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.LongTermMemory.Profile, as: StoreProfile

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [type: :utc_datetime_usec]

    schema "phoenix_ai_store_profiles" do
      field :user_id, :string
      field :summary, :string
      field :metadata, :map, default: %{}

      timestamps()
    end

    @cast_fields ~w(id user_id summary metadata)a
    @required_fields ~w(user_id)a

    def changeset(schema \\ %__MODULE__{}, attrs) do
      schema
      |> cast(attrs, @cast_fields)
      |> validate_required(@required_fields)
      |> unique_constraint(:user_id)
    end

    def to_store_struct(%__MODULE__{} = schema) do
      %StoreProfile{
        id: schema.id,
        user_id: schema.user_id,
        summary: schema.summary,
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }
    end

    def from_store_struct(%StoreProfile{} = profile) do
      %{
        id: profile.id,
        user_id: profile.user_id,
        summary: profile.summary,
        metadata: profile.metadata || %{}
      }
    end
  end
end
```

- [ ] **Step 3: Update migration template**

Add to `priv/templates/migration.exs.eex` at the end of the `change` function (before the closing `end`):

```eex
    create table(:<%= @prefix %>facts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :key, :string, null: false
      add :value, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:<%= @prefix %>facts, [:user_id, :key])
    create index(:<%= @prefix %>facts, [:user_id])

    create table(:<%= @prefix %>profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :summary, :text
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:<%= @prefix %>profiles, [:user_id])
```

- [ ] **Step 4: Implement FactStore + ProfileStore in Ecto adapter**

Add to `lib/phoenix_ai/store/adapters/ecto.ex`:

After existing `@behaviour` line:

```elixir
@behaviour PhoenixAI.Store.Adapter.FactStore
@behaviour PhoenixAI.Store.Adapter.ProfileStore
```

Add aliases:

```elixir
alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
alias PhoenixAI.Store.Schemas.Fact, as: FactSchema
alias PhoenixAI.Store.Schemas.Profile, as: ProfileSchema
```

Add FactStore implementation (before private helpers):

```elixir
    # -- FactStore --

    @impl PhoenixAI.Store.Adapter.FactStore
    def save_fact(%Fact{} = fact, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = FactSchema.from_store_struct(fact)

      case repo.one(
             from(f in fact_source(opts),
               where: f.user_id == ^fact.user_id and f.key == ^fact.key
             )
           ) do
        nil ->
          attrs = Map.put_new(attrs, :id, Uniq.UUID.uuid7())

          %FactSchema{}
          |> Ecto.put_meta(source: fact_table_name(opts))
          |> FactSchema.changeset(attrs)
          |> repo.insert()
          |> handle_fact_result()

        existing ->
          existing
          |> FactSchema.changeset(attrs)
          |> repo.update()
          |> handle_fact_result()
      end
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def get_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      facts =
        from(f in fact_source(opts),
          where: f.user_id == ^user_id,
          order_by: [asc: f.inserted_at]
        )
        |> repo.all()
        |> Enum.map(&FactSchema.to_store_struct/1)

      {:ok, facts}
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def delete_fact(user_id, key, opts) do
      repo = Keyword.fetch!(opts, :repo)

      from(f in fact_source(opts),
        where: f.user_id == ^user_id and f.key == ^key
      )
      |> repo.delete_all()

      :ok
    end

    @impl PhoenixAI.Store.Adapter.FactStore
    def count_facts(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      count =
        from(f in fact_source(opts),
          where: f.user_id == ^user_id,
          select: count(f.id)
        )
        |> repo.one()

      {:ok, count}
    end
```

Add ProfileStore implementation:

```elixir
    # -- ProfileStore --

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def save_profile(%Profile{} = profile, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ProfileSchema.from_store_struct(profile)

      case repo.one(from(p in profile_source(opts), where: p.user_id == ^profile.user_id)) do
        nil ->
          attrs = Map.put_new(attrs, :id, Uniq.UUID.uuid7())

          %ProfileSchema{}
          |> Ecto.put_meta(source: profile_table_name(opts))
          |> ProfileSchema.changeset(attrs)
          |> repo.insert()
          |> handle_profile_result()

        existing ->
          existing
          |> ProfileSchema.changeset(attrs)
          |> repo.update()
          |> handle_profile_result()
      end
    end

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def load_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.one(from(p in profile_source(opts), where: p.user_id == ^user_id)) do
        nil -> {:error, :not_found}
        schema -> {:ok, ProfileSchema.to_store_struct(schema)}
      end
    end

    @impl PhoenixAI.Store.Adapter.ProfileStore
    def delete_profile(user_id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      from(p in profile_source(opts), where: p.user_id == ^user_id) |> repo.delete_all()
      :ok
    end
```

Add helper functions in the Private Helpers section:

```elixir
    defp fact_source(opts), do: {fact_table_name(opts), FactSchema}
    defp profile_source(opts), do: {profile_table_name(opts), ProfileSchema}
    defp fact_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "facts"
    defp profile_table_name(opts), do: Keyword.get(opts, :prefix, "phoenix_ai_store_") <> "profiles"

    defp handle_fact_result({:ok, schema}), do: {:ok, FactSchema.to_store_struct(schema)}
    defp handle_fact_result({:error, changeset}), do: {:error, changeset}

    defp handle_profile_result({:ok, schema}), do: {:ok, ProfileSchema.to_store_struct(schema)}
    defp handle_profile_result({:error, changeset}), do: {:error, changeset}
```

- [ ] **Step 5: Regenerate test migration and add contract tests**

Regenerate the test migration to include fact/profile tables, then add to Ecto test:

```elixir
use PhoenixAI.Store.FactStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
use PhoenixAI.Store.ProfileStoreContractTest, adapter: PhoenixAI.Store.Adapters.Ecto
```

Run: `mix test test/phoenix_ai/store/adapters/ecto_test.exs`
Expected: All tests pass

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass (existing + new)

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/store/schemas/fact.ex \
        lib/phoenix_ai/store/schemas/profile.ex \
        lib/phoenix_ai/store/adapters/ecto.ex \
        priv/templates/migration.exs.eex \
        test/phoenix_ai/store/adapters/ecto_test.exs \
        priv/repo/migrations/
git commit -m "feat(ltm): implement FactStore + ProfileStore in Ecto adapter"
```

---

### Task 5: Extractor behaviour and Default implementation

**Files:**
- Create: `lib/phoenix_ai/store/long_term_memory/extractor.ex`
- Create: `lib/phoenix_ai/store/long_term_memory/extractor/default.ex`
- Create: `test/phoenix_ai/store/long_term_memory/extractor/default_test.exs`

- [ ] **Step 1: Write failing tests for Default extractor**

```elixir
# test/phoenix_ai/store/long_term_memory/extractor/default_test.exs
defmodule PhoenixAI.Store.LongTermMemory.Extractor.DefaultTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.Extractor.Default
  alias PhoenixAI.Store.Message

  defp make_messages do
    [
      %Message{role: :user, content: "I live in São Paulo and prefer Portuguese."},
      %Message{role: :assistant, content: "Noted! I'll communicate in Portuguese."}
    ]
  end

  describe "extract/3" do
    test "extracts facts using the provided extract_fn" do
      extract_fn = fn _messages, _context, _opts ->
        {:ok, ~s([{"key": "city", "value": "São Paulo"}, {"key": "language", "value": "Portuguese"}])}
      end

      context = %{user_id: "user_1", conversation_id: "conv_1"}
      opts = [extract_fn: extract_fn]

      assert {:ok, facts} = Default.extract(make_messages(), context, opts)
      assert length(facts) == 2
      assert %{key: "city", value: "São Paulo"} in facts
      assert %{key: "language", value: "Portuguese"} in facts
    end

    test "returns empty list when no facts extracted" do
      extract_fn = fn _messages, _context, _opts -> {:ok, "[]"} end
      context = %{user_id: "user_1"}

      assert {:ok, []} = Default.extract(make_messages(), context, [extract_fn: extract_fn])
    end

    test "returns error when AI call fails" do
      extract_fn = fn _messages, _context, _opts -> {:error, :api_error} end
      context = %{user_id: "user_1"}

      assert {:error, {:extraction_failed, :api_error}} =
               Default.extract(make_messages(), context, [extract_fn: extract_fn])
    end

    test "returns error when JSON is malformed" do
      extract_fn = fn _messages, _context, _opts -> {:ok, "not json at all"} end
      context = %{user_id: "user_1"}

      assert {:error, {:parse_error, _}} =
               Default.extract(make_messages(), context, [extract_fn: extract_fn])
    end

    test "returns ok empty when messages list is empty" do
      context = %{user_id: "user_1"}
      assert {:ok, []} = Default.extract([], context, [])
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/long_term_memory/extractor/default_test.exs`
Expected: Compilation error

- [ ] **Step 3: Create Extractor behaviour**

```elixir
# lib/phoenix_ai/store/long_term_memory/extractor.ex
defmodule PhoenixAI.Store.LongTermMemory.Extractor do
  @moduledoc """
  Behaviour for extracting key-value facts from conversation messages.

  Implementations receive a list of messages (typically only new ones since
  the last extraction) and a context map, and return a list of
  `%{key: String.t(), value: String.t()}` pairs.
  """

  alias PhoenixAI.Store.Message

  @callback extract(
              messages :: [Message.t()],
              context :: map(),
              opts :: keyword()
            ) :: {:ok, [%{key: String.t(), value: String.t()}]} | {:error, term()}
end
```

- [ ] **Step 4: Implement Default extractor**

```elixir
# lib/phoenix_ai/store/long_term_memory/extractor/default.ex
defmodule PhoenixAI.Store.LongTermMemory.Extractor.Default do
  @moduledoc """
  Default AI-powered fact extractor using `AI.chat/2`.

  Sends conversation messages to the AI with a prompt asking for key-value
  facts in JSON format. Accepts `:extract_fn` in opts for test injection.

  ## Options

    * `:extract_fn` - 3-arity function override for testing (avoids real AI calls)
    * `:provider` - AI provider (falls back to context)
    * `:model` - AI model (falls back to context)
  """

  @behaviour PhoenixAI.Store.LongTermMemory.Extractor

  @impl true
  def extract([], _context, _opts), do: {:ok, []}

  def extract(messages, context, opts) do
    case do_extract(messages, context, opts) do
      {:ok, json_string} -> parse_facts(json_string)
      {:error, reason} -> {:error, {:extraction_failed, reason}}
    end
  end

  defp do_extract(messages, context, opts) do
    case Keyword.get(opts, :extract_fn) do
      nil -> call_ai(messages, context, opts)
      fun when is_function(fun, 3) -> fun.(messages, context, opts)
    end
  end

  defp call_ai(messages, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

    unless provider do
      raise ArgumentError,
            "Fact extraction requires :provider in context or opts."
    end

    conversation_text =
      messages
      |> Enum.map(fn msg -> "#{msg.role}: #{msg.content}" end)
      |> Enum.join("\n")

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content: """
        Extract key facts about the user from the conversation below.
        Return a JSON array of objects with "key" and "value" fields.
        Keys should be snake_case identifiers (e.g., "preferred_language", "city", "expertise").
        Values should be concise strings.
        If no facts can be extracted, return an empty array [].
        Output ONLY the JSON array, no preamble or explanation.
        """
      },
      %PhoenixAI.Message{
        role: :user,
        content: conversation_text
      }
    ]

    ai_opts =
      [provider: provider, model: model]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case AI.chat(prompt, ai_opts) do
      {:ok, response} -> {:ok, response.content}
      {:error, _} = error -> error
    end
  end

  defp parse_facts(json_string) do
    case Jason.decode(json_string) do
      {:ok, facts} when is_list(facts) ->
        parsed =
          facts
          |> Enum.filter(fn f -> is_map(f) and Map.has_key?(f, "key") and Map.has_key?(f, "value") end)
          |> Enum.map(fn f -> %{key: f["key"], value: f["value"]} end)

        {:ok, parsed}

      {:ok, _other} ->
        {:error, {:parse_error, json_string}}

      {:error, _} ->
        {:error, {:parse_error, json_string}}
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory/extractor/default_test.exs`
Expected: 5 tests, 0 failures

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory/extractor.ex \
        lib/phoenix_ai/store/long_term_memory/extractor/default.ex \
        test/phoenix_ai/store/long_term_memory/extractor/default_test.exs
git commit -m "feat(ltm): add Extractor behaviour and Default AI implementation"
```

---

### Task 6: Injector — pure injection formatter

**Files:**
- Create: `lib/phoenix_ai/store/long_term_memory/injector.ex`
- Create: `test/phoenix_ai/store/long_term_memory/injector_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/phoenix_ai/store/long_term_memory/injector_test.exs
defmodule PhoenixAI.Store.LongTermMemory.InjectorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.LongTermMemory.{Fact, Injector, Profile}
  alias PhoenixAI.Store.Message

  defp make_messages do
    [
      %Message{role: :system, content: "You are helpful.", pinned: true},
      %Message{role: :user, content: "Hello"}
    ]
  end

  describe "inject/3" do
    test "returns messages unchanged when no facts and no profile" do
      messages = make_messages()
      assert Injector.inject([], nil, messages) == messages
    end

    test "injects facts as pinned system message" do
      facts = [
        %Fact{user_id: "u1", key: "language", value: "Portuguese"},
        %Fact{user_id: "u1", key: "city", value: "São Paulo"}
      ]

      result = Injector.inject(facts, nil, make_messages())

      assert length(result) == 3
      [facts_msg | _rest] = result
      assert facts_msg.role == :system
      assert facts_msg.pinned == true
      assert facts_msg.content =~ "language: Portuguese"
      assert facts_msg.content =~ "city: São Paulo"
    end

    test "injects profile as pinned system message" do
      profile = %Profile{user_id: "u1", summary: "An Elixir developer."}

      result = Injector.inject([], profile, make_messages())

      assert length(result) == 3
      [profile_msg | _rest] = result
      assert profile_msg.role == :system
      assert profile_msg.pinned == true
      assert profile_msg.content =~ "An Elixir developer."
    end

    test "injects both profile and facts (profile first, then facts)" do
      facts = [%Fact{user_id: "u1", key: "lang", value: "pt"}]
      profile = %Profile{user_id: "u1", summary: "Senior dev."}

      result = Injector.inject(facts, profile, make_messages())

      assert length(result) == 4
      [profile_msg, facts_msg | _rest] = result
      assert profile_msg.content =~ "Senior dev."
      assert facts_msg.content =~ "lang: pt"
    end

    test "skips profile injection when summary is nil" do
      profile = %Profile{user_id: "u1", summary: nil}
      facts = [%Fact{user_id: "u1", key: "a", value: "b"}]

      result = Injector.inject(facts, profile, make_messages())
      # Only facts message + original messages
      assert length(result) == 3
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/long_term_memory/injector_test.exs`
Expected: Compilation error

- [ ] **Step 3: Implement Injector**

```elixir
# lib/phoenix_ai/store/long_term_memory/injector.ex
defmodule PhoenixAI.Store.LongTermMemory.Injector do
  @moduledoc """
  Formats facts and profile as pinned system messages for injection
  into a conversation's message list.

  This is a pure module — no side effects, no IO. It receives data
  and returns a modified message list.

  Facts are formatted as a single system message with a key-value list.
  Profile is formatted as a separate system message with the summary text.
  Both messages have `pinned: true` and appear before existing messages.
  """

  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
  alias PhoenixAI.Store.Message

  @spec inject([Fact.t()], Profile.t() | nil, [Message.t()]) :: [Message.t()]
  def inject([], nil, messages), do: messages
  def inject([], %Profile{summary: nil}, messages), do: messages

  def inject(facts, profile, messages) do
    []
    |> maybe_add_profile(profile)
    |> maybe_add_facts(facts)
    |> Kernel.++(messages)
  end

  defp maybe_add_profile(acc, nil), do: acc
  defp maybe_add_profile(acc, %Profile{summary: nil}), do: acc

  defp maybe_add_profile(acc, %Profile{summary: summary}) do
    msg = %Message{
      role: :system,
      content: "User profile:\n#{summary}",
      pinned: true
    }

    acc ++ [msg]
  end

  defp maybe_add_facts(acc, []), do: acc

  defp maybe_add_facts(acc, facts) do
    lines =
      facts
      |> Enum.map(fn %Fact{key: key, value: value} -> "- #{key}: #{value}" end)
      |> Enum.join("\n")

    msg = %Message{
      role: :system,
      content: "User context:\n#{lines}",
      pinned: true
    }

    acc ++ [msg]
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory/injector_test.exs`
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory/injector.ex \
        test/phoenix_ai/store/long_term_memory/injector_test.exs
git commit -m "feat(ltm): add Injector pure module for context injection"
```

---

### Task 7: LongTermMemory orchestrator — manual CRUD

**Files:**
- Create: `lib/phoenix_ai/store/long_term_memory.ex`
- Create: `test/phoenix_ai/store/long_term_memory_test.exs`

- [ ] **Step 1: Write failing tests for manual CRUD**

```elixir
# test/phoenix_ai/store/long_term_memory_test.exs
defmodule PhoenixAI.Store.LongTermMemoryTest do
  use ExUnit.Case

  alias PhoenixAI.Store
  alias PhoenixAI.Store.LongTermMemory
  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}

  setup do
    {:ok, _pid} =
      Store.start_link(
        name: :"ltm_test_#{System.unique_integer([:positive])}",
        adapter: PhoenixAI.Store.Adapters.ETS
      )
      |> then(fn {:ok, pid} ->
        store_name = Process.info(pid) |> get_in([:registered_name]) |> to_string()
        {:ok, pid}
      end)

    store_name = :"ltm_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Store.start_link(name: store_name, adapter: PhoenixAI.Store.Adapters.ETS)

    {:ok, store: store_name}
  end

  describe "save_fact/2" do
    test "saves and retrieves a fact", %{store: store} do
      fact = %Fact{user_id: "user_1", key: "lang", value: "pt-BR"}
      assert {:ok, saved} = LongTermMemory.save_fact(fact, store: store)
      assert saved.key == "lang"
      assert saved.value == "pt-BR"
      assert saved.id != nil
    end
  end

  describe "get_facts/2" do
    test "returns facts for a user", %{store: store} do
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "b", value: "2"}, store: store)

      assert {:ok, facts} = LongTermMemory.get_facts("u1", store: store)
      assert length(facts) == 2
    end

    test "returns empty for unknown user", %{store: store} do
      assert {:ok, []} = LongTermMemory.get_facts("nobody", store: store)
    end
  end

  describe "delete_fact/3" do
    test "deletes a fact", %{store: store} do
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "a", value: "1"}, store: store)
      assert :ok = LongTermMemory.delete_fact("u1", "a", store: store)
      assert {:ok, []} = LongTermMemory.get_facts("u1", store: store)
    end
  end

  describe "save_profile/2 and get_profile/2" do
    test "saves and retrieves a profile", %{store: store} do
      profile = %Profile{user_id: "u1", summary: "Dev.", metadata: %{"level" => "senior"}}
      assert {:ok, saved} = LongTermMemory.save_profile(profile, store: store)
      assert saved.summary == "Dev."

      assert {:ok, loaded} = LongTermMemory.get_profile("u1", store: store)
      assert loaded.summary == "Dev."
    end

    test "returns :not_found for unknown user", %{store: store} do
      assert {:error, :not_found} = LongTermMemory.get_profile("nobody", store: store)
    end
  end

  describe "delete_profile/2" do
    test "deletes a profile", %{store: store} do
      {:ok, _} = LongTermMemory.save_profile(%Profile{user_id: "u1", summary: "X"}, store: store)
      assert :ok = LongTermMemory.delete_profile("u1", store: store)
      assert {:error, :not_found} = LongTermMemory.get_profile("u1", store: store)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs`
Expected: Compilation error

- [ ] **Step 3: Implement orchestrator with CRUD functions**

```elixir
# lib/phoenix_ai/store/long_term_memory.ex
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
    unless function_exported?(adapter, :save_fact, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.FactStore. " <>
              "Long-term memory requires an adapter that supports fact storage."
    end
  end

  defp check_profile_store!(adapter) do
    unless function_exported?(adapter, :save_profile, 2) do
      raise ArgumentError,
            "Adapter #{inspect(adapter)} does not implement PhoenixAI.Store.Adapter.ProfileStore. " <>
              "Long-term memory requires an adapter that supports profile storage."
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory.ex \
        test/phoenix_ai/store/long_term_memory_test.exs
git commit -m "feat(ltm): add LongTermMemory orchestrator with CRUD"
```

---

### Task 8: LongTermMemory — extract_facts with incremental cursor

**Files:**
- Modify: `lib/phoenix_ai/store/long_term_memory.ex`
- Modify: `test/phoenix_ai/store/long_term_memory_test.exs`

- [ ] **Step 1: Write failing tests for extract_facts**

Append to `test/phoenix_ai/store/long_term_memory_test.exs`:

```elixir
  describe "extract_facts/2" do
    setup %{store: store} do
      conv = %PhoenixAI.Store.Conversation{user_id: "user_1", messages: []}
      {:ok, conv} = Store.save_conversation(conv, store: store)
      {:ok, _} = Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "I live in SP"}, store: store)
      {:ok, _} = Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :assistant, content: "Got it!"}, store: store)
      {:ok, conv: conv}
    end

    test "extracts facts using extract_fn", %{store: store, conv: conv} do
      extract_fn = fn _messages, _context, _opts ->
        {:ok, ~s([{"key": "city", "value": "SP"}])}
      end

      assert {:ok, facts} =
               LongTermMemory.extract_facts(conv.id,
                 store: store,
                 extract_fn: extract_fn,
                 provider: :test
               )

      assert length(facts) == 1
      assert hd(facts).key == "city"

      # Facts are persisted
      assert {:ok, stored} = LongTermMemory.get_facts("user_1", store: store)
      assert length(stored) == 1
    end

    test "incremental extraction skips already-processed messages", %{store: store, conv: conv} do
      call_count = :counters.new(1, [:atomics])

      extract_fn = fn messages, _context, _opts ->
        :counters.add(call_count, 1, 1)
        count = length(messages)
        {:ok, ~s([{"key": "call_#{:counters.get(call_count, 1)}", "value": "#{count} msgs"}])}
      end

      # First extraction — processes 2 messages
      {:ok, _} = LongTermMemory.extract_facts(conv.id, store: store, extract_fn: extract_fn, provider: :test)

      # Add another message
      {:ok, _} = Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "New msg"}, store: store)

      # Second extraction — should only process the new message
      {:ok, _} = LongTermMemory.extract_facts(conv.id, store: store, extract_fn: extract_fn, provider: :test)

      {:ok, facts} = LongTermMemory.get_facts("user_1", store: store)
      # Second call should have received fewer messages
      second_fact = Enum.find(facts, &(&1.key == "call_2"))
      assert second_fact.value == "1 msgs"
    end

    test "returns ok empty when no new messages", %{store: store, conv: conv} do
      extract_fn = fn _msgs, _ctx, _opts -> {:ok, "[]"} end

      # First extraction processes everything
      {:ok, _} = LongTermMemory.extract_facts(conv.id, store: store, extract_fn: extract_fn, provider: :test)

      # Second extraction has no new messages
      assert {:ok, []} = LongTermMemory.extract_facts(conv.id, store: store, extract_fn: extract_fn, provider: :test)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs --only describe:"extract_facts/2"`
Expected: Fails — `extract_facts` not defined

- [ ] **Step 3: Implement extract_facts**

Add to `lib/phoenix_ai/store/long_term_memory.ex`:

```elixir
  alias PhoenixAI.Store.LongTermMemory.Extractor

  @spec extract_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def extract_facts(conversation_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_fact_store!(adapter)

    with {:ok, conv} <- adapter.load_conversation(conversation_id, adapter_opts),
         {:ok, all_messages} <- adapter.get_messages(conversation_id, adapter_opts) do
      cursor = get_in(conv.metadata, ["_ltm_cursor"])
      new_messages = filter_messages_after_cursor(all_messages, cursor)

      if new_messages == [] do
        {:ok, []}
      else
        extractor = Keyword.get(opts, :extractor, Extractor.Default)
        context = build_extraction_context(conv, opts)

        case extractor.extract(new_messages, context, opts) do
          {:ok, raw_facts} ->
            saved = save_extracted_facts(raw_facts, conv.user_id, adapter, adapter_opts, opts)
            update_cursor(conv, new_messages, adapter, adapter_opts)
            {:ok, saved}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  defp filter_messages_after_cursor(messages, nil), do: messages

  defp filter_messages_after_cursor(messages, cursor_id) do
    case Enum.find_index(messages, &(&1.id == cursor_id)) do
      nil -> messages
      idx -> Enum.drop(messages, idx + 1)
    end
  end

  defp build_extraction_context(conv, opts) do
    %{
      user_id: conv.user_id,
      conversation_id: conv.id,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model)
    }
  end

  defp save_extracted_facts(raw_facts, user_id, adapter, adapter_opts, opts) do
    max_facts = Keyword.get(opts, :max_facts_per_user, 100)

    Enum.reduce(raw_facts, [], fn %{key: key, value: value}, acc ->
      {:ok, count} = adapter.count_facts(user_id, adapter_opts)

      if count >= max_facts do
        acc
      else
        fact = %Fact{user_id: user_id, key: key, value: value}

        case adapter.save_fact(fact, adapter_opts) do
          {:ok, saved} -> acc ++ [saved]
          {:error, _} -> acc
        end
      end
    end)
  end

  defp update_cursor(conv, messages, adapter, adapter_opts) do
    last_msg = List.last(messages)

    if last_msg && last_msg.id do
      updated_metadata = Map.put(conv.metadata || %{}, "_ltm_cursor", last_msg.id)
      updated_conv = %{conv | metadata: updated_metadata}
      adapter.save_conversation(updated_conv, adapter_opts)
    end
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory.ex \
        test/phoenix_ai/store/long_term_memory_test.exs
git commit -m "feat(ltm): add extract_facts with incremental cursor"
```

---

### Task 9: LongTermMemory — update_profile

**Files:**
- Modify: `lib/phoenix_ai/store/long_term_memory.ex`
- Modify: `test/phoenix_ai/store/long_term_memory_test.exs`

- [ ] **Step 1: Write failing tests**

Append to test file:

```elixir
  describe "update_profile/2" do
    test "creates a new profile from facts", %{store: store} do
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "lang", value: "pt"}, store: store)
      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "role", value: "dev"}, store: store)

      profile_fn = fn _profile, _facts, _context, _opts ->
        {:ok, %{summary: "Portuguese-speaking developer.", metadata: %{"level" => "mid"}}}
      end

      assert {:ok, profile} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )

      assert profile.summary == "Portuguese-speaking developer."
      assert profile.metadata == %{"level" => "mid"}
    end

    test "refines existing profile", %{store: store} do
      {:ok, _} =
        LongTermMemory.save_profile(
          %Profile{user_id: "u1", summary: "A developer.", metadata: %{}},
          store: store
        )

      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "u1", key: "lang", value: "pt"}, store: store)

      profile_fn = fn existing_profile, _facts, _ctx, _opts ->
        assert existing_profile.summary == "A developer."
        {:ok, %{summary: "A Portuguese-speaking developer.", metadata: %{}}}
      end

      assert {:ok, profile} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )

      assert profile.summary =~ "Portuguese"
    end

    test "returns error when profile_fn fails", %{store: store} do
      profile_fn = fn _p, _f, _c, _o -> {:error, :ai_failed} end

      assert {:error, {:profile_update_failed, :ai_failed}} =
               LongTermMemory.update_profile("u1",
                 store: store,
                 profile_fn: profile_fn,
                 provider: :test
               )
    end
  end
```

- [ ] **Step 2: Implement update_profile**

Add to `lib/phoenix_ai/store/long_term_memory.ex`:

```elixir
  @spec update_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def update_profile(user_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    check_profile_store!(adapter)
    check_fact_store!(adapter)

    existing_profile =
      case adapter.load_profile(user_id, adapter_opts) do
        {:ok, profile} -> profile
        {:error, :not_found} -> nil
      end

    {:ok, facts} = adapter.get_facts(user_id, adapter_opts)

    context = %{
      user_id: user_id,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model)
    }

    case do_update_profile(existing_profile, facts, context, opts) do
      {:ok, %{summary: summary, metadata: metadata}} ->
        profile = %Profile{
          user_id: user_id,
          summary: summary,
          metadata: metadata || %{}
        }

        adapter.save_profile(profile, adapter_opts)

      {:error, reason} ->
        {:error, {:profile_update_failed, reason}}
    end
  end

  defp do_update_profile(existing_profile, facts, context, opts) do
    case Keyword.get(opts, :profile_fn) do
      nil -> call_profile_ai(existing_profile, facts, context, opts)
      fun when is_function(fun, 4) -> fun.(existing_profile, facts, context, opts)
    end
  end

  defp call_profile_ai(existing_profile, facts, context, opts) do
    provider = Keyword.get(opts, :provider, context[:provider])
    model = Keyword.get(opts, :model, context[:model])

    unless provider do
      raise ArgumentError,
            "Profile update requires :provider in context or opts."
    end

    facts_text =
      facts
      |> Enum.map(fn f -> "- #{f.key}: #{f.value}" end)
      |> Enum.join("\n")

    existing_text =
      if existing_profile && existing_profile.summary do
        "Current profile:\n#{existing_profile.summary}\n\n"
      else
        ""
      end

    prompt = [
      %PhoenixAI.Message{
        role: :system,
        content: """
        You are updating a user profile based on known facts.
        #{existing_text}User facts:
        #{facts_text}

        Generate a concise user profile summary (2-3 sentences) and structured metadata.
        Return JSON: {"summary": "...", "metadata": {"key": "value", ...}}
        Output ONLY the JSON, no preamble.
        """
      },
      %PhoenixAI.Message{
        role: :user,
        content: "Generate the updated profile."
      }
    ]

    ai_opts =
      [provider: provider, model: model]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case AI.chat(prompt, ai_opts) do
      {:ok, response} -> parse_profile_response(response.content)
      {:error, _} = error -> error
    end
  end

  defp parse_profile_response(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"summary" => summary} = data} ->
        {:ok, %{summary: summary, metadata: Map.get(data, "metadata", %{})}}

      _ ->
        {:error, {:parse_error, json_string}}
    end
  end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/long_term_memory.ex \
        test/phoenix_ai/store/long_term_memory_test.exs
git commit -m "feat(ltm): add update_profile with AI refinement"
```

---

### Task 10: Facade delegations and apply_memory/3 integration

**Files:**
- Modify: `lib/phoenix_ai/store.ex`
- Modify: `lib/phoenix_ai/store/config.ex`

- [ ] **Step 1: Write integration test for apply_memory with LTM injection**

Append to `test/phoenix_ai/store/long_term_memory_test.exs`:

```elixir
  describe "apply_memory/3 with LTM injection" do
    setup %{store: store} do
      conv = %PhoenixAI.Store.Conversation{user_id: "user_1", messages: []}
      {:ok, conv} = Store.save_conversation(conv, store: store)
      {:ok, _} = Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :system, content: "Be helpful.", pinned: true}, store: store)
      {:ok, _} = Store.add_message(conv.id, %PhoenixAI.Store.Message{role: :user, content: "Hello"}, store: store)

      {:ok, _} = LongTermMemory.save_fact(%Fact{user_id: "user_1", key: "lang", value: "pt"}, store: store)
      {:ok, _} = LongTermMemory.save_profile(%Profile{user_id: "user_1", summary: "A dev."}, store: store)

      {:ok, conv: conv}
    end

    test "injects facts and profile as pinned messages", %{store: store, conv: conv} do
      pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)

      {:ok, messages} =
        Store.apply_memory(conv.id, pipeline,
          store: store,
          inject_long_term_memory: true,
          user_id: "user_1"
        )

      # Should have: profile msg + facts msg + system msg + user msg
      assert length(messages) >= 3

      contents = Enum.map(messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "A dev."))
      assert Enum.any?(contents, &(&1 =~ "lang: pt"))
    end

    test "does not inject when option is false", %{store: store, conv: conv} do
      pipeline = PhoenixAI.Store.Memory.Pipeline.preset(:default)

      {:ok, messages} =
        Store.apply_memory(conv.id, pipeline, store: store)

      contents = Enum.map(messages, & &1.content)
      refute Enum.any?(contents, &(&1 =~ "A dev."))
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/store/long_term_memory_test.exs --only describe:"apply_memory/3"`
Expected: Fails — no LTM injection in apply_memory yet

- [ ] **Step 3: Update apply_memory/3 in store.ex**

Modify the `apply_memory/3` function in `lib/phoenix_ai/store.ex` to inject LTM before Pipeline.run:

```elixir
  alias PhoenixAI.Store.LongTermMemory
  alias PhoenixAI.Store.LongTermMemory.Injector

  @spec apply_memory(String.t(), Pipeline.t(), keyword()) ::
          {:ok, [PhoenixAI.Message.t()]} | {:error, term()}
  def apply_memory(conversation_id, %Pipeline{} = pipeline, opts \\ []) do
    :telemetry.span([:phoenix_ai_store, :memory, :apply], %{}, fn ->
      {adapter, adapter_opts, config} = resolve_adapter(opts)

      context = %{
        conversation_id: conversation_id,
        model: Keyword.get(opts, :model, config[:model]),
        provider: Keyword.get(opts, :provider, config[:provider]),
        max_tokens: Keyword.get(opts, :max_tokens),
        token_counter:
          Keyword.get(opts, :token_counter, PhoenixAI.Store.Memory.TokenCounter.Default)
      }

      with {:ok, messages} <- adapter.get_messages(conversation_id, adapter_opts) do
        messages = maybe_inject_ltm(messages, adapter, adapter_opts, opts)

        case Pipeline.run(pipeline, messages, context) do
          {:ok, filtered} ->
            result = {:ok, Enum.map(filtered, &Message.to_phoenix_ai/1)}
            {result, %{}}

          {:error, _} = error ->
            {error, %{}}
        end
      else
        {:error, _} = error -> {error, %{}}
      end
    end)
  end

  defp maybe_inject_ltm(messages, adapter, adapter_opts, opts) do
    user_id = Keyword.get(opts, :user_id)
    inject? = Keyword.get(opts, :inject_long_term_memory, false)

    if inject? && user_id && function_exported?(adapter, :save_fact, 2) do
      {:ok, facts} = adapter.get_facts(user_id, adapter_opts)

      profile =
        if function_exported?(adapter, :load_profile, 2) do
          case adapter.load_profile(user_id, adapter_opts) do
            {:ok, p} -> p
            {:error, :not_found} -> nil
          end
        end

      Injector.inject(facts, profile, messages)
    else
      messages
    end
  end
```

- [ ] **Step 4: Add LTM facade delegations to store.ex**

Add to `lib/phoenix_ai/store.ex` after the existing public API section:

```elixir
  # -- Long-Term Memory Facade --

  def save_fact(fact, opts \\ []), do: LongTermMemory.save_fact(fact, opts)
  def get_facts(user_id, opts \\ []), do: LongTermMemory.get_facts(user_id, opts)
  def delete_fact(user_id, key, opts \\ []), do: LongTermMemory.delete_fact(user_id, key, opts)
  def extract_facts(conversation_id, opts \\ []), do: LongTermMemory.extract_facts(conversation_id, opts)
  def save_profile(profile, opts \\ []), do: LongTermMemory.save_profile(profile, opts)
  def get_profile(user_id, opts \\ []), do: LongTermMemory.get_profile(user_id, opts)
  def delete_profile(user_id, opts \\ []), do: LongTermMemory.delete_profile(user_id, opts)
  def update_profile(user_id, opts \\ []), do: LongTermMemory.update_profile(user_id, opts)
```

- [ ] **Step 5: Update Config with LTM options**

Add to `lib/phoenix_ai/store/config.ex` in the `@schema`:

```elixir
    long_term_memory: [
      type: :keyword_list,
      default: [],
      doc: "Long-term memory configuration.",
      keys: [
        enabled: [type: :boolean, default: false, doc: "Enable LTM subsystem."],
        max_facts_per_user: [type: :pos_integer, default: 100, doc: "Maximum facts per user."],
        extraction_trigger: [
          type: {:in, [:manual, :per_turn, :on_close]},
          default: :manual,
          doc: "When fact extraction runs: :manual, :per_turn, or :on_close."
        ],
        extraction_mode: [
          type: {:in, [:sync, :async]},
          default: :sync,
          doc: "Whether extraction blocks (:sync) or runs in background (:async)."
        ],
        extractor: [
          type: :atom,
          default: PhoenixAI.Store.LongTermMemory.Extractor.Default,
          doc: "Module implementing the Extractor behaviour."
        ],
        inject_long_term_memory: [
          type: :boolean,
          default: false,
          doc: "Auto-inject facts/profile in apply_memory/3."
        ],
        extraction_provider: [type: :atom, doc: "Provider override for extraction AI calls."],
        extraction_model: [type: :string, doc: "Model override for extraction AI calls."],
        profile_provider: [type: :atom, doc: "Provider override for profile AI calls."],
        profile_model: [type: :string, doc: "Model override for profile AI calls."]
      ]
    ]
```

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/store.ex \
        lib/phoenix_ai/store/config.ex \
        test/phoenix_ai/store/long_term_memory_test.exs
git commit -m "feat(ltm): integrate LTM into facade and apply_memory pipeline"
```

---

### Task 11: Final verification

**Files:** None — verification only

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 2: Check compilation with no warnings**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 3: Verify test count increased**

Run: `mix test --trace 2>&1 | tail -1`
Expected: ~170+ tests (133 existing + ~40 new), 0 failures

- [ ] **Step 4: Commit any remaining changes**

If any files were missed, stage and commit them.

---

## Requirement Coverage

| Requirement | Task(s) |
|-------------|---------|
| LTM-01: Extract and store key-value facts | Tasks 1, 3, 4, 8 |
| LTM-02: Manual CRUD for user facts | Tasks 1, 3, 4, 7 |
| LTM-03: AI-powered profile summary | Tasks 2, 3, 4, 9 |
| LTM-04: Auto-inject facts/profile before AI calls | Tasks 6, 10 |
| LTM-05: Custom extraction via Extractor behaviour | Task 5 |
