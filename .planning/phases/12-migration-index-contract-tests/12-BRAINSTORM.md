# Phase 12: Migration Index & Contract Tests — Design Spec

**Date:** 2026-04-07
**Phase:** 12-migration-index-contract-tests
**Approach:** Versioned upgrade template (Oban pattern)

## Overview

Add composite `(recorded_at, id)` index to cost_records for cursor pagination performance. Provide upgrade path for existing projects via `--upgrade` flag on the mix task. Verify contract test coverage is complete.

**Scope:** 2 files modified, 1 new template, 1 new test file

## 1. Cost Migration Template Update

File: `priv/templates/cost_migration.exs.eex`

Add the cursor composite index after the existing indexes (after line 27):

```elixir
    create index(:<%= @prefix %>cost_records, [:recorded_at, :id],
      name: :<%= @prefix %>cost_records_cursor_idx)
```

New projects running `mix phoenix_ai_store.gen.migration --cost` (or the full migration) get this index automatically.

## 2. Upgrade Migration Template

New file: `priv/templates/upgrade_v030_migration.exs.eex`

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

Uses `create_if_not_exists` — safe to run even if the index already exists (new projects that already have it from the base template).

Future versions add new templates (`upgrade_v040_migration.exs.eex`, etc.) following the same pattern.

## 3. Mix Task --upgrade Flag

File: `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`

### Changes:

1. Add `upgrade: :boolean` to `OptionParser` strict list
2. Add `upgrade = Keyword.get(opts, :upgrade, false)` 
3. Add clause in `cond` (before `true` catch-all):

```elixir
      upgrade ->
        generate_upgrade_migrations(prefix, slug, migrations_path)
```

### New function `generate_upgrade_migrations/3`:

Iterates over all `upgrade_v*_migration.exs.eex` templates in `priv/templates/`, checks if each has already been generated (via `Path.wildcard` matching the output filename pattern), generates those that are missing.

```elixir
  defp generate_upgrade_migrations(prefix, slug, migrations_path) do
    templates_dir = find_templates_dir()
    upgrade_templates = Path.wildcard(Path.join(templates_dir, "upgrade_v*_migration.exs.eex"))

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

### Documentation update in `@moduledoc`:

```
  For existing installations upgrading to a new version:

      $ mix phoenix_ai_store.gen.migration --upgrade
```

## 4. Tests

### Mix task --upgrade tests

File: `test/mix/tasks/phoenix_ai_store_gen_migration_test.exs` (existing or new)

Tests to add:

1. **--upgrade generates upgrade migration** — runs `mix phoenix_ai_store.gen.migration --upgrade`, verifies file created with correct name pattern and contains `create_if_not_exists index`
2. **--upgrade is idempotent** — running twice doesn't generate a duplicate file
3. **--upgrade with no pending upgrades** — shows info message when all upgrades already generated

### Contract test verification

Contract tests were already updated in Phase 11 (14 list_cost_records + 2 count_cost_records tests). No additional contract test changes needed for Phase 12.

## Files Changed Summary

| File | Action |
|------|--------|
| `priv/templates/cost_migration.exs.eex` | Modify — add cursor index |
| `priv/templates/upgrade_v030_migration.exs.eex` | Create — upgrade template |
| `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` | Modify — add --upgrade flag |
| `test/mix/tasks/phoenix_ai_store_gen_migration_test.exs` | Modify — add upgrade tests |

## Requirements Coverage

| Requirement | How |
|-------------|-----|
| MIGR-01: Migration includes cursor index | Template updated + upgrade template created |
| MIGR-02: Contract tests updated | Already done in Phase 11 — verified complete |

## Decisions Log

| ID | Decision | Rationale |
|----|----------|-----------|
| D-01 | Versioned upgrade templates | Oban pattern — scales with future versions |
| D-02 | `create_if_not_exists` in upgrade | Safe for new projects that already have the index |
| D-03 | --upgrade generates all pending | Single command for users upgrading across multiple versions |
| D-04 | Wildcard discovery of templates | No hardcoded version list — adding a template file is enough |

---
*Design approved: 2026-04-07*
*Approach: A — Versioned upgrade templates*
