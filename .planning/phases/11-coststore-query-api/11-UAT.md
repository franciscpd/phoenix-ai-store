---
status: complete
phase: 11-coststore-query-api
source: [ROADMAP.md success criteria, 11-PLAN.md]
started: 2026-04-07T00:20:00Z
updated: 2026-04-07T00:22:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Global cost query without conversation_id
expected: list_cost_records([], opts) returns all cost records across conversations without requiring a conversation_id
result: pass

### 2. Filter by conversation_id
expected: list_cost_records([conversation_id: id], opts) returns only records for that conversation (replaces old get_cost_records)
result: pass

### 3. Filter by user_id, provider, model
expected: list_cost_records with :user_id, :provider, or :model filters returns matching subset
result: pass

### 4. Filter by date range
expected: list_cost_records with :after and/or :before filters scopes by recorded_at
result: pass

### 5. Cursor pagination
expected: list_cost_records with :limit returns page + next_cursor. Passing cursor to next call returns next page. Exhausted pages return nil cursor.
result: pass

### 6. Invalid cursor handling
expected: list_cost_records with garbage cursor returns {:error, :invalid_cursor} (not crash)
result: pass

### 7. count_cost_records
expected: count_cost_records(filters, opts) returns count matching filters without loading records
result: pass

### 8. Provider string normalization
expected: Passing provider as string "openai" works same as atom :openai (facade normalizes)
result: pass

### 9. Old API removed
expected: get_cost_records/2 no longer exists on CostStore behaviour or Store facade. Calling it produces undefined function error.
result: pass

## Summary

total: 9
passed: 9
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
