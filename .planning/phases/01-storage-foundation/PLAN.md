# Phase 1: Storage Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the core storage contract — Adapter behaviour, Conversation/Message structs, InMemory (ETS) + Ecto adapters, migration generator, and NimbleOptions configuration — as a supervised Elixir hex package.

**Architecture:** Oban-style supervised facade. `PhoenixAI.Store` is both a Supervisor and the public API facade. It delegates to pluggable adapter backends while handling cross-cutting concerns (UUID v7 generation, timestamps, soft delete, telemetry). Single `Adapter` behaviour with 8 callbacks.

**Tech Stack:** Elixir >= 1.15, OTP >= 26, Ecto ~> 3.13 (optional), NimbleOptions ~> 1.1, Telemetry ~> 1.3, Uniq ~> 0.6 (UUID v7), Jason ~> 1.4

---

## File Structure

```
phoenix_ai_store/
├── mix.exs
├── .formatter.exs
├── .gitignore
├── LICENSE
├── README.md
├── lib/
│   ├── phoenix_ai/
│   │   └── store.ex                                    # Supervisor + public API facade
│   └── phoenix_ai/store/
│       ├── adapter.ex                                  # @behaviour — 8 callbacks
│       ├── conversation.ex                             # Struct + PhoenixAI conversion
│       ├── message.ex                                  # Struct + PhoenixAI conversion
│       ├── config.ex                                   # NimbleOptions schema + resolution
│       ├── instance.ex                                 # GenServer — per-instance state
│       ├── adapters/
│       │   ├── ets.ex                                  # InMemory adapter
│       │   └── ets/
│       │       └── table_owner.ex                      # GenServer ETS table owner
│       ├── adapters/
│       │   └── ecto.ex                                 # Ecto adapter (compile-time guarded)
│       └── schemas/
│           ├── conversation.ex                         # Ecto schema (compile-time guarded)
│           └── message.ex                              # Ecto schema (compile-time guarded)
├── lib/mix/tasks/
│   └── phoenix_ai_store.gen.migration.ex               # Migration generator
├── test/
│   ├── test_helper.exs
│   ├── support/
│   │   ├── repo.ex                                     # Test Ecto Repo
│   │   ├── migrations/                                 # Test migrations
│   │   │   └── 20260403000000_create_store_tables.exs
│   │   └── adapter_contract_test.ex                    # Shared contract tests
│   ├── phoenix_ai/store/
│   │   ├── conversation_test.exs
│   │   ├── message_test.exs
│   │   ├── config_test.exs
│   │   ├── instance_test.exs
│   │   └── adapters/
│   │       ├── ets_test.exs
│   │       └── ecto_test.exs
│   ├── phoenix_ai/store_test.exs                       # Facade integration tests
│   └── mix/tasks/
│       └── phoenix_ai_store.gen.migration_test.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   └── test.exs
└── priv/
    └── templates/
        └── migration.exs.eex                          # Migration template
```

---

### Task 1: Project Bootstrap

**Files:**
- Create: `mix.exs`
- Create: `.formatter.exs`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `config/config.exs`
- Create: `config/dev.exs`
- Create: `config/test.exs`
- Create: `test/test_helper.exs`

- [ ] **Step 1: Create mix.exs**

```elixir
# mix.exs
defmodule PhoenixAI.Store.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/franciscpd/phoenix-ai-store"

  def project do
    [
      app: :phoenix_ai_store,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description: "Persistence, memory management, guardrails, and cost tracking for PhoenixAI conversations",
      package: package(),
      name: "PhoenixAI.Store",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_ai, "~> 0.1"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:uniq, "~> 0.6"},

      # Optional — Ecto adapter
      {:ecto, "~> 3.13", optional: true},
      {:ecto_sql, "~> 3.13", optional: true},
      {:postgrex, "~> 0.19", optional: true},

      # Dev/Test
      {:mox, "~> 1.2", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "PhoenixAI.Store",
      extras: ["README.md"]
    ]
  end
end
```

- [ ] **Step 2: Create .formatter.exs**

```elixir
# .formatter.exs
[
  import_deps: [:ecto],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
```

- [ ] **Step 3: Create .gitignore**

```
# .gitignore
/_build/
/cover/
/deps/
/doc/
/.fetch
erl_crash.dump
*.ez
*.beam
/tmp/
*.db
*.db-journal
*.db-wal
```

- [ ] **Step 4: Create LICENSE**

MIT License file with current year and Francisco's name.

- [ ] **Step 5: Create config files**

```elixir
# config/config.exs
import Config
import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs
import Config
```

```elixir
# config/test.exs
import Config

config :phoenix_ai_store, PhoenixAI.Store.Test.Repo,
  database: "phoenix_ai_store_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :phoenix_ai_store, ecto_repos: [PhoenixAI.Store.Test.Repo]
```

- [ ] **Step 6: Create test_helper.exs**

```elixir
# test/test_helper.exs
ExUnit.start()

# Start the test repo for Ecto adapter tests
{:ok, _} = PhoenixAI.Store.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(PhoenixAI.Store.Test.Repo, :manual)
```

- [ ] **Step 7: Create test Repo**

```elixir
# test/support/repo.ex
defmodule PhoenixAI.Store.Test.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_ai_store,
    adapter: Ecto.Adapters.Postgres
end
```

- [ ] **Step 8: Run mix deps.get and verify compilation**

Run: `cd /home/franciscpd/Projects/opensource/phoenix-ai-store && mix deps.get && mix compile`
Expected: Compilation succeeds with no errors.

- [ ] **Step 9: Commit**

```bash
git add mix.exs .formatter.exs .gitignore LICENSE config/ test/test_helper.exs test/support/repo.ex
git commit -m "chore: bootstrap phoenix_ai_store hex package"
```

---

### Task 2: Data Structs — Conversation & Message

**Files:**
- Create: `lib/phoenix_ai/store/conversation.ex`
- Create: `lib/phoenix_ai/store/message.ex`
- Test: `test/phoenix_ai/store/conversation_test.exs`
- Test: `test/phoenix_ai/store/message_test.exs`

- [ ] **Step 1: Write Conversation struct test**

```elixir
# test/phoenix_ai/store/conversation_test.exs
defmodule PhoenixAI.Store.ConversationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Conversation

  describe "struct" do
    test "creates with defaults" do
      conv = %Conversation{}
      assert conv.id == nil
      assert conv.user_id == nil
      assert conv.title == nil
      assert conv.tags == []
      assert conv.model == nil
      assert conv.messages == []
      assert conv.metadata == %{}
      assert conv.deleted_at == nil
      assert conv.inserted_at == nil
      assert conv.updated_at == nil
    end

    test "creates with fields" do
      conv = %Conversation{
        id: "conv-123",
        user_id: "user-1",
        title: "Test conversation",
        tags: ["support", "billing"],
        model: "gpt-4o",
        metadata: %{"priority" => "high"}
      }

      assert conv.id == "conv-123"
      assert conv.user_id == "user-1"
      assert conv.tags == ["support", "billing"]
      assert conv.metadata == %{"priority" => "high"}
    end
  end

  describe "to_phoenix_ai/1" do
    test "converts to PhoenixAI.Conversation" do
      msg = %PhoenixAI.Store.Message{role: :user, content: "Hello"}

      conv = %Conversation{
        id: "conv-1",
        messages: [msg],
        metadata: %{"key" => "value"}
      }

      phoenix_conv = Conversation.to_phoenix_ai(conv)

      assert %PhoenixAI.Conversation{} = phoenix_conv
      assert phoenix_conv.id == "conv-1"
      assert length(phoenix_conv.messages) == 1
      assert phoenix_conv.metadata == %{"key" => "value"}
    end
  end

  describe "from_phoenix_ai/2" do
    test "converts from PhoenixAI.Conversation" do
      phoenix_conv = %PhoenixAI.Conversation{
        id: "conv-1",
        messages: [%PhoenixAI.Message{role: :user, content: "Hi"}],
        metadata: %{}
      }

      conv = Conversation.from_phoenix_ai(phoenix_conv)

      assert %Conversation{} = conv
      assert conv.id == "conv-1"
      assert length(conv.messages) == 1
      assert %PhoenixAI.Store.Message{} = hd(conv.messages)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/conversation_test.exs`
Expected: FAIL — module `PhoenixAI.Store.Conversation` not found.

- [ ] **Step 3: Implement Conversation struct**

```elixir
# lib/phoenix_ai/store/conversation.ex
defmodule PhoenixAI.Store.Conversation do
  @moduledoc """
  Represents a persisted AI conversation with messages and metadata.

  This struct is owned by PhoenixAI.Store and includes persistence-specific
  fields (user_id, timestamps, soft delete) that the core PhoenixAI.Conversation
  stub does not have.

  ## Conversion

  Convert to/from `PhoenixAI.Conversation` for interop with PhoenixAI.Agent:

      store_conv = PhoenixAI.Store.Conversation.from_phoenix_ai(phoenix_conv)
      phoenix_conv = PhoenixAI.Store.Conversation.to_phoenix_ai(store_conv)
  """

  alias PhoenixAI.Store.Message

  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          title: String.t() | nil,
          tags: [String.t()],
          model: String.t() | nil,
          messages: [Message.t()],
          metadata: map(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :title,
    :model,
    :deleted_at,
    :inserted_at,
    :updated_at,
    tags: [],
    messages: [],
    metadata: %{}
  ]

  @doc "Converts a Store Conversation to a PhoenixAI.Conversation."
  @spec to_phoenix_ai(t()) :: PhoenixAI.Conversation.t()
  def to_phoenix_ai(%__MODULE__{} = conv) do
    %PhoenixAI.Conversation{
      id: conv.id,
      messages: Enum.map(conv.messages, &Message.to_phoenix_ai/1),
      metadata: conv.metadata
    }
  end

  @doc "Converts a PhoenixAI.Conversation to a Store Conversation."
  @spec from_phoenix_ai(PhoenixAI.Conversation.t(), keyword()) :: t()
  def from_phoenix_ai(%PhoenixAI.Conversation{} = conv, opts \\ []) do
    %__MODULE__{
      id: conv.id,
      messages: Enum.map(conv.messages, &Message.from_phoenix_ai/1),
      metadata: conv.metadata,
      user_id: Keyword.get(opts, :user_id),
      title: Keyword.get(opts, :title),
      tags: Keyword.get(opts, :tags, []),
      model: Keyword.get(opts, :model)
    }
  end
end
```

- [ ] **Step 4: Write Message struct test**

```elixir
# test/phoenix_ai/store/message_test.exs
defmodule PhoenixAI.Store.MessageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Message

  describe "struct" do
    test "creates with defaults" do
      msg = %Message{}
      assert msg.id == nil
      assert msg.role == nil
      assert msg.content == nil
      assert msg.token_count == nil
      assert msg.metadata == %{}
    end

    test "creates with fields" do
      msg = %Message{
        role: :user,
        content: "Hello",
        token_count: 5,
        metadata: %{"source" => "web"}
      }

      assert msg.role == :user
      assert msg.content == "Hello"
      assert msg.token_count == 5
    end
  end

  describe "to_phoenix_ai/1" do
    test "converts to PhoenixAI.Message" do
      msg = %Message{
        role: :assistant,
        content: "Hi there!",
        tool_calls: [%{"id" => "tc-1", "name" => "weather"}]
      }

      phoenix_msg = Message.to_phoenix_ai(msg)

      assert %PhoenixAI.Message{} = phoenix_msg
      assert phoenix_msg.role == :assistant
      assert phoenix_msg.content == "Hi there!"
      assert phoenix_msg.tool_calls == [%{"id" => "tc-1", "name" => "weather"}]
    end
  end

  describe "from_phoenix_ai/1" do
    test "converts from PhoenixAI.Message" do
      phoenix_msg = %PhoenixAI.Message{
        role: :user,
        content: "Hello",
        metadata: %{"source" => "api"}
      }

      msg = Message.from_phoenix_ai(phoenix_msg)

      assert %Message{} = msg
      assert msg.role == :user
      assert msg.content == "Hello"
      assert msg.metadata == %{"source" => "api"}
    end
  end
end
```

- [ ] **Step 5: Implement Message struct**

```elixir
# lib/phoenix_ai/store/message.ex
defmodule PhoenixAI.Store.Message do
  @moduledoc """
  Represents a single message within a conversation.

  Wraps `PhoenixAI.Message` with persistence fields (id, conversation_id,
  token_count, timestamps).
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          conversation_id: String.t() | nil,
          role: :system | :user | :assistant | :tool | nil,
          content: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [map()] | nil,
          metadata: map(),
          token_count: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :conversation_id,
    :role,
    :content,
    :tool_call_id,
    :tool_calls,
    :inserted_at,
    token_count: nil,
    metadata: %{}
  ]

  @doc "Converts a Store Message to a PhoenixAI.Message."
  @spec to_phoenix_ai(t()) :: PhoenixAI.Message.t()
  def to_phoenix_ai(%__MODULE__{} = msg) do
    %PhoenixAI.Message{
      role: msg.role,
      content: msg.content,
      tool_call_id: msg.tool_call_id,
      tool_calls: msg.tool_calls,
      metadata: msg.metadata
    }
  end

  @doc "Converts a PhoenixAI.Message to a Store Message."
  @spec from_phoenix_ai(PhoenixAI.Message.t()) :: t()
  def from_phoenix_ai(%PhoenixAI.Message{} = msg) do
    %__MODULE__{
      role: msg.role,
      content: msg.content,
      tool_call_id: msg.tool_call_id,
      tool_calls: msg.tool_calls,
      metadata: msg.metadata
    }
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/conversation_test.exs test/phoenix_ai/store/message_test.exs`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/store/conversation.ex lib/phoenix_ai/store/message.ex test/phoenix_ai/store/conversation_test.exs test/phoenix_ai/store/message_test.exs
git commit -m "feat(store): add Conversation and Message structs with PhoenixAI conversion"
```

---

### Task 3: Adapter Behaviour & Config

**Files:**
- Create: `lib/phoenix_ai/store/adapter.ex`
- Create: `lib/phoenix_ai/store/config.ex`
- Test: `test/phoenix_ai/store/config_test.exs`

- [ ] **Step 1: Write Config test**

```elixir
# test/phoenix_ai/store/config_test.exs
defmodule PhoenixAI.Store.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Config

  describe "validate!/1" do
    test "accepts valid ETS config" do
      opts = Config.validate!(adapter: PhoenixAI.Store.Adapters.ETS, name: :test)
      assert opts[:adapter] == PhoenixAI.Store.Adapters.ETS
      assert opts[:name] == :test
    end

    test "applies defaults" do
      opts = Config.validate!(adapter: PhoenixAI.Store.Adapters.ETS, name: :test)
      assert opts[:prefix] == "phoenix_ai_store_"
      assert opts[:soft_delete] == false
      assert opts[:user_id_required] == false
    end

    test "raises on missing required fields" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.validate!(name: :test)
      end
    end

    test "raises on invalid adapter" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.validate!(adapter: "not_a_module", name: :test)
      end
    end
  end

  describe "resolve/1" do
    test "merges per-instance opts over global config" do
      # Global config is read from Application env
      Application.put_env(:phoenix_ai_store, :defaults, prefix: "global_", soft_delete: true)

      opts = Config.resolve(adapter: PhoenixAI.Store.Adapters.ETS, name: :test, prefix: "local_")
      assert opts[:prefix] == "local_"
      assert opts[:soft_delete] == true

      Application.delete_env(:phoenix_ai_store, :defaults)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/config_test.exs`
Expected: FAIL — modules not found.

- [ ] **Step 3: Implement Adapter behaviour**

```elixir
# lib/phoenix_ai/store/adapter.ex
defmodule PhoenixAI.Store.Adapter do
  @moduledoc """
  Behaviour for storage backends.

  Implement all 8 callbacks to create a custom adapter. See
  `PhoenixAI.Store.Adapters.ETS` for a reference implementation.
  """

  alias PhoenixAI.Store.{Conversation, Message}

  # --- Conversation-level ---

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

  # --- Message-level ---

  @callback add_message(conversation_id :: String.t(), Message.t(), opts :: keyword()) ::
              {:ok, Message.t()} | {:error, term()}

  @callback get_messages(conversation_id :: String.t(), opts :: keyword()) ::
              {:ok, [Message.t()]} | {:error, term()}
end
```

- [ ] **Step 4: Implement Config module**

```elixir
# lib/phoenix_ai/store/config.ex
defmodule PhoenixAI.Store.Config do
  @moduledoc """
  Configuration schema and resolution for PhoenixAI.Store.

  Options are validated via NimbleOptions at init time.
  """

  @schema NimbleOptions.new!([
    name: [
      type: :atom,
      required: true,
      doc: "Unique name for this store instance."
    ],
    adapter: [
      type: :atom,
      required: true,
      doc: "Adapter module implementing `PhoenixAI.Store.Adapter`."
    ],
    repo: [
      type: :atom,
      doc: "Ecto Repo module. Required when using the Ecto adapter."
    ],
    prefix: [
      type: :string,
      default: "phoenix_ai_store_",
      doc: "Table name prefix for Ecto schemas."
    ],
    soft_delete: [
      type: :boolean,
      default: false,
      doc: "Use soft delete (deleted_at) instead of hard delete."
    ],
    user_id_required: [
      type: :boolean,
      default: false,
      doc: "Require user_id on all conversations."
    ]
  ])

  @doc "Validates options against the schema. Raises on invalid config."
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    NimbleOptions.validate!(opts, @schema)
  end

  @doc """
  Resolves configuration by merging:
  1. Per-instance opts (highest priority)
  2. Global Application env defaults
  3. NimbleOptions defaults (lowest priority)
  """
  @spec resolve(keyword()) :: keyword()
  def resolve(instance_opts) do
    global = Application.get_env(:phoenix_ai_store, :defaults, [])

    global
    |> Keyword.merge(instance_opts)
    |> validate!()
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/config_test.exs`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/adapter.ex lib/phoenix_ai/store/config.ex test/phoenix_ai/store/config_test.exs
git commit -m "feat(store): add Adapter behaviour and Config module with NimbleOptions"
```

---

### Task 4: ETS Table Owner GenServer

**Files:**
- Create: `lib/phoenix_ai/store/adapters/ets/table_owner.ex`
- Test: `test/phoenix_ai/store/adapters/ets/table_owner_test.exs`

- [ ] **Step 1: Write TableOwner test**

```elixir
# test/phoenix_ai/store/adapters/ets/table_owner_test.exs
defmodule PhoenixAI.Store.Adapters.ETS.TableOwnerTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Adapters.ETS.TableOwner

  describe "start_link/1" do
    test "starts and creates ETS table" do
      {:ok, pid} = TableOwner.start_link(name: :test_table_owner_1)
      assert Process.alive?(pid)

      table = TableOwner.table(pid)
      assert :ets.info(table) != :undefined

      GenServer.stop(pid)
    end
  end

  describe "table/1" do
    test "returns the ETS table reference" do
      {:ok, pid} = TableOwner.start_link(name: :test_table_owner_2)
      table = TableOwner.table(pid)

      :ets.insert(table, {"key", "value"})
      assert :ets.lookup(table, "key") == [{"key", "value"}]

      GenServer.stop(pid)
    end
  end

  describe "cleanup on termination" do
    test "ETS table is deleted when owner stops" do
      {:ok, pid} = TableOwner.start_link(name: :test_table_owner_3)
      table = TableOwner.table(pid)
      assert :ets.info(table) != :undefined

      GenServer.stop(pid)
      Process.sleep(10)
      assert :ets.info(table) == :undefined
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/adapters/ets/table_owner_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement TableOwner**

```elixir
# lib/phoenix_ai/store/adapters/ets/table_owner.ex
defmodule PhoenixAI.Store.Adapters.ETS.TableOwner do
  @moduledoc """
  GenServer that owns the ETS table for the InMemory adapter.

  The table survives caller crashes because the GenServer — not the
  caller — is the owner process. The table is deleted when this
  process terminates.
  """

  use GenServer

  @doc "Starts the table owner process."
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the ETS table reference."
  @spec table(GenServer.server()) :: :ets.table()
  def table(server) do
    GenServer.call(server, :table)
  end

  @impl GenServer
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :phoenix_ai_store_ets)

    table =
      :ets.new(table_name, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call(:table, _from, state) do
    {:reply, state.table, state}
  end

  @impl GenServer
  def terminate(_reason, %{table: table}) do
    if :ets.info(table) != :undefined do
      :ets.delete(table)
    end

    :ok
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/adapters/ets/table_owner_test.exs`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets/table_owner.ex test/phoenix_ai/store/adapters/ets/table_owner_test.exs
git commit -m "feat(store): add ETS TableOwner GenServer"
```

---

### Task 5: ETS InMemory Adapter

**Files:**
- Create: `lib/phoenix_ai/store/adapters/ets.ex`
- Create: `test/support/adapter_contract_test.ex`
- Test: `test/phoenix_ai/store/adapters/ets_test.exs`

- [ ] **Step 1: Write shared adapter contract test module**

```elixir
# test/support/adapter_contract_test.ex
defmodule PhoenixAI.Store.AdapterContractTest do
  @moduledoc """
  Shared test cases for any Adapter implementation.
  Use with `use PhoenixAI.Store.AdapterContractTest, adapter: MyAdapter`.
  """

  defmacro __using__(opts) do
    quote do
      use ExUnit.Case

      @adapter unquote(opts[:adapter])
      @setup_fn unquote(opts[:setup_fn])

      setup do
        if @setup_fn, do: @setup_fn.()
        opts = if @setup_fn, do: @setup_fn.(), else: []
        {:ok, opts: opts}
      end

      alias PhoenixAI.Store.{Conversation, Message}

      describe "#{inspect(@adapter)} save_conversation/2" do
        test "saves and loads a conversation", %{opts: opts} do
          conv = %Conversation{
            id: Uniq.UUID.uuid7(),
            user_id: "user-1",
            title: "Test",
            tags: ["test"],
            model: "gpt-4o",
            metadata: %{"key" => "value"}
          }

          assert {:ok, saved} = @adapter.save_conversation(conv, opts)
          assert saved.id == conv.id
          assert saved.title == "Test"

          assert {:ok, loaded} = @adapter.load_conversation(conv.id, opts)
          assert loaded.id == conv.id
          assert loaded.title == "Test"
          assert loaded.tags == ["test"]
          assert loaded.metadata == %{"key" => "value"}
        end

        test "upserts existing conversation", %{opts: opts} do
          id = Uniq.UUID.uuid7()
          conv = %Conversation{id: id, title: "Original"}

          assert {:ok, _} = @adapter.save_conversation(conv, opts)
          assert {:ok, _} = @adapter.save_conversation(%{conv | title: "Updated"}, opts)
          assert {:ok, loaded} = @adapter.load_conversation(id, opts)
          assert loaded.title == "Updated"
        end
      end

      describe "#{inspect(@adapter)} load_conversation/2" do
        test "returns error for missing conversation", %{opts: opts} do
          assert {:error, :not_found} = @adapter.load_conversation("nonexistent", opts)
        end
      end

      describe "#{inspect(@adapter)} delete_conversation/2" do
        test "deletes an existing conversation", %{opts: opts} do
          conv = %Conversation{id: Uniq.UUID.uuid7(), title: "To delete"}
          assert {:ok, _} = @adapter.save_conversation(conv, opts)
          assert :ok = @adapter.delete_conversation(conv.id, opts)
          assert {:error, :not_found} = @adapter.load_conversation(conv.id, opts)
        end

        test "returns error for missing conversation", %{opts: opts} do
          assert {:error, :not_found} = @adapter.delete_conversation("nonexistent", opts)
        end
      end

      describe "#{inspect(@adapter)} list_conversations/2" do
        test "lists conversations", %{opts: opts} do
          conv1 = %Conversation{id: Uniq.UUID.uuid7(), user_id: "user-1"}
          conv2 = %Conversation{id: Uniq.UUID.uuid7(), user_id: "user-2"}
          @adapter.save_conversation(conv1, opts)
          @adapter.save_conversation(conv2, opts)

          assert {:ok, list} = @adapter.list_conversations([], opts)
          assert length(list) >= 2
        end

        test "filters by user_id", %{opts: opts} do
          conv1 = %Conversation{id: Uniq.UUID.uuid7(), user_id: "filter-user"}
          conv2 = %Conversation{id: Uniq.UUID.uuid7(), user_id: "other-user"}
          @adapter.save_conversation(conv1, opts)
          @adapter.save_conversation(conv2, opts)

          assert {:ok, list} = @adapter.list_conversations([user_id: "filter-user"], opts)
          assert Enum.all?(list, &(&1.user_id == "filter-user"))
        end
      end

      describe "#{inspect(@adapter)} count_conversations/2" do
        test "counts conversations", %{opts: opts} do
          conv = %Conversation{id: Uniq.UUID.uuid7()}
          @adapter.save_conversation(conv, opts)

          assert {:ok, count} = @adapter.count_conversations([], opts)
          assert is_integer(count) and count >= 1
        end
      end

      describe "#{inspect(@adapter)} conversation_exists?/2" do
        test "returns true for existing conversation", %{opts: opts} do
          conv = %Conversation{id: Uniq.UUID.uuid7()}
          @adapter.save_conversation(conv, opts)

          assert {:ok, true} = @adapter.conversation_exists?(conv.id, opts)
        end

        test "returns false for missing conversation", %{opts: opts} do
          assert {:ok, false} = @adapter.conversation_exists?("nonexistent", opts)
        end
      end

      describe "#{inspect(@adapter)} add_message/3 and get_messages/2" do
        test "adds and retrieves messages", %{opts: opts} do
          conv = %Conversation{id: Uniq.UUID.uuid7()}
          @adapter.save_conversation(conv, opts)

          msg = %Message{role: :user, content: "Hello"}
          assert {:ok, saved_msg} = @adapter.add_message(conv.id, msg, opts)
          assert saved_msg.role == :user
          assert saved_msg.content == "Hello"
          assert saved_msg.id != nil

          assert {:ok, messages} = @adapter.get_messages(conv.id, opts)
          assert length(messages) == 1
          assert hd(messages).content == "Hello"
        end

        test "returns messages in insertion order", %{opts: opts} do
          conv = %Conversation{id: Uniq.UUID.uuid7()}
          @adapter.save_conversation(conv, opts)

          @adapter.add_message(conv.id, %Message{role: :user, content: "First"}, opts)
          @adapter.add_message(conv.id, %Message{role: :assistant, content: "Second"}, opts)
          @adapter.add_message(conv.id, %Message{role: :user, content: "Third"}, opts)

          assert {:ok, messages} = @adapter.get_messages(conv.id, opts)
          assert Enum.map(messages, & &1.content) == ["First", "Second", "Third"]
        end
      end
    end
  end
end
```

- [ ] **Step 2: Write ETS adapter test using contract**

```elixir
# test/phoenix_ai/store/adapters/ets_test.exs
defmodule PhoenixAI.Store.Adapters.ETSTest do
  alias PhoenixAI.Store.Adapters.ETS.TableOwner

  setup do
    {:ok, pid} = TableOwner.start_link(name: :"table_owner_#{:erlang.unique_integer([:positive])}")
    table = TableOwner.table(pid)

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    {:ok, opts: [table: table]}
  end

  use PhoenixAI.Store.AdapterContractTest,
    adapter: PhoenixAI.Store.Adapters.ETS,
    setup_fn: nil
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs`
Expected: FAIL — `PhoenixAI.Store.Adapters.ETS` not found.

- [ ] **Step 4: Implement ETS adapter**

```elixir
# lib/phoenix_ai/store/adapters/ets.ex
defmodule PhoenixAI.Store.Adapters.ETS do
  @moduledoc """
  InMemory storage adapter backed by ETS.

  Suitable for development, testing, and production workloads
  that don't need durability across node restarts.
  """

  @behaviour PhoenixAI.Store.Adapter

  alias PhoenixAI.Store.{Conversation, Message}

  # --- Conversation-level ---

  @impl true
  def save_conversation(%Conversation{} = conv, opts) do
    table = Keyword.fetch!(opts, :table)
    now = DateTime.utc_now()

    conv =
      case :ets.lookup(table, {:conversation, conv.id}) do
        [{_, existing}] ->
          %{conv | inserted_at: existing.inserted_at, updated_at: now}

        [] ->
          %{conv | inserted_at: conv.inserted_at || now, updated_at: now}
      end

    :ets.insert(table, {{:conversation, conv.id}, conv})
    {:ok, conv}
  end

  @impl true
  def load_conversation(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_, conv}] ->
        {:ok, messages} = get_messages(id, opts)
        {:ok, %{conv | messages: messages}}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_conversations(filters, opts) do
    table = Keyword.fetch!(opts, :table)

    conversations =
      :ets.foldl(
        fn
          {{:conversation, _id}, conv}, acc -> [conv | acc]
          _, acc -> acc
        end,
        [],
        table
      )
      |> apply_filters(filters)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    {:ok, conversations}
  end

  @impl true
  def delete_conversation(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_, _}] ->
        :ets.delete(table, {:conversation, id})
        delete_messages_for_conversation(table, id)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def count_conversations(filters, opts) do
    {:ok, conversations} = list_conversations(filters, opts)
    {:ok, length(conversations)}
  end

  @impl true
  def conversation_exists?(id, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, id}) do
      [{_, _}] -> {:ok, true}
      [] -> {:ok, false}
    end
  end

  # --- Message-level ---

  @impl true
  def add_message(conversation_id, %Message{} = msg, opts) do
    table = Keyword.fetch!(opts, :table)

    case :ets.lookup(table, {:conversation, conversation_id}) do
      [{_, _}] ->
        msg = %{
          msg
          | id: msg.id || Uniq.UUID.uuid7(),
            conversation_id: conversation_id,
            inserted_at: msg.inserted_at || DateTime.utc_now()
        }

        key = {:message, conversation_id, msg.id}
        :ets.insert(table, {key, msg})
        {:ok, msg}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def get_messages(conversation_id, opts) do
    table = Keyword.fetch!(opts, :table)

    messages =
      :ets.foldl(
        fn
          {{:message, ^conversation_id, _msg_id}, msg}, acc -> [msg | acc]
          _, acc -> acc
        end,
        [],
        table
      )
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:ok, messages}
  end

  # --- Private ---

  defp apply_filters(conversations, []), do: conversations

  defp apply_filters(conversations, [{:user_id, user_id} | rest]) do
    conversations
    |> Enum.filter(&(&1.user_id == user_id))
    |> apply_filters(rest)
  end

  defp apply_filters(conversations, [{:tags, tags} | rest]) when is_list(tags) do
    conversations
    |> Enum.filter(fn conv ->
      Enum.any?(tags, &(&1 in conv.tags))
    end)
    |> apply_filters(rest)
  end

  defp apply_filters(conversations, [{:limit, limit} | rest]) do
    conversations
    |> Enum.take(limit)
    |> apply_filters(rest)
  end

  defp apply_filters(conversations, [{:offset, offset} | rest]) do
    conversations
    |> Enum.drop(offset)
    |> apply_filters(rest)
  end

  defp apply_filters(conversations, [_ | rest]) do
    apply_filters(conversations, rest)
  end

  defp delete_messages_for_conversation(table, conversation_id) do
    :ets.foldl(
      fn
        {{:message, ^conversation_id, _} = key, _}, acc -> [key | acc]
        _, acc -> acc
      end,
      [],
      table
    )
    |> Enum.each(&:ets.delete(table, &1))
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/adapters/ets_test.exs`
Expected: All contract tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ets.ex test/support/adapter_contract_test.ex test/phoenix_ai/store/adapters/ets_test.exs
git commit -m "feat(store): add ETS InMemory adapter with shared contract tests"
```

---

### Task 6: Instance GenServer

**Files:**
- Create: `lib/phoenix_ai/store/instance.ex`
- Test: `test/phoenix_ai/store/instance_test.exs`

- [ ] **Step 1: Write Instance test**

```elixir
# test/phoenix_ai/store/instance_test.exs
defmodule PhoenixAI.Store.InstanceTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Store.Instance

  describe "start_link/1" do
    test "starts with valid config" do
      {:ok, pid} =
        Instance.start_link(
          name: :"instance_test_#{:erlang.unique_integer([:positive])}",
          adapter: PhoenixAI.Store.Adapters.ETS
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "get_config/1" do
    test "returns resolved config" do
      name = :"instance_config_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Instance.start_link(
          name: name,
          adapter: PhoenixAI.Store.Adapters.ETS,
          prefix: "custom_"
        )

      config = Instance.get_config(pid)
      assert config[:adapter] == PhoenixAI.Store.Adapters.ETS
      assert config[:prefix] == "custom_"

      GenServer.stop(pid)
    end
  end

  describe "get_adapter_opts/1" do
    test "returns opts for adapter calls" do
      name = :"instance_adapter_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Instance.start_link(
          name: name,
          adapter: PhoenixAI.Store.Adapters.ETS
        )

      opts = Instance.get_adapter_opts(pid)
      assert Keyword.has_key?(opts, :table)

      GenServer.stop(pid)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/instance_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement Instance GenServer**

```elixir
# lib/phoenix_ai/store/instance.ex
defmodule PhoenixAI.Store.Instance do
  @moduledoc """
  GenServer that holds per-instance store state: adapter, resolved config,
  and adapter-specific resources (e.g., ETS table reference).
  """

  use GenServer

  alias PhoenixAI.Store.{Config, Adapters}

  @doc "Starts the instance process."
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the resolved config for this instance."
  @spec get_config(GenServer.server()) :: keyword()
  def get_config(server) do
    GenServer.call(server, :get_config)
  end

  @doc "Returns opts to pass to adapter callback calls."
  @spec get_adapter_opts(GenServer.server()) :: keyword()
  def get_adapter_opts(server) do
    GenServer.call(server, :get_adapter_opts)
  end

  @impl GenServer
  def init(opts) do
    config = Config.resolve(opts)
    adapter = config[:adapter]

    adapter_opts = build_adapter_opts(adapter, config)

    {:ok, %{config: config, adapter: adapter, adapter_opts: adapter_opts}}
  end

  @impl GenServer
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_call(:get_adapter_opts, _from, state) do
    {:reply, state.adapter_opts, state}
  end

  defp build_adapter_opts(PhoenixAI.Store.Adapters.ETS, config) do
    table_owner = :"#{config[:name]}_table_owner"
    table = PhoenixAI.Store.Adapters.ETS.TableOwner.table(table_owner)
    [table: table]
  end

  defp build_adapter_opts(_adapter, config) do
    Keyword.take(config, [:repo, :prefix, :soft_delete])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store/instance_test.exs`
Expected: All tests PASS (ETS adapter tests need TableOwner started — Instance handles this).

Note: The Instance test for ETS adapter requires the TableOwner to be started first. We'll need to adjust the test setup or the Instance to start the TableOwner itself. This will be resolved in Task 7 when we wire the Supervisor.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/store/instance.ex test/phoenix_ai/store/instance_test.exs
git commit -m "feat(store): add Instance GenServer for per-store state"
```

---

### Task 7: Store Supervisor & Public API Facade

**Files:**
- Create: `lib/phoenix_ai/store.ex`
- Test: `test/phoenix_ai/store_test.exs`

- [ ] **Step 1: Write facade integration test**

```elixir
# test/phoenix_ai/store_test.exs
defmodule PhoenixAI.StoreTest do
  use ExUnit.Case

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}

  setup do
    name = :"store_test_#{:erlang.unique_integer([:positive])}"

    {:ok, _pid} =
      Store.start_link(
        name: name,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

    {:ok, store: name}
  end

  describe "save_conversation/2" do
    test "saves with auto-generated UUID and timestamps", %{store: store} do
      conv = %Conversation{title: "New conversation"}
      assert {:ok, saved} = Store.save_conversation(conv, store: store)
      assert saved.id != nil
      assert saved.inserted_at != nil
      assert saved.updated_at != nil
    end

    test "preserves existing ID on save", %{store: store} do
      conv = %Conversation{id: "my-custom-id", title: "Custom"}
      assert {:ok, saved} = Store.save_conversation(conv, store: store)
      assert saved.id == "my-custom-id"
    end
  end

  describe "load_conversation/2" do
    test "loads a saved conversation with messages", %{store: store} do
      conv = %Conversation{title: "With messages"}
      {:ok, saved} = Store.save_conversation(conv, store: store)

      Store.add_message(saved.id, %Message{role: :user, content: "Hello"}, store: store)
      Store.add_message(saved.id, %Message{role: :assistant, content: "Hi!"}, store: store)

      {:ok, loaded} = Store.load_conversation(saved.id, store: store)
      assert loaded.title == "With messages"
      assert length(loaded.messages) == 2
    end

    test "returns error for nonexistent", %{store: store} do
      assert {:error, :not_found} = Store.load_conversation("nope", store: store)
    end
  end

  describe "delete_conversation/2" do
    test "hard deletes by default", %{store: store} do
      conv = %Conversation{title: "Delete me"}
      {:ok, saved} = Store.save_conversation(conv, store: store)
      assert :ok = Store.delete_conversation(saved.id, store: store)
      assert {:error, :not_found} = Store.load_conversation(saved.id, store: store)
    end
  end

  describe "list_conversations/2" do
    test "lists all conversations", %{store: store} do
      Store.save_conversation(%Conversation{title: "One"}, store: store)
      Store.save_conversation(%Conversation{title: "Two"}, store: store)

      {:ok, list} = Store.list_conversations([], store: store)
      assert length(list) >= 2
    end
  end

  describe "count_conversations/2" do
    test "counts conversations", %{store: store} do
      Store.save_conversation(%Conversation{title: "Count me"}, store: store)
      {:ok, count} = Store.count_conversations([], store: store)
      assert count >= 1
    end
  end

  describe "conversation_exists?/2" do
    test "returns true/false", %{store: store} do
      {:ok, saved} = Store.save_conversation(%Conversation{title: "Exists"}, store: store)
      assert {:ok, true} = Store.conversation_exists?(saved.id, store: store)
      assert {:ok, false} = Store.conversation_exists?("nope", store: store)
    end
  end

  describe "add_message/3" do
    test "adds message with auto ID and timestamp", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Chat"}, store: store)

      {:ok, msg} =
        Store.add_message(conv.id, %Message{role: :user, content: "Hey"}, store: store)

      assert msg.id != nil
      assert msg.conversation_id == conv.id
      assert msg.inserted_at != nil
    end
  end

  describe "get_messages/2" do
    test "returns messages in order", %{store: store} do
      {:ok, conv} = Store.save_conversation(%Conversation{title: "Chat"}, store: store)
      Store.add_message(conv.id, %Message{role: :user, content: "A"}, store: store)
      Store.add_message(conv.id, %Message{role: :assistant, content: "B"}, store: store)

      {:ok, msgs} = Store.get_messages(conv.id, store: store)
      assert Enum.map(msgs, & &1.content) == ["A", "B"]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store_test.exs`
Expected: FAIL — `PhoenixAI.Store` module not found.

- [ ] **Step 3: Implement Store Supervisor + Facade**

```elixir
# lib/phoenix_ai/store.ex
defmodule PhoenixAI.Store do
  @moduledoc """
  Persistence, memory management, guardrails, and cost tracking
  for PhoenixAI conversations.

  ## Setup

      # In your application supervisor:
      children = [
        {PhoenixAI.Store,
          name: :my_store,
          adapter: PhoenixAI.Store.Adapters.ETS}
      ]

  ## Usage

      alias PhoenixAI.Store
      alias PhoenixAI.Store.{Conversation, Message}

      {:ok, conv} = Store.save_conversation(%Conversation{title: "Chat"})
      {:ok, msg} = Store.add_message(conv.id, %Message{role: :user, content: "Hello"})
      {:ok, loaded} = Store.load_conversation(conv.id)
  """

  use Supervisor

  alias PhoenixAI.Store.{Config, Conversation, Instance, Message}

  @default_store :phoenix_ai_store_default

  # --- Supervisor ---

  @doc "Starts the Store supervision tree."
  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_store)
    config = Config.resolve(opts)
    Supervisor.start_link(__MODULE__, config, name: supervisor_name(name))
  end

  @impl Supervisor
  def init(config) do
    name = config[:name]
    adapter = config[:adapter]

    children =
      adapter_children(adapter, config) ++
        [
          {Instance, config}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # --- Conversation API ---

  @doc "Saves (upserts) a conversation."
  @spec save_conversation(Conversation.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def save_conversation(%Conversation{} = conv, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    now = DateTime.utc_now()

    conv = %{
      conv
      | id: conv.id || Uniq.UUID.uuid7(),
        inserted_at: conv.inserted_at || now,
        updated_at: now
    }

    adapter.save_conversation(conv, adapter_opts)
  end

  @doc "Loads a conversation by ID."
  @spec load_conversation(String.t(), keyword()) ::
          {:ok, Conversation.t()} | {:error, :not_found | term()}
  def load_conversation(id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.load_conversation(id, adapter_opts)
  end

  @doc "Lists conversations with optional filters."
  @spec list_conversations(keyword(), keyword()) ::
          {:ok, [Conversation.t()]} | {:error, term()}
  def list_conversations(filters \\ [], opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.list_conversations(filters, adapter_opts)
  end

  @doc "Deletes a conversation by ID."
  @spec delete_conversation(String.t(), keyword()) ::
          :ok | {:error, :not_found | term()}
  def delete_conversation(id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.delete_conversation(id, adapter_opts)
  end

  @doc "Counts conversations matching optional filters."
  @spec count_conversations(keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_conversations(filters \\ [], opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.count_conversations(filters, adapter_opts)
  end

  @doc "Checks if a conversation exists."
  @spec conversation_exists?(String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def conversation_exists?(id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.conversation_exists?(id, adapter_opts)
  end

  # --- Message API ---

  @doc "Adds a message to a conversation."
  @spec add_message(String.t(), Message.t(), keyword()) ::
          {:ok, Message.t()} | {:error, term()}
  def add_message(conversation_id, %Message{} = msg, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)

    msg = %{
      msg
      | id: msg.id || Uniq.UUID.uuid7(),
        conversation_id: conversation_id,
        inserted_at: msg.inserted_at || DateTime.utc_now()
    }

    adapter.add_message(conversation_id, msg, adapter_opts)
  end

  @doc "Gets all messages for a conversation."
  @spec get_messages(String.t(), keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def get_messages(conversation_id, opts \\ []) do
    {adapter, adapter_opts} = resolve_adapter(opts)
    adapter.get_messages(conversation_id, adapter_opts)
  end

  # --- Private ---

  defp resolve_adapter(opts) do
    store = Keyword.get(opts, :store, @default_store)
    config = Instance.get_config(store)
    adapter_opts = Instance.get_adapter_opts(store)
    {config[:adapter], adapter_opts}
  end

  defp supervisor_name(name), do: :"#{name}_supervisor"

  defp adapter_children(PhoenixAI.Store.Adapters.ETS, config) do
    table_owner_name = :"#{config[:name]}_table_owner"
    [{PhoenixAI.Store.Adapters.ETS.TableOwner, name: table_owner_name}]
  end

  defp adapter_children(_adapter, _config), do: []
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/store_test.exs`
Expected: All facade integration tests PASS.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store.ex test/phoenix_ai/store_test.exs
git commit -m "feat(store): add Store Supervisor and public API facade"
```

---

### Task 8: Ecto Schemas (Compile-Time Guarded)

**Files:**
- Create: `lib/phoenix_ai/store/schemas/conversation.ex`
- Create: `lib/phoenix_ai/store/schemas/message.ex`

- [ ] **Step 1: Implement Ecto Conversation schema**

```elixir
# lib/phoenix_ai/store/schemas/conversation.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Conversation do
    @moduledoc """
    Ecto schema for the conversations table.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.Schemas.Message, as: MessageSchema

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [type: :utc_datetime_usec]

    schema "phoenix_ai_store_conversations" do
      field :user_id, :string
      field :title, :string
      field :tags, {:array, :string}, default: []
      field :model, :string
      field :metadata, :map, default: %{}
      field :deleted_at, :utc_datetime_usec

      has_many :messages, MessageSchema, foreign_key: :conversation_id

      timestamps()
    end

    @required_fields []
    @optional_fields [:id, :user_id, :title, :tags, :model, :metadata, :deleted_at]

    @doc false
    def changeset(conversation, attrs) do
      conversation
      |> cast(attrs, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
    end

    @doc "Converts Ecto schema to Store struct."
    def to_store_struct(%__MODULE__{} = schema) do
      %PhoenixAI.Store.Conversation{
        id: schema.id,
        user_id: schema.user_id,
        title: schema.title,
        tags: schema.tags || [],
        model: schema.model,
        metadata: schema.metadata || %{},
        deleted_at: schema.deleted_at,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at,
        messages:
          case schema.messages do
            %Ecto.Association.NotLoaded{} -> []
            msgs -> Enum.map(msgs, &MessageSchema.to_store_struct/1)
          end
      }
    end

    @doc "Converts Store struct to Ecto attrs map."
    def from_store_struct(%PhoenixAI.Store.Conversation{} = conv) do
      %{
        id: conv.id,
        user_id: conv.user_id,
        title: conv.title,
        tags: conv.tags,
        model: conv.model,
        metadata: conv.metadata,
        deleted_at: conv.deleted_at
      }
    end
  end
end
```

- [ ] **Step 2: Implement Ecto Message schema**

```elixir
# lib/phoenix_ai/store/schemas/message.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Schemas.Message do
    @moduledoc """
    Ecto schema for the messages table.
    """

    use Ecto.Schema
    import Ecto.Changeset

    alias PhoenixAI.Store.Schemas.Conversation, as: ConversationSchema

    @primary_key {:id, :binary_id, autogenerate: false}
    @timestamps_opts [inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec]

    schema "phoenix_ai_store_messages" do
      field :role, :string
      field :content, :string
      field :tool_call_id, :string
      field :tool_calls, {:array, :map}
      field :token_count, :integer
      field :metadata, :map, default: %{}

      belongs_to :conversation, ConversationSchema, type: :binary_id

      timestamps()
    end

    @required_fields [:role, :conversation_id]
    @optional_fields [:id, :content, :tool_call_id, :tool_calls, :token_count, :metadata]

    @doc false
    def changeset(message, attrs) do
      message
      |> cast(attrs, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
      |> validate_inclusion(:role, ~w(system user assistant tool))
      |> foreign_key_constraint(:conversation_id)
    end

    @doc "Converts Ecto schema to Store struct."
    def to_store_struct(%__MODULE__{} = schema) do
      %PhoenixAI.Store.Message{
        id: schema.id,
        conversation_id: schema.conversation_id,
        role: String.to_existing_atom(schema.role),
        content: schema.content,
        tool_call_id: schema.tool_call_id,
        tool_calls: schema.tool_calls,
        token_count: schema.token_count,
        metadata: schema.metadata || %{},
        inserted_at: schema.inserted_at
      }
    end

    @doc "Converts Store struct to Ecto attrs map."
    def from_store_struct(%PhoenixAI.Store.Message{} = msg) do
      %{
        id: msg.id,
        conversation_id: msg.conversation_id,
        role: to_string(msg.role),
        content: msg.content,
        tool_call_id: msg.tool_call_id,
        tool_calls: msg.tool_calls,
        token_count: msg.token_count,
        metadata: msg.metadata
      }
    end
  end
end
```

- [ ] **Step 3: Verify compilation with Ecto present**

Run: `mix compile`
Expected: Compiles with no errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/store/schemas/conversation.ex lib/phoenix_ai/store/schemas/message.ex
git commit -m "feat(store): add Ecto schemas for conversations and messages (compile-time guarded)"
```

---

### Task 9: Ecto Adapter

**Files:**
- Create: `lib/phoenix_ai/store/adapters/ecto.ex`
- Create: `test/support/migrations/20260403000000_create_store_tables.exs`
- Test: `test/phoenix_ai/store/adapters/ecto_test.exs`

- [ ] **Step 1: Create test migration**

```elixir
# test/support/migrations/20260403000000_create_store_tables.exs
defmodule PhoenixAI.Store.Test.Repo.Migrations.CreateStoreTables do
  use Ecto.Migration

  def change do
    create table(:phoenix_ai_store_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string
      add :title, :string
      add :tags, {:array, :string}, default: []
      add :model, :string
      add :metadata, :map, default: %{}
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:phoenix_ai_store_conversations, [:user_id])
    create index(:phoenix_ai_store_conversations, [:tags], using: "GIN")
    create index(:phoenix_ai_store_conversations, [:inserted_at])
    create index(:phoenix_ai_store_conversations, [:deleted_at])

    create table(:phoenix_ai_store_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:phoenix_ai_store_conversations,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :role, :string, null: false
      add :content, :text
      add :tool_call_id, :string
      add :tool_calls, {:array, :map}
      add :token_count, :integer
      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    create index(:phoenix_ai_store_messages, [:conversation_id])
    create index(:phoenix_ai_store_messages, [:conversation_id, :inserted_at])
  end
end
```

- [ ] **Step 2: Write Ecto adapter test using contract**

```elixir
# test/phoenix_ai/store/adapters/ecto_test.exs
defmodule PhoenixAI.Store.Adapters.EctoTest do
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PhoenixAI.Store.Test.Repo)
    {:ok, opts: [repo: PhoenixAI.Store.Test.Repo, prefix: "phoenix_ai_store_"]}
  end

  use PhoenixAI.Store.AdapterContractTest,
    adapter: PhoenixAI.Store.Adapters.Ecto,
    setup_fn: nil
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/phoenix_ai/store/adapters/ecto_test.exs`
Expected: FAIL — `PhoenixAI.Store.Adapters.Ecto` not found.

- [ ] **Step 4: Implement Ecto adapter**

```elixir
# lib/phoenix_ai/store/adapters/ecto.ex
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Adapters.Ecto do
    @moduledoc """
    Ecto-backed storage adapter for PostgreSQL and SQLite.

    Requires a Repo module passed via the `:repo` option.
    """

    @behaviour PhoenixAI.Store.Adapter

    import Ecto.Query

    alias PhoenixAI.Store.{Conversation, Message}
    alias PhoenixAI.Store.Schemas.Conversation, as: ConvSchema
    alias PhoenixAI.Store.Schemas.Message, as: MsgSchema

    # --- Conversation-level ---

    @impl true
    def save_conversation(%Conversation{} = conv, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = ConvSchema.from_store_struct(conv)

      result =
        case repo.get(ConvSchema, conv.id) do
          nil ->
            %ConvSchema{}
            |> ConvSchema.changeset(attrs)
            |> repo.insert()

          existing ->
            existing
            |> ConvSchema.changeset(attrs)
            |> repo.update()
        end

      case result do
        {:ok, schema} -> {:ok, ConvSchema.to_store_struct(schema)}
        {:error, changeset} -> {:error, changeset}
      end
    end

    @impl true
    def load_conversation(id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.get(ConvSchema, id) do
        nil ->
          {:error, :not_found}

        schema ->
          schema = repo.preload(schema, messages: from(m in MsgSchema, order_by: [asc: m.inserted_at]))
          {:ok, ConvSchema.to_store_struct(schema)}
      end
    end

    @impl true
    def list_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      query =
        ConvSchema
        |> apply_ecto_filters(filters)
        |> order_by([c], desc: c.inserted_at)

      {:ok, repo.all(query) |> Enum.map(&ConvSchema.to_store_struct/1)}
    end

    @impl true
    def delete_conversation(id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.get(ConvSchema, id) do
        nil -> {:error, :not_found}
        schema ->
          repo.delete(schema)
          :ok
      end
    end

    @impl true
    def count_conversations(filters, opts) do
      repo = Keyword.fetch!(opts, :repo)

      count =
        ConvSchema
        |> apply_ecto_filters(filters)
        |> repo.aggregate(:count)

      {:ok, count}
    end

    @impl true
    def conversation_exists?(id, opts) do
      repo = Keyword.fetch!(opts, :repo)
      exists = repo.exists?(from(c in ConvSchema, where: c.id == ^id))
      {:ok, exists}
    end

    # --- Message-level ---

    @impl true
    def add_message(conversation_id, %Message{} = msg, opts) do
      repo = Keyword.fetch!(opts, :repo)
      attrs = MsgSchema.from_store_struct(%{msg | conversation_id: conversation_id})

      case %MsgSchema{} |> MsgSchema.changeset(attrs) |> repo.insert() do
        {:ok, schema} -> {:ok, MsgSchema.to_store_struct(schema)}
        {:error, changeset} -> {:error, changeset}
      end
    end

    @impl true
    def get_messages(conversation_id, opts) do
      repo = Keyword.fetch!(opts, :repo)

      messages =
        MsgSchema
        |> where([m], m.conversation_id == ^conversation_id)
        |> order_by([m], asc: m.inserted_at)
        |> repo.all()
        |> Enum.map(&MsgSchema.to_store_struct/1)

      {:ok, messages}
    end

    # --- Private ---

    defp apply_ecto_filters(query, []), do: query

    defp apply_ecto_filters(query, [{:user_id, user_id} | rest]) do
      query
      |> where([c], c.user_id == ^user_id)
      |> apply_ecto_filters(rest)
    end

    defp apply_ecto_filters(query, [{:tags, tags} | rest]) when is_list(tags) do
      query
      |> where([c], fragment("? && ?", c.tags, ^tags))
      |> apply_ecto_filters(rest)
    end

    defp apply_ecto_filters(query, [{:limit, limit} | rest]) do
      query
      |> limit(^limit)
      |> apply_ecto_filters(rest)
    end

    defp apply_ecto_filters(query, [{:offset, offset} | rest]) do
      query
      |> offset(^offset)
      |> apply_ecto_filters(rest)
    end

    defp apply_ecto_filters(query, [_ | rest]) do
      apply_ecto_filters(query, rest)
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix ecto.create && mix ecto.migrate && mix test test/phoenix_ai/store/adapters/ecto_test.exs`
Expected: All contract tests PASS against Postgres.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/store/adapters/ecto.ex test/support/migrations/ test/phoenix_ai/store/adapters/ecto_test.exs
git commit -m "feat(store): add Ecto adapter with Postgres support"
```

---

### Task 10: Migration Generator Mix Task

**Files:**
- Create: `lib/mix/tasks/phoenix_ai_store.gen.migration.ex`
- Create: `priv/templates/migration.exs.eex`
- Test: `test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`

- [ ] **Step 1: Write migration generator test**

```elixir
# test/mix/tasks/phoenix_ai_store.gen.migration_test.exs
defmodule Mix.Tasks.PhoenixAiStore.Gen.MigrationTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  @tmp_dir "tmp/test_migrations"

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  describe "run/1" do
    test "generates migration file" do
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
      end)

      files = File.ls!(@tmp_dir)
      assert length(files) == 1
      [filename] = files
      assert filename =~ ~r/\d+_create_phoenix_ai_store_tables\.exs/

      content = File.read!(Path.join(@tmp_dir, filename))
      assert content =~ "create table(:phoenix_ai_store_conversations"
      assert content =~ "create table(:phoenix_ai_store_messages"
      assert content =~ ":binary_id"
    end

    test "generates with custom prefix" do
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run([
          "--migrations-path", @tmp_dir,
          "--prefix", "ai_"
        ])
      end)

      [filename] = File.ls!(@tmp_dir)
      content = File.read!(Path.join(@tmp_dir, filename))
      assert content =~ "create table(:ai_conversations"
      assert content =~ "create table(:ai_messages"
    end

    test "is idempotent — does not duplicate" do
      capture_io(fn ->
        Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
      end)

      output =
        capture_io(fn ->
          Mix.Tasks.PhoenixAiStore.Gen.Migration.run(["--migrations-path", @tmp_dir])
        end)

      assert output =~ "already exists"
      assert length(File.ls!(@tmp_dir)) == 1
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Create migration EEx template**

```eex
# priv/templates/migration.exs.eex
defmodule <%= @repo_module %>.Migrations.Create<%= @migration_module %>Tables do
  use Ecto.Migration

  def change do
    create table(:<%= @prefix %>conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string
      add :title, :string
      add :tags, {:array, :string}, default: []
      add :model, :string
      add :metadata, :map, default: %{}
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:<%= @prefix %>conversations, [:user_id])
    create index(:<%= @prefix %>conversations, [:tags], using: "GIN")
    create index(:<%= @prefix %>conversations, [:inserted_at])
    create index(:<%= @prefix %>conversations, [:deleted_at])

    create table(:<%= @prefix %>messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:<%= @prefix %>conversations,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :role, :string, null: false
      add :content, :text
      add :tool_call_id, :string
      add :tool_calls, {:array, :map}
      add :token_count, :integer
      add :metadata, :map, default: %{}

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    create index(:<%= @prefix %>messages, [:conversation_id])
    create index(:<%= @prefix %>messages, [:conversation_id, :inserted_at])
  end
end
```

- [ ] **Step 4: Implement migration generator mix task**

```elixir
# lib/mix/tasks/phoenix_ai_store.gen.migration.ex
defmodule Mix.Tasks.PhoenixAiStore.Gen.Migration do
  @moduledoc """
  Generates the Ecto migration for PhoenixAI.Store tables.

      $ mix phoenix_ai_store.gen.migration
      $ mix phoenix_ai_store.gen.migration --prefix ai_

  ## Options

    * `--prefix` - Table name prefix (default: `phoenix_ai_store_`)
    * `--migrations-path` - Path for migration files (default: `priv/repo/migrations`)
  """

  use Mix.Task

  import Mix.Generator

  @shortdoc "Generates PhoenixAI.Store Ecto migration"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [prefix: :string, migrations_path: :string]
      )

    prefix = Keyword.get(opts, :prefix, "phoenix_ai_store_")
    migrations_path = Keyword.get(opts, :migrations_path, "priv/repo/migrations")

    # Check idempotency
    if migration_exists?(migrations_path) do
      Mix.shell().info("Migration already exists in #{migrations_path}. Skipping.")
      :ok
    else
      File.mkdir_p!(migrations_path)
      timestamp = generate_timestamp()
      filename = "#{timestamp}_create_#{prefix}tables.exs"
      filepath = Path.join(migrations_path, filename)

      # Determine module names from prefix
      migration_module =
        prefix
        |> String.trim_trailing("_")
        |> Macro.camelize()

      repo_module = detect_repo_module()

      assigns = [
        prefix: prefix,
        migration_module: migration_module,
        repo_module: repo_module
      ]

      template_path =
        Path.join(Application.app_dir(:phoenix_ai_store, "priv"), "templates/migration.exs.eex")

      content = EEx.eval_file(template_path, assigns: assigns)

      create_file(filepath, content)
      Mix.shell().info("Generated migration: #{filepath}")
    end
  end

  defp migration_exists?(path) do
    case File.ls(path) do
      {:ok, files} ->
        Enum.any?(files, &String.contains?(&1, "_create_"))

      {:error, _} ->
        false
    end
  end

  defp generate_timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()

    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: "#{i}"

  defp detect_repo_module do
    case Application.get_env(:phoenix_ai_store, :ecto_repos) do
      [repo | _] -> inspect(repo)
      _ -> "MyApp.Repo"
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/mix/tasks/phoenix_ai_store.gen.migration_test.exs`
Expected: All tests PASS.

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/mix/tasks/phoenix_ai_store.gen.migration.ex priv/templates/migration.exs.eex test/mix/tasks/phoenix_ai_store.gen.migration_test.exs
git commit -m "feat(store): add migration generator mix task"
```

---

### Task 11: Final Verification & Compilation Check

**Files:**
- No new files

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 2: Run formatter**

Run: `mix format --check-formatted`
Expected: No formatting issues.

- [ ] **Step 3: Run Credo**

Run: `mix credo --strict`
Expected: No issues or only minor style suggestions.

- [ ] **Step 4: Verify optional Ecto compilation**

Run: `mix compile --no-optional-deps --warnings-as-errors`
Expected: Compiles successfully — Ecto-guarded modules are skipped.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "chore(store): fix formatting and credo warnings"
```

---

## Summary

| Task | What it delivers | Commit message |
|------|------------------|----------------|
| 1 | Project bootstrap (mix.exs, config, deps) | `chore: bootstrap phoenix_ai_store hex package` |
| 2 | Conversation + Message structs with PhoenixAI conversion | `feat(store): add Conversation and Message structs` |
| 3 | Adapter behaviour (8 callbacks) + Config (NimbleOptions) | `feat(store): add Adapter behaviour and Config` |
| 4 | ETS TableOwner GenServer | `feat(store): add ETS TableOwner GenServer` |
| 5 | ETS InMemory adapter + shared contract tests | `feat(store): add ETS InMemory adapter` |
| 6 | Instance GenServer (per-store state) | `feat(store): add Instance GenServer` |
| 7 | Store Supervisor + public API facade | `feat(store): add Store Supervisor and facade` |
| 8 | Ecto schemas (compile-time guarded) | `feat(store): add Ecto schemas` |
| 9 | Ecto adapter | `feat(store): add Ecto adapter` |
| 10 | Migration generator mix task | `feat(store): add migration generator` |
| 11 | Final verification + optional Ecto check | `chore(store): fix formatting and credo warnings` |
