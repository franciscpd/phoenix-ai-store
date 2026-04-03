# Phase 1: Storage Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 01-storage-foundation
**Areas discussed:** Conversation schema, Adapter behaviour API, Migration strategy, Project bootstrap

---

## Conversation Schema

| Option | Description | Selected |
|--------|-------------|----------|
| JSONB embed | Messages as JSONB array in conversation column — atomic saves, no joins, simpler | |
| Separate table | Messages table with FK to conversation — queryable by role, content, timestamps | ✓ |
| Both (JSONB + cache) | JSONB as source of truth + materialized views for advanced queries | |

**User's choice:** Separate table
**Notes:** Better for Event Log and Memory strategies downstream

---

| Option | Description | Selected |
|--------|-------------|----------|
| Always with user_id | user_id required — simplifies queries | |
| user_id optional | Supports anonymous conversations | |
| Configurable | Developer chooses via config | ✓ |

**User's choice:** Configurable

---

| Option | Description | Selected |
|--------|-------------|----------|
| UUID v7 | Sortable by timestamp, good for cursor pagination | ✓ |
| UUID v4 | Standard Ecto, random | |
| Bigint auto-increment | Classic, performant, sortable | |

**User's choice:** UUID v7

---

| Option | Description | Selected |
|--------|-------------|----------|
| utc_datetime_usec | UTC with microseconds — maximum precision | ✓ |
| utc_datetime | UTC without microseconds | |
| You decide | Claude chooses | |

**User's choice:** utc_datetime_usec

---

| Option | Description | Selected |
|--------|-------------|----------|
| JSONB livre | Free-form metadata JSONB column | |
| Campos + JSONB | Specific columns (title, tags, model) + JSONB for extras | ✓ |
| You decide | Claude chooses | |

**User's choice:** Campos + JSONB (title, tags array, model + metadata JSONB)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Hard delete | delete_conversation removes permanently | |
| Soft delete | deleted_at timestamp, filter by default | |
| Configurable | Developer chooses via config | ✓ |

**User's choice:** Configurable

---

## Adapter Behaviour API

| Option | Description | Selected |
|--------|-------------|----------|
| Only 4 basic | save, load, list, delete | |
| Add update | 5 callbacks: save (create), update (partial), load, list, delete | |
| Add count + exists? | 6 callbacks: basic 4 + count_conversations + conversation_exists? | ✓ |

**User's choice:** 6 callbacks with count + exists?

---

| Option | Description | Selected |
|--------|-------------|----------|
| Upsert | If ID exists, update. If not, create. | ✓ |
| Create + Update separate | save creates, update modifies | |
| You decide | Claude chooses | |

**User's choice:** Upsert

---

| Option | Description | Selected |
|--------|-------------|----------|
| {:error, :not_found} | Explicit error for missing conversation | ✓ |
| {:ok, nil} | Soft return | |
| You decide | Claude chooses | |

**User's choice:** {:error, :not_found}

---

| Option | Description | Selected |
|--------|-------------|----------|
| Conversation-level only | Adapter only knows conversations | |
| Both levels | Adapter has add_message/get_messages too | ✓ |

**User's choice:** Both levels (conversation + message callbacks)

---

## Migration Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Single migration | One migration with all tables (Oban pattern) | ✓ |
| Multiple separate | One migration per table | |
| Versioned | Incremental migrations per lib version | |

**User's choice:** Single migration

---

| Option | Description | Selected |
|--------|-------------|----------|
| phoenix_ai_store_* | Full prefix | |
| ai_* | Short prefix | |
| Configurable | Developer chooses prefix | ✓ |

**User's choice:** Configurable prefix

---

## Project Bootstrap

| Option | Description | Selected |
|--------|-------------|----------|
| PhoenixAI.Store | Namespaced under PhoenixAI family | ✓ |
| PhoenixAIStore | Independent namespace | |

**User's choice:** PhoenixAI.Store

---

| Option | Description | Selected |
|--------|-------------|----------|
| Elixir >= 1.18 | Native UUID v7, modern features | |
| Elixir >= 1.15 | Match PhoenixAI constraint | ✓ |
| You decide | Claude chooses | |

**User's choice:** Elixir >= 1.15

---

| Option | Description | Selected |
|--------|-------------|----------|
| Config global | config :phoenix_ai, :store in config.exs | |
| Per-instance | start_link with options | |
| Both | Global default + per-instance override | ✓ |

**User's choice:** Both

---

| Option | Description | Selected |
|--------|-------------|----------|
| MIT | Standard permissive | ✓ |
| Apache 2.0 | Enterprise standard | |
| You decide | Claude chooses | |

**User's choice:** MIT

---

## Claude's Discretion

- NimbleOptions schema structure
- Internal module organization
- Test structure and helpers
- ExDoc configuration

## Deferred Ideas

None — discussion stayed within phase scope
