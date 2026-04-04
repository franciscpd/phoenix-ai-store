---
status: complete
phase: 03-memory-strategies
source: [ROADMAP.md success criteria, BRAINSTORM.md, PLAN.md]
started: 2026-04-03T23:30:00Z
updated: 2026-04-03T23:35:00Z
---

## Current Test

[testing complete]

## Tests

### 1. SlidingWindow preserves pinned messages
expected: Apply SlidingWindow(last: 3) to a conversation with system prompt + 20 messages. Output has system prompt + 3 most recent = 4 messages total.
result: pass
evidence: Output 4 messages — system prompt (pinned) + Messages 18, 19, 20

### 2. TokenTruncation fits within budget
expected: Apply TokenTruncation(max_tokens: 25) to messages with token_count: 10 each. With 5 messages (50 tokens), only 2 newest fit (20 tokens). Output has 2 messages.
result: pass
evidence: Output 2 messages — Msg 4, Msg 5 (20 tokens ≤ 25 budget)

### 3. Custom strategy composes with built-in
expected: A custom strategy module implementing Strategy behaviour can be added to a Pipeline alongside SlidingWindow and both execute correctly.
result: pass
evidence: Custom UpperCaseStrategy(priority: 150) composed with SlidingWindow(100). Output 3 messages, all uppercased — HELLO 8, HELLO 9, HELLO 10

### 4. Pipeline chains strategies by priority
expected: Pipeline with SlidingWindow(100) + TokenTruncation(200) applies SlidingWindow first (lower priority number), then TokenTruncation on the result.
result: pass
evidence: SlidingWindow(last:15) ran first → 15 messages. TokenTruncation(max:50) ran second → 10 messages. Output: Msg 11 through Msg 20.

### 5. apply_memory returns PhoenixAI.Message structs
expected: Store.apply_memory/3 loads messages from a real conversation, applies pipeline, returns %PhoenixAI.Message{} structs (not Store.Message).
result: pass
evidence: All 3 output messages are %PhoenixAI.Message{} — no conversation_id, no id field (Store-specific fields dropped)

### 6. Pinned field persists in Ecto
expected: A message saved with pinned: true via Ecto adapter can be loaded back with pinned: true preserved.
result: pass
evidence: 17 Ecto adapter contract tests pass. SQL queries show `pinned` column in INSERT and SELECT.

### 7. Summarization with mock AI
expected: Summarization strategy with summarize_fn produces a pinned system message containing the summary text, with recent messages preserved.
result: pass
evidence: Summary message created — role: system, pinned: true, content: "Summary of 10 messages". Total output: 11 (1 summary + 10 recent)

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0

## Gaps

[none]
