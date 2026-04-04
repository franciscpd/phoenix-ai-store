# Phase 4: Long-Term Memory — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Requirements:** LTM-01, LTM-02, LTM-03, LTM-04, LTM-05

## Overview

Cross-conversation long-term memory for PhoenixAI Store. Extracts key-value facts from conversations, generates AI-powered user profile summaries, and injects both as pinned system messages before memory strategies run. Built as a layer above the existing Adapter, with sub-behaviours for storage and a pluggable Extractor behaviour for custom extraction logic.

## Architecture

**Approach: LTM as a Layer Above the Adapter**

```
PhoenixAI.Store (facade — gains LTM delegations)
  └── LongTermMemory (orchestrator module)
        ├── Fact (struct)
        ├── Profile (struct)
        ├── Extractor (behaviour)
        │   └── Extractor.Default (AI-powered implementation)
        └── Injector (pure module — formats facts/profile as pinned messages)

Adapter (base — unchanged)
  ├── Adapter.FactStore (sub-behaviour)
  └── Adapter.ProfileStore (sub-behaviour)

Adapters.ETS (implements FactStore + ProfileStore)
Adapters.Ecto (implements FactStore + ProfileStore)
  └── Schemas.Fact, Schemas.Profile (Ecto schemas)
```

Separation of concerns:
- **LongTermMemory** orchestrates when/how to extract and inject
- **Adapter sub-behaviours** handle where to store
- **Extractor** handles what to extract (pluggable)
- **Injector** handles how to format for injection (pure function)

## Structs

### Fact

```elixir
defmodule PhoenixAI.Store.LongTermMemory.Fact do
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

- UUID v7 for `id` (same pattern as conversations/messages)
- Key-value simple model: `key` and `value` are both strings
- `inserted_at` / `updated_at` for audit trail
- Save is upsert: same `{user_id, key}` silently overwrites value

### Profile

```elixir
defmodule PhoenixAI.Store.LongTermMemory.Profile do
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

- Hybrid model: `summary` (free text, injected into AI calls) + `metadata` (structured map — tags, expertise_level, etc.)
- One profile per `user_id` (upsert)
- `summary` is AI-generated; `metadata` is AI-generated structured data

## Sub-Behaviours

### Adapter.FactStore

```elixir
defmodule PhoenixAI.Store.Adapter.FactStore do
  alias PhoenixAI.Store.LongTermMemory.Fact

  @callback save_fact(Fact.t(), keyword()) :: {:ok, Fact.t()} | {:error, term()}
  @callback get_facts(user_id :: String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  @callback delete_fact(user_id :: String.t(), key :: String.t(), keyword()) :: :ok | {:error, term()}
  @callback count_facts(user_id :: String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
end
```

- `save_fact/2` is upsert on `{user_id, key}`
- `count_facts/2` supports the configurable max limit check
- `get_facts/2` returns all facts for a user, ordered by `inserted_at`

### Adapter.ProfileStore

```elixir
defmodule PhoenixAI.Store.Adapter.ProfileStore do
  alias PhoenixAI.Store.LongTermMemory.Profile

  @callback save_profile(Profile.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  @callback load_profile(user_id :: String.t(), keyword()) :: {:ok, Profile.t()} | {:error, :not_found | term()}
  @callback delete_profile(user_id :: String.t(), keyword()) :: :ok | {:error, term()}
end
```

- `save_profile/2` is upsert on `user_id`
- `load_profile/2` returns `{:error, :not_found}` if no profile exists (consistent with `load_conversation`)

### Adapter Support Checking

At boot time (`start_link/1`), if `long_term_memory.enabled` is `true`:
- Check if adapter implements `FactStore` and `ProfileStore` sub-behaviours
- If not, raise `ArgumentError` with clear message about which sub-behaviour is missing

At runtime, direct calls like `extract_facts/2` also check and return `{:error, :ltm_not_supported}` if sub-behaviours are not implemented.

## Extractor

### Behaviour

```elixir
defmodule PhoenixAI.Store.LongTermMemory.Extractor do
  alias PhoenixAI.Store.Message

  @callback extract(messages :: [Message.t()], context :: map(), opts :: keyword()) ::
    {:ok, [%{key: String.t(), value: String.t()}]} | {:error, term()}
end
```

- Receives messages (only new ones since last extraction) + context map
- Returns list of `%{key: ..., value: ...}` pairs — orchestrator creates Fact structs
- Context includes: `user_id`, `conversation_id`, `provider`, `model`, existing facts

### Extractor.Default

AI-powered extraction using `AI.chat/2`:

- Prompt asks AI to identify user facts in JSON array format: `[{"key": "...", "value": "..."}]`
- Accepts `:extract_fn` in opts for test injection (same pattern as Summarization's `:summarize_fn`)
- Provider/model configurable via opts or global config
- JSON parsing with error handling for malformed AI responses

## Orchestrator: LongTermMemory

```elixir
defmodule PhoenixAI.Store.LongTermMemory do
  @moduledoc "Orchestrates fact extraction, profile updates, and context injection."

  # --- Extraction ---

  @spec extract_facts(String.t(), keyword()) :: {:ok, [Fact.t()]} | {:error, term()}
  def extract_facts(conversation_id, opts \\ [])
  # opts includes :store (instance name, default :phoenix_ai_store_default)
  # 1. Load conversation via adapter to get user_id and metadata (cursor)
  # 2. Load messages since last extraction cursor (incremental)
  # 3. Call Extractor.extract/3 with new messages + context
  # 3. For each extracted fact:
  #    a. Check count_facts against max_facts_per_user limit
  #    b. If under limit: save_fact (upsert)
  #    c. If at limit: return {:error, :limit_exceeded} for that fact, continue others
  # 4. Update extraction cursor in conversation metadata
  # 5. Return {:ok, saved_facts}
  # Mode: sync (default) or async via Task.Supervisor

  # --- Profile ---

  @spec update_profile(String.t(), keyword()) :: {:ok, Profile.t()} | {:error, term()}
  def update_profile(user_id, opts \\ [])
  # 1. Load current profile (or nil if first time)
  # 2. Load all facts for user
  # 3. Call AI with current profile + facts → new summary + metadata
  # 4. save_profile via adapter (upsert)
  # Accepts :profile_fn for test injection

  # --- Manual CRUD ---

  def save_fact(%Fact{} = fact, opts \\ [])
  def get_facts(user_id, opts \\ [])
  def delete_fact(user_id, key, opts \\ [])
  def get_profile(user_id, opts \\ [])
  def delete_profile(user_id, opts \\ [])
end
```

### Extraction Cursor

The cursor tracking "last extracted message" uses the conversation's existing `metadata` field:

```elixir
metadata["_ltm_cursor"] = last_extracted_message_id
```

- Zero schema changes — `metadata` is already a JSONB map
- Read cursor on extraction start → load messages after that ID
- Write cursor after successful extraction
- If no cursor exists, extracts from all messages (first run)

### Async Mode

When `extraction_mode: :async`:

```elixir
Task.Supervisor.async_nolink(
  PhoenixAI.Store.TaskSupervisor,
  fn -> do_extract_facts(conversation_id, opts) end
)
```

- `Task.Supervisor` started as child of the Store supervisor
- Returns `{:ok, :async}` immediately
- Facts may not be ready for the next turn — documented trade-off
- Errors logged via Logger, not propagated to caller

## Injector

```elixir
defmodule PhoenixAI.Store.LongTermMemory.Injector do
  @moduledoc "Formats facts and profile as pinned system messages."

  alias PhoenixAI.Store.{Message, LongTermMemory.Fact, LongTermMemory.Profile}

  @spec inject([Fact.t()], Profile.t() | nil, [Message.t()]) :: [Message.t()]
  def inject([], nil, messages), do: messages
  def inject(facts, profile, messages) do
    ltm_messages = []
    ltm_messages = maybe_add_profile(ltm_messages, profile)
    ltm_messages = maybe_add_facts(ltm_messages, facts)
    ltm_messages ++ messages
  end
end
```

- **Pure function** — no side effects, no IO. Receives data, returns modified message list.
- Facts formatted as single pinned system message:
  ```
  User context:
  - preferred_language: pt-BR
  - expertise: Elixir
  - timezone: America/Sao_Paulo
  ```
- Profile formatted as separate pinned system message:
  ```
  User profile:
  {summary text from Profile.summary}
  ```
- Both messages have `pinned: true`, `role: :system`
- If no facts and no profile → returns messages unchanged (noop)

## Pipeline Integration

In `PhoenixAI.Store.apply_memory/3`:

```elixir
def apply_memory(messages, pipeline, opts \\ []) do
  messages_with_ltm =
    if opts[:inject_long_term_memory] && opts[:user_id] do
      {:ok, facts} = LongTermMemory.get_facts(opts[:user_id], opts)
      profile = case LongTermMemory.get_profile(opts[:user_id], opts) do
        {:ok, p} -> p
        {:error, :not_found} -> nil
      end
      Injector.inject(facts, profile, messages)
    else
      messages
    end

  Pipeline.run(pipeline, messages_with_ltm, context, opts)
end
```

- Injection happens **before** `Pipeline.run` — facts/profile enter as pinned messages
- Pipeline's pinned extraction preserves them through all strategies
- Requires `inject_long_term_memory: true` AND `user_id` in opts

## Configuration

New NimbleOptions keys under `:long_term_memory`:

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
      doc: "When fact extraction runs."
    ],
    extraction_mode: [
      type: {:in, [:sync, :async]},
      default: :sync,
      doc: "Whether extraction blocks or runs in background."
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
    profile_provider: [type: :atom, doc: "Provider override for profile update AI calls."],
    profile_model: [type: :string, doc: "Model override for profile update AI calls."]
  ]
]
```

Boot-time validation:
- If `enabled: true`, adapter must implement `FactStore` + `ProfileStore`
- If `extraction_trigger` is `:per_turn` or `:on_close`, `enabled` must be `true`

## Ecto Migration

The migration generator (`mix phoenix_ai_store.gen.migration`) gains two new tables:

### facts table

```sql
CREATE TABLE phoenix_ai_store_facts (
  id UUID PRIMARY KEY,
  user_id VARCHAR(255) NOT NULL,
  key VARCHAR(255) NOT NULL,
  value TEXT NOT NULL,
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE UNIQUE INDEX phoenix_ai_store_facts_user_id_key_index
  ON phoenix_ai_store_facts (user_id, key);

CREATE INDEX phoenix_ai_store_facts_user_id_index
  ON phoenix_ai_store_facts (user_id);
```

### profiles table

```sql
CREATE TABLE phoenix_ai_store_profiles (
  id UUID PRIMARY KEY,
  user_id VARCHAR(255) NOT NULL UNIQUE,
  summary TEXT,
  metadata JSONB DEFAULT '{}',
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE UNIQUE INDEX phoenix_ai_store_profiles_user_id_index
  ON phoenix_ai_store_profiles (user_id);
```

Both tables use the configurable prefix (default: `phoenix_ai_store_`).

## Ecto Schemas

```elixir
# In lib/phoenix_ai/store/schemas/fact.ex
# Gated behind `if Code.ensure_loaded?(Ecto)`
defmodule PhoenixAI.Store.Schemas.Fact do
  use Ecto.Schema
  # Maps to phoenix_ai_store_facts table
  # Fields: id, user_id, key, value, inserted_at, updated_at
end

# In lib/phoenix_ai/store/schemas/profile.ex
defmodule PhoenixAI.Store.Schemas.Profile do
  use Ecto.Schema
  # Maps to phoenix_ai_store_profiles table
  # Fields: id, user_id, summary, metadata, inserted_at, updated_at
end
```

## Telemetry

New spans following existing convention:

| Event | Metadata |
|-------|----------|
| `[:phoenix_ai_store, :extract_facts, :start\|:stop\|:exception]` | `conversation_id`, `facts_count`, `mode` (sync/async) |
| `[:phoenix_ai_store, :update_profile, :start\|:stop\|:exception]` | `user_id` |
| `[:phoenix_ai_store, :inject_ltm, :start\|:stop\|:exception]` | `user_id`, `facts_count`, `has_profile` |
| `[:phoenix_ai_store, :save_fact, :start\|:stop\|:exception]` | `user_id`, `key` |
| `[:phoenix_ai_store, :delete_fact, :start\|:stop\|:exception]` | `user_id`, `key` |

## Error Handling

| Scenario | Error |
|----------|-------|
| Adapter doesn't implement FactStore | `{:error, :ltm_not_supported}` (runtime) or `ArgumentError` (boot) |
| Max facts limit reached | `{:error, :limit_exceeded}` |
| AI extraction fails | `{:error, {:extraction_failed, reason}}` |
| AI profile update fails | `{:error, {:profile_update_failed, reason}}` |
| JSON parse failure on AI response | `{:error, {:parse_error, raw_response}}` |
| No provider configured | `ArgumentError` (same as Summarization) |
| Extraction with no new messages | `{:ok, []}` (noop) |

## Testing Strategy

- **Extractor.Default:** Use `:extract_fn` to inject mock (avoid real AI calls)
- **Profile update:** Use `:profile_fn` to inject mock
- **Injector:** Pure functions — direct unit tests with fixture data
- **Sub-behaviours:** Test both ETS and Ecto implementations via adapter contract tests (extend existing `AdapterContractTest`)
- **Integration:** End-to-end test: save conversation → extract facts → update profile → inject → verify pinned messages in pipeline output
- **Async mode:** Test with `Task.Supervisor` using controlled mock that signals completion

## File Inventory

New files:
- `lib/phoenix_ai/store/long_term_memory.ex` — Orchestrator
- `lib/phoenix_ai/store/long_term_memory/fact.ex` — Fact struct
- `lib/phoenix_ai/store/long_term_memory/profile.ex` — Profile struct
- `lib/phoenix_ai/store/long_term_memory/extractor.ex` — Extractor behaviour
- `lib/phoenix_ai/store/long_term_memory/extractor/default.ex` — Default AI extractor
- `lib/phoenix_ai/store/long_term_memory/injector.ex` — Pure injection formatter
- `lib/phoenix_ai/store/adapter/fact_store.ex` — FactStore sub-behaviour
- `lib/phoenix_ai/store/adapter/profile_store.ex` — ProfileStore sub-behaviour
- `lib/phoenix_ai/store/schemas/fact.ex` — Ecto schema (gated)
- `lib/phoenix_ai/store/schemas/profile.ex` — Ecto schema (gated)

Modified files:
- `lib/phoenix_ai/store.ex` — Delegate LTM functions from facade
- `lib/phoenix_ai/store/config.ex` — Add `:long_term_memory` NimbleOptions
- `lib/phoenix_ai/store/adapters/ets.ex` — Implement FactStore + ProfileStore
- `lib/phoenix_ai/store/adapters/ecto.ex` — Implement FactStore + ProfileStore
- `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` — Add facts + profiles tables

---

*Phase: 04-long-term-memory*
*Design approved: 2026-04-04*
