# Phase 1: Storage Foundation — Verification

**Verified:** 2026-04-03
**Status:** PASSED

## Test Suite

```
91 tests, 0 failures
Finished in 0.2 seconds
```

**Evidence:** `mix test` — full output reviewed, exit code 0.

## Formatting

```
mix format --check-formatted → CLEAN (exit 0)
```

## Optional Ecto Compilation

```
mix compile --no-optional-deps --warnings-as-errors → Compiles cleanly (exit 0)
```

Ecto-guarded modules (`schemas/`, `adapters/ecto.ex`) correctly excluded when Ecto is absent.

## Requirements Checklist

| Requirement | Description | Evidence | Status |
|-------------|-------------|----------|--------|
| **STOR-01** | Custom backend via Store behaviour | `lib/phoenix_ai/store/adapter.ex` — 8 `@callback` definitions. Shared `AdapterContractTest` verifies any implementation. | ✓ |
| **STOR-02** | Ecto adapter for Postgres/SQLite | `lib/phoenix_ai/store/adapters/ecto.ex` — 14 contract tests pass against Postgres on port 5434. Dynamic table source respects configurable prefix. | ✓ |
| **STOR-03** | ETS-backed InMemory adapter | `lib/phoenix_ai/store/adapters/ets.ex` — 17 contract tests pass. TableOwner GenServer owns ETS table with supervised lifecycle. | ✓ |
| **STOR-04** | Migration generator via mix task | `lib/mix/tasks/phoenix_ai_store.gen.migration.ex` — 3 tests (generation, custom prefix, idempotency). EEx template at `priv/templates/migration.exs.eex`. | ✓ |
| **STOR-05** | Conversation struct with persistence fields | `lib/phoenix_ai/store/conversation.ex` — id, user_id, title, tags, model, metadata, deleted_at, inserted_at, updated_at. Conversion to/from `PhoenixAI.Conversation`. | ✓ |
| **STOR-06** | List with pagination and filtering | Both adapters: `user_id`, `tags`, `limit`, `offset`, `inserted_after`, `inserted_before` filters. Tested in contract tests. | ✓ |
| **STOR-07** | Conversation metadata | Named columns (title, tags array, model) + JSONB `metadata` field for arbitrary custom data. | ✓ |
| **INTG-05** | NimbleOptions config validation | `lib/phoenix_ai/store/config.ex` — `validate!/1` and `resolve/1` with 6 config options. 10 tests covering validation, defaults, and global merge. | ✓ |

## Code Review Issues — All Resolved

| # | Issue | Severity | Resolution |
|---|-------|----------|------------|
| 1 | Prefix hardcoded in Ecto schemas | Critical | Ecto adapter uses dynamic source via `conv_source(opts)` / `msg_source(opts)` — prefix applied at query time |
| 2 | Double config validation | Critical | Instance GenServer skips re-validation when config is already resolved by Supervisor |
| 3 | ETS adapter overrides facade UUIDs/timestamps | Critical | Adapter respects pre-set values from facade, only fills nil fields |
| 4 | Soft delete not implemented | Important | Facade sets `deleted_at` on delete when `soft_delete: true`, filters soft-deleted in list/load |
| 5 | Telemetry not emitted | Important | All 8 facade functions emit `:telemetry.span/3` events (`[:phoenix_ai_store, ...]`) |
| 6 | `user_id_required` not enforced | Important | Facade returns `{:error, :user_id_required}` when configured and `user_id` is nil |
| 7 | Facade doesn't set `conversation_id` | Important | `add_message/3` now sets `conversation_id` on the message struct before delegating |
| 8 | `count_conversations` O(n) in ETS | Important | Comment added documenting intentional simplicity for dev/test adapter |
| 9 | Date range filter missing | Important | `inserted_after` / `inserted_before` filters added to both adapters |
| 10 | Typo `§` in moduledoc | Suggestion | Removed |
| 11 | ETS table name collision | Suggestion | TableOwner uses unique atom per instance from `:name` opt |
| 12-13 | Missing test coverage | Suggestion | 7 tests added: tags filtering, limit/offset, date range, soft delete, user_id_required, telemetry |

## Test Breakdown

| Category | Count | Files |
|----------|-------|-------|
| Conversation struct | 7 | `test/phoenix_ai/store/conversation_test.exs` |
| Message struct | 6 | `test/phoenix_ai/store/message_test.exs` |
| Config | 10 | `test/phoenix_ai/store/config_test.exs` |
| ETS TableOwner | 3 | `test/phoenix_ai/store/adapters/ets/table_owner_test.exs` |
| ETS adapter (contract) | 17 | `test/phoenix_ai/store/adapters/ets_test.exs` |
| Ecto adapter (contract) | 14 | `test/phoenix_ai/store/adapters/ecto_test.exs` |
| Instance GenServer | 5 | `test/phoenix_ai/store/instance_test.exs` |
| Store facade (integration) | 23 | `test/phoenix_ai/store_test.exs` |
| Migration generator | 3 | `test/mix/tasks/phoenix_ai_store.gen.migration_test.exs` |
| **Total** | **91** | |

## Architecture Summary

```
PhoenixAI.Store (Supervisor + Public API Facade)
├── PhoenixAI.Store.Instance (GenServer — config, adapter ref)
└── PhoenixAI.Store.Adapters.ETS.TableOwner (GenServer, conditional)

Facade responsibilities: UUID v7 generation, timestamps, soft delete, telemetry spans, user_id validation
Adapters: pure I/O — ETS (dev/test) and Ecto (production)
Config: NimbleOptions with global + per-instance merge
```

## Infrastructure

- Postgres container: `phoenix_ai_store_postgres` on port **5434**
- Test database: `phoenix_ai_store_test`

---

*Phase: 01-storage-foundation*
*Verified: 2026-04-03*
