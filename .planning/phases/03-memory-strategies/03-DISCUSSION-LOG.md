# Phase 3: Memory Strategies - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 03-memory-strategies
**Areas discussed:** Strategy behaviour API, Token counting, Pinned messages, Composition model

---

## Strategy Behaviour API

| Option | Description | Selected |
|--------|-------------|----------|
| Always synchronous | apply(messages, opts) :: {:ok, messages}. Summarization blocks. | ✓ |
| Sync + async variant | apply/2 synchronous + apply_async/2 for Summarization | |
| You decide | Claude chooses | |

**User's choice:** Always synchronous
**Notes:** Simple and predictable. Summarization blocks until completion.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Only messages | apply([Message.t()], opts) :: {:ok, [Message.t()]} | |
| Full conversation | apply(Conversation.t(), opts) :: {:ok, Conversation.t()} | |
| Messages + context | apply([Message.t()], context, opts) — messages + metadata map | ✓ |

**User's choice:** Messages + context
**Notes:** Messages are pure list, context is a separate map with conversation metadata.

---

## Token Counting

| Option | Description | Selected |
|--------|-------------|----------|
| chars/4 heuristic | Simple, zero deps, ~15% error | |
| tiktoken optional | Rust NIF for OpenAI, chars/4 fallback | |
| Provider-dispatched | Each provider defines counting via behaviour | ✓ |
| You decide | Claude chooses | |

**User's choice:** Provider-dispatched
**Notes:** Extensible, correct per-provider. Default uses chars/4 heuristic.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Eager on insertion | Calculate at add_message, store in field | |
| Lazy in strategy | Calculate only when strategy needs it | |
| Eager + override | Calculate on insertion, strategy can recalculate if nil or forced | ✓ |

**User's choice:** Eager + override

---

## Pinned Messages

**User asked for clarification:** "O que seriam essas mensagens pinadas?"

**Explanation provided:** Pinned messages are "never evict" markers — even when strategies cut the history to fit the context window, pinned messages are preserved. Most common: system prompts, critical user context, business rules, summaries from previous rounds.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Campo pinned: boolean | New field on Message struct | |
| System auto + manual | System messages auto-pinned + boolean field for manual pinning | ✓ |
| You decide | Claude chooses | |

**User's choice:** System auto-pin + campo pinned: boolean
**Notes:** User specifically asked about "compacting but keeping history for querying" — strategies don't delete from storage, only filter what goes to AI. Full history stays in DB.

---

## Composition Model

| Option | Description | Selected |
|--------|-------------|----------|
| Pipeline sequential | Strategies applied in declared order | |
| Priority-based | Each strategy has priority, system resolves conflicts | ✓ |
| You decide | Claude chooses | |

**User's choice:** Priority-based

---

| Option | Description | Selected |
|--------|-------------|----------|
| Building blocks only | Developer assembles their own pipeline | |
| Presets + custom | Ready-made presets + custom pipeline option | ✓ |
| You decide | Claude chooses | |

**User's choice:** Presets + custom

---

## Claude's Discretion

- Priority numbers for built-in strategies
- TokenCounter behaviour implementation details
- Internal representation of strategy chains
- How presets are defined
- Summarization prompt template

## Deferred Ideas

None — discussion stayed within phase scope
