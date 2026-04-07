# Migration Index & Upgrade Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add composite `(recorded_at, id)` cursor index to cost_records migration template, and provide an `--upgrade` flag for existing projects to generate additive index migrations.

**Architecture:** Update existing cost migration template with the new index. Create a versioned upgrade template (`upgrade_v030_migration.exs.eex`). Extend the mix task with `--upgrade` flag that discovers and generates all pending upgrade migrations.

**Tech Stack:** Elixir, Ecto.Migration, EEx, Mix.Task, ExUnit

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `priv/templates/cost_migration.exs.eex` | Modify | Add cursor index for new projects |
| `priv/templates/upgrade_v030_migration.exs.eex` | Create | Upgrade migration for existing projects |
| `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` | Modify | Add --upgrade flag and generation logic |
| `test/mix/tasks/phoenix_ai_store.gen.migration_test.exs` | Modify | Add upgrade tests |

---

### Task 1: Add Cursor Index to Cost Migration Template

**Files:**
- Modify: `priv/templates/cost_migration.exs.eex:24-28`

- [ ] **Step 1: Add the composite cursor index to the template**

In `priv/templates/cost_migration.exs.eex`, after line 27 (`create index(:<%= @prefix %>cost_records, [:user_id, :recorded_at])`), add:

```elixir
    create index(:<%= @prefix %>cost_records, [:recorded_at, :id],
      name: :<%= @prefix %>cost_records_cursor_idx)
```

- [ ] **Step 2: Update the existing migration test to assert the new index**

In `test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`, the test `"generates migration file with correct content"` does not check cost_records (it checks the full migration template, not `--cost`). We need to verify the cost template separately. Add a new test after the existing ones:

```elixir
  test "generates cost migration with cursor index" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--cost"
      ])
    end)

    [file] = Path.wildcard(Path.join(@tmp_dir, "*_add_phoenix_ai_store_cost_tables.exs"))
    content = File.read!(file)

    assert content =~ "create table(:phoenix_ai_store_cost_records, primary_key: false)"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:conversation_id])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:user_id])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:recorded_at])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:user_id, :recorded_at])"
    assert content =~ "create index(:phoenix_ai_store_cost_records, [:recorded_at, :id]"
    assert content =~ "cost_records_cursor_idx"
  end
```

- [ ] **Step 3: Run tests to verify**

Run: `mix test test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add priv/templates/cost_migration.exs.eex test/mix/tasks/phoenix_ai_store.gen.migration_test.exs
git commit -m "feat(migration): add cursor composite index to cost_records template"
```

---

### Task 2: Create Upgrade Migration Template

**Files:**
- Create: `priv/templates/upgrade_v030_migration.exs.eex`

- [ ] **Step 1: Create the upgrade template**

```elixir
defmodule <%= @repo_module %>.Migrations.Upgrade<%= @migration_module %>V030 do
  use Ecto.Migration

  def change do
    # v0.3.0: Composite index for cursor-based pagination on cost_records
    create_if_not_exists index(:<%= @prefix %>cost_records, [:recorded_at, :id],
      name: :<%= @prefix %>cost_records_cursor_idx)
  end
end
```

- [ ] **Step 2: Verify the template is valid EEx**

Run: `mix run -e 'EEx.eval_file("priv/templates/upgrade_v030_migration.exs.eex", assigns: [prefix: "phoenix_ai_store_", migration_module: "PhoenixAiStore", repo_module: "MyApp.Repo"]) |> IO.puts()'`
Expected: Outputs valid Elixir migration code without errors

- [ ] **Step 3: Commit**

```bash
git add priv/templates/upgrade_v030_migration.exs.eex
git commit -m "feat(migration): add v0.3.0 upgrade template for cursor index"
```

---

### Task 3: Add --upgrade Flag to Mix Task

**Files:**
- Modify: `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`

- [ ] **Step 1: Add upgrade option to OptionParser (line 44)**

Add `upgrade: :boolean` to the strict list:

```elixir
      OptionParser.parse(args,
        strict: [
          prefix: :string,
          migrations_path: :string,
          ltm: :boolean,
          cost: :boolean,
          events: :boolean,
          upgrade: :boolean
        ]
      )
```

- [ ] **Step 2: Add upgrade variable (after line 53)**

```elixir
    upgrade = Keyword.get(opts, :upgrade, false)
```

- [ ] **Step 3: Add upgrade clause in cond (before the `true` catch-all at line 69)**

```elixir
      upgrade ->
        generate_upgrade_migrations(prefix, slug, migrations_path)
```

- [ ] **Step 4: Add generate_upgrade_migrations/3 and helpers (before generate_timestamp)**

```elixir
  defp generate_upgrade_migrations(prefix, slug, migrations_path) do
    templates_dir = find_templates_dir()
    upgrade_templates =
      Path.wildcard(Path.join(templates_dir, "upgrade_v*_migration.exs.eex"))
      |> Enum.sort()

    if upgrade_templates == [] do
      Mix.shell().info("No upgrade migrations available.")
      :ok
    else
      migration_module = module_from_prefix(prefix)
      repo_module = detect_repo_module()
      assigns = [prefix: prefix, migration_module: migration_module, repo_module: repo_module]

      generated =
        Enum.reduce(upgrade_templates, 0, fn template_path, count ->
          version = extract_version(template_path)
          pattern = "*_upgrade_#{slug}_#{version}.exs"
          existing = Path.wildcard(Path.join(migrations_path, pattern))

          if existing != [] do
            Mix.shell().info("Upgrade #{version} already exists: #{hd(existing)}")
            count
          else
            timestamp = generate_timestamp()
            content = EEx.eval_file(template_path, assigns: assigns)
            filename = "#{timestamp}_upgrade_#{slug}_#{version}.exs"
            filepath = Path.join(migrations_path, filename)
            Mix.Generator.create_file(filepath, content)
            count + 1
          end
        end)

      if generated == 0 do
        Mix.shell().info("All upgrade migrations already generated.")
      end

      :ok
    end
  end

  defp extract_version(template_path) do
    template_path
    |> Path.basename(".exs.eex")
    |> String.replace("upgrade_", "")
    |> String.replace("_migration", "")
  end

  defp find_templates_dir do
    case Application.app_dir(:phoenix_ai_store, "priv/templates") do
      path when is_binary(path) ->
        if File.dir?(path), do: path, else: fallback_templates_dir()
    end
  rescue
    _ -> fallback_templates_dir()
  end

  defp fallback_templates_dir do
    Path.join([File.cwd!(), "priv", "templates"])
  end
```

- [ ] **Step 5: Update @moduledoc (after line 19)**

Add before the `## Options` section:

```elixir
  For existing installations upgrading to a new version:

      $ mix phoenix_ai_store.gen.migration --upgrade
```

And add to Options:

```elixir
    * `--upgrade` - Generate pending upgrade migrations for existing installations
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 7: Commit**

```bash
git add lib/mix/tasks/phoenix_ai_store.gen.migration.ex
git commit -m "feat(migration): add --upgrade flag for existing installations"
```

---

### Task 4: Add Upgrade Tests

**Files:**
- Modify: `test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`

- [ ] **Step 1: Add upgrade migration tests**

Append these tests to the existing test module:

```elixir
  test "generates upgrade migration with --upgrade" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--upgrade"
      ])
    end)

    files = Path.wildcard(Path.join(@tmp_dir, "*_upgrade_phoenix_ai_store_v030.exs"))
    assert length(files) == 1

    content = File.read!(hd(files))
    assert content =~ "UpgradePhoenixAiStoreV030"
    assert content =~ "create_if_not_exists index(:phoenix_ai_store_cost_records, [:recorded_at, :id]"
    assert content =~ "cost_records_cursor_idx"
  end

  test "--upgrade is idempotent" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--upgrade"
      ])
    end)

    files_before = Path.wildcard(Path.join(@tmp_dir, "*_upgrade_*.exs"))
    assert length(files_before) == 1

    output =
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
          "--migrations-path",
          @tmp_dir,
          "--upgrade"
        ])
      end)

    assert output =~ "already exists"

    files_after = Path.wildcard(Path.join(@tmp_dir, "*_upgrade_*.exs"))
    assert length(files_after) == 1
  end

  test "--upgrade with custom prefix" do
    capture_io(fn ->
      Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
        "--migrations-path",
        @tmp_dir,
        "--upgrade",
        "--prefix",
        "my_ai_"
      ])
    end)

    files = Path.wildcard(Path.join(@tmp_dir, "*_upgrade_my_ai_v030.exs"))
    assert length(files) == 1

    content = File.read!(hd(files))
    assert content =~ "UpgradeMyAiV030"
    assert content =~ "create_if_not_exists index(:my_ai_cost_records"
  end
```

- [ ] **Step 2: Run all migration tests**

Run: `mix test test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`
Expected: All tests PASS (existing 3 + new 4 = 7 total)

- [ ] **Step 3: Commit**

```bash
git add test/mix/tasks/phoenix_ai_store.gen.migration_test.exs
git commit -m "test(migration): add upgrade flag tests"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests PASS

- [ ] **Step 2: Compile with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean

- [ ] **Step 3: Format check**

Run: `mix format --check-formatted`
Expected: All formatted

- [ ] **Step 4: Fix formatting if needed and commit**

```bash
mix format && git add -A && git diff --cached --quiet || git commit -m "style: format migration changes"
```

---

## Task Dependency Order

```
Task 1 (Template index) → Task 2 (Upgrade template) → Task 3 (Mix task flag) → Task 4 (Tests) → Task 5 (Verification)
```

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| MIGR-01: Migration includes cursor index | Tasks 1, 2 |
| MIGR-02: Contract tests updated | Phase 11 (verified) + Task 4 (upgrade tests) |
