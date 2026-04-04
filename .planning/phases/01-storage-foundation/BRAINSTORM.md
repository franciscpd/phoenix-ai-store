# Phase 1: Storage Foundation — Design Spec

**Created:** 2026-04-03
**Status:** Approved
**Approach:** Unified Adapter + Facade Pattern (Oban-style)

## Architecture Overview

PhoenixAI.Store follows the Oban pattern: a supervised process tree with a public facade module that delegates to pluggable adapter backends. The facade handles cross-cutting concerns (UUID generation, timestamps, soft delete, telemetry) while adapters are laser-focused on I/O.

```
PhoenixAI.Store (Supervisor + Public API Facade)
├── PhoenixAI.Store.Instance (GenServer — config, adapter ref, name registry)
└── PhoenixAI.Store.Adapters.ETS.TableOwner (GenServer, conditional — only for InMemory)
```

**Key architectural decisions:**
- Supervised process tree — developer adds `{PhoenixAI.Store, opts}` to their supervision tree
- Single behaviour with all 8 callbacks — simple, testable, one contract
- Facade absorbs cross-cutting logic — adapters stay thin
- Multi-instance support via named stores

## Module Structure

```
lib/
├── phoenix_ai/
│   └── store.ex                          # Public API facade + Supervisor
│
└── phoenix_ai/store/
    ├── adapter.ex                        # @behaviour — 8 callbacks
    ├── conversation.ex                   # Struct + conversion to/from PhoenixAI.Conversation
    ├── message.ex                        # Struct + conversion to/from PhoenixAI.Message
    ├── config.ex                         # NimbleOptions schema + resolution
    ├── instance.ex                       # GenServer — per-instance state
    │
    ├── adapters/
    │   ├── ets.ex                        # InMemory adapter (Adapter implementation)
    │   ├── ets/
    │   │   └── table_owner.ex            # GenServer that owns the ETS table
    │   └── ecto.ex                       # Ecto adapter (entire module wrapped in
    │                                     #   if Code.ensure_loaded?(Ecto) do ... end)
    │
    ├── schemas/                          # Ecto schemas (also compile-time guarded)
    │   ├── conversation.ex               # Ecto schema for conversations table
    │   └── message.ex                    # Ecto schema for messages table
    │
    └── mix/
        └── tasks/
            └── phoenix_ai_store.gen.migration.ex   # Migration generator mix task
```

## Adapter Behaviour

```elixir
defmodule PhoenixAI.Store.Adapter do
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

**Semantics:**
- `save_conversation` is upsert — if ID exists, update; if not, create
- `load_conversation` returns `{:error, :not_found}` for missing conversations
- `delete_conversation` returns `:ok` on success (load before delete if you need the data)
- All callbacks receive `opts` as last argument for per-call config (repo, prefix, etc.)
- `list_conversations` filters: `user_id`, `tags`, date range, `limit`, `offset`

## Data Structs

### PhoenixAI.Store.Conversation

```elixir
@type t :: %__MODULE__{
  id: String.t() | nil,
  user_id: String.t() | nil,
  title: String.t() | nil,
  tags: [String.t()],
  model: String.t() | nil,
  messages: [PhoenixAI.Store.Message.t()],
  metadata: map(),
  deleted_at: DateTime.t() | nil,
  inserted_at: DateTime.t() | nil,
  updated_at: DateTime.t() | nil
}

defstruct [
  :id, :user_id, :title, :model, :deleted_at,
  :inserted_at, :updated_at,
  tags: [], messages: [], metadata: %{}
]
```

Provides `to_phoenix_ai/1` and `from_phoenix_ai/2` conversion functions for interop with `PhoenixAI.Conversation` stub.

### PhoenixAI.Store.Message

```elixir
@type t :: %__MODULE__{
  id: String.t() | nil,
  conversation_id: String.t() | nil,
  role: :system | :user | :assistant | :tool,
  content: String.t() | nil,
  tool_call_id: String.t() | nil,
  tool_calls: [map()] | nil,
  metadata: map(),
  token_count: non_neg_integer() | nil,
  inserted_at: DateTime.t() | nil
}

defstruct [
  :id, :conversation_id, :role, :content,
  :tool_call_id, :tool_calls, :inserted_at,
  token_count: nil, metadata: %{}
]
```

- `token_count` is pre-calculated at insertion time — used by Memory strategies (Phase 3) without re-counting
- Provides `to_phoenix_ai/1` and `from_phoenix_ai/1` conversion functions for `PhoenixAI.Message`

### UUID v7 Generation

Since minimum Elixir is 1.15 (no native UUID v7), use `uniq` library (`{:uniq, "~> 0.6"}`) which provides `Uniq.UUID.uuid7/0`. This is a lightweight dependency (~100 LOC, no native code) used by several Hex packages. The facade generates UUIDs, not adapters.

## Ecto Schemas & Migration

### Tables

```
{prefix}conversations
├── id          (uuid, PK)          — UUID v7
├── user_id     (string, nullable)  — configurable requirement
├── title       (string, nullable)
├── tags        (array of string)   — GIN indexed
├── model       (string, nullable)  — AI model used
├── metadata    (jsonb, default {})
├── deleted_at  (utc_datetime_usec, nullable) — soft delete
├── inserted_at (utc_datetime_usec)
└── updated_at  (utc_datetime_usec)

{prefix}messages
├── id              (uuid, PK)          — UUID v7
├── conversation_id (uuid, FK)          — references conversations, on_delete: :delete_all
├── role            (string)            — system/user/assistant/tool
├── content         (text, nullable)
├── tool_call_id    (string, nullable)
├── tool_calls      (jsonb, nullable)   — array of tool call objects
├── token_count     (integer, nullable)
├── metadata        (jsonb, default {})
└── inserted_at     (utc_datetime_usec)
```

### Indexes

**conversations:** `user_id`, `tags` (GIN), `inserted_at`, `deleted_at`
**messages:** `conversation_id`, `(conversation_id, inserted_at)` composite

### Migration Generator

- `mix phoenix_ai_store.gen.migration` generates a single migration file with all tables
- Accepts `--prefix` flag for table name prefix override (default: `phoenix_ai_store_`)
- Idempotent — checks if migration already exists by base name before generating
- Uses `Mix.Generator` following the Oban pattern

## Supervision Tree & Configuration

### Usage

```elixir
# In application.ex — Ecto adapter:
children = [
  MyApp.Repo,
  {PhoenixAI.Store,
    name: :main_store,
    adapter: PhoenixAI.Store.Adapters.Ecto,
    repo: MyApp.Repo,
    prefix: "ai_",
    soft_delete: true,
    user_id_required: false}
]

# InMemory adapter (dev/test):
children = [
  {PhoenixAI.Store,
    name: :test_store,
    adapter: PhoenixAI.Store.Adapters.ETS}
]
```

### Internal Structure

```
PhoenixAI.Store (Supervisor, strategy: :one_for_one)
├── PhoenixAI.Store.Instance (GenServer)
│   — holds: adapter module, resolved config, store name
│   — registered via the :name option
└── PhoenixAI.Store.Adapters.ETS.TableOwner (GenServer, conditional)
    — only started when adapter is ETS
    — owns the ETS table, handles cleanup on termination
```

### Config Resolution (NimbleOptions)

Priority order:
1. Per-instance opts (from `start_link/1`) — highest priority
2. Global config (`config :phoenix_ai, :store, [...]`) — fallback
3. NimbleOptions defaults — lowest priority

Validation happens at `init/1` — fails fast with clear error messages. Invalid config never reaches runtime.

## Public API (Facade)

```elixir
defmodule PhoenixAI.Store do
  # Conversation API
  def save_conversation(conversation, opts \\ [])
  def load_conversation(id, opts \\ [])
  def list_conversations(filters \\ [], opts \\ [])
  def delete_conversation(id, opts \\ [])
  def count_conversations(filters \\ [], opts \\ [])
  def conversation_exists?(id, opts \\ [])

  # Message API
  def add_message(conversation_id, message, opts \\ [])
  def get_messages(conversation_id, opts \\ [])
end
```

### Facade Responsibilities (cross-cutting, NOT in adapter)

- Generate UUID v7 for new conversations/messages (when `id` is nil)
- Inject `inserted_at`/`updated_at` timestamps
- Apply soft delete logic (filter `deleted_at != nil`, or set `deleted_at` on delete)
- Resolve which adapter instance to delegate to (default `:main_store` or `opts[:store]`)
- Emit telemetry spans: `[:phoenix_ai_store, :conversation, :save|:load|:delete|...]`
- Validate public API opts via NimbleOptions

### Multi-instance Usage

```elixir
# Default store (first started, or named :default)
PhoenixAI.Store.save_conversation(conv)

# Named store
PhoenixAI.Store.save_conversation(conv, store: :secondary)
```

## Optional Ecto Pattern

The entire Ecto adapter module is wrapped in a compile-time guard:

```elixir
if Code.ensure_loaded?(Ecto) do
  defmodule PhoenixAI.Store.Adapters.Ecto do
    @behaviour PhoenixAI.Store.Adapter
    # ... implementation
  end
end
```

The same guard applies to all files in `schemas/`. This ensures the library compiles cleanly with `--no-optional-deps` (CI verification required).

## Testing Strategy

- **InMemory adapter**: used as the default test adapter — no DB setup needed for unit tests
- **Ecto adapter**: integration tests against Postgres (and optionally SQLite) via a test Repo
- **Behaviour contract tests**: shared test suite that runs against ANY adapter implementation — ensures all adapters satisfy the same contract
- **Mox**: for mocking the Adapter behaviour in consumer tests

---

*Phase: 01-storage-foundation*
*Design approved: 2026-04-03*
