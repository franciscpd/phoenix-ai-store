defmodule Mix.Tasks.PhoenixAiStore.Gen.Migration do
  @shortdoc "Generates PhoenixAI.Store Ecto migration"

  @moduledoc """
  Generates a migration file for the PhoenixAI.Store conversations and messages tables.

      $ mix phoenix_ai_store.gen.migration

  ## Options

    * `--prefix` - Table name prefix (default: `phoenix_ai_store_`)
    * `--migrations-path` - Output directory (default: `priv/repo/migrations`)

  """

  use Mix.Task

  @default_prefix "phoenix_ai_store_"
  @default_migrations_path "priv/repo/migrations"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [prefix: :string, migrations_path: :string]
      )

    prefix = Keyword.get(opts, :prefix, @default_prefix)
    migrations_path = Keyword.get(opts, :migrations_path, @default_migrations_path)

    File.mkdir_p!(migrations_path)

    # Check idempotency — look for existing migration
    slug = slug_from_prefix(prefix)

    existing =
      Path.wildcard(Path.join(migrations_path, "*_create_#{slug}_tables.exs"))

    if existing != [] do
      Mix.shell().info("Migration already exists: #{hd(existing)}")
      :ok
    else
      generate_migration(prefix, slug, migrations_path)
    end
  end

  defp generate_migration(prefix, slug, migrations_path) do
    template_path = find_template()
    timestamp = generate_timestamp()

    migration_module = module_from_prefix(prefix)

    repo_module = detect_repo_module()

    assigns = [
      prefix: prefix,
      migration_module: migration_module,
      repo_module: repo_module
    ]

    content = EEx.eval_file(template_path, assigns: assigns)

    filename = "#{timestamp}_create_#{slug}_tables.exs"
    filepath = Path.join(migrations_path, filename)

    Mix.Generator.create_file(filepath, content)
  end

  defp find_template do
    # Try Application.app_dir first, fall back to cwd for dev/test
    case Application.app_dir(:phoenix_ai_store, "priv/templates/migration.exs.eex") do
      path when is_binary(path) ->
        if File.exists?(path), do: path, else: fallback_template_path()
    end
  rescue
    _ -> fallback_template_path()
  end

  defp fallback_template_path do
    Path.join([File.cwd!(), "priv", "templates", "migration.exs.eex"])
  end

  defp generate_timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()

    "#{pad(y, 4)}#{pad(m, 2)}#{pad(d, 2)}#{pad(hh, 2)}#{pad(mm, 2)}#{pad(ss, 2)}"
  end

  defp pad(i, count) do
    i
    |> Integer.to_string()
    |> String.pad_leading(count, "0")
  end

  defp slug_from_prefix(prefix) do
    prefix |> String.trim_trailing("_")
  end

  defp module_from_prefix(prefix) do
    prefix
    |> String.trim_trailing("_")
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end

  defp detect_repo_module do
    case Application.get_env(:phoenix_ai_store, :ecto_repos) do
      [repo | _] -> inspect(repo)
      _ -> "MyApp.Repo"
    end
  end
end
