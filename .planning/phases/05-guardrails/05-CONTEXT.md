# Phase 5: Guardrails - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a middleware-chain policy system that runs before each AI call — enforcing token budgets, tool allowlists/denylists, content filtering hooks, and jailbreak/prompt injection detection. Policies can pass, halt (with structured PolicyViolation), or modify the request. First violation wins. Policies are stackable via ordered config lists, with presets for common patterns.

Note: GUARD-02 (cost budget) is deferred to Phase 6 where CostRecord data is available.

</domain>

<decisions>
## Implementation Decisions

### Policy Stack Design
- **D-01:** Policies follow a **middleware chain pattern** (Plug-style) — each policy receives a request context struct and can: (1) `:pass` — next policy runs, (2) `:halt` — returns `{:error, %PolicyViolation{}}`, (3) modify the request (e.g., sanitize content, add metadata). Combines validation with transformation.
- **D-02:** Policy stack is defined as an **ordered list via config** — `[{PolicyModule, opts}, ...]`. Execution is sequential; order in the list is order of execution. No automatic priority system — developer controls ordering explicitly.
- **D-03:** **Presets available** — ready-made stacks like `:default` (token budget + jailbreak detection), `:strict` (all policies enabled), `:permissive` (jailbreak only). Developer can customize or extend presets.

### PolicyViolation Struct
- **D-04:** PolicyViolation has **essential + context fields**: `policy` (atom — which policy), `reason` (string — human-readable), `message` (String.t | nil — the violating message if applicable), `metadata` (map — extra data from the policy). No severity field — every violation is blocking.

### Token Budget
- **D-05:** Token budget supports **three scopes**: per-conversation (sums token_count from messages), per-user (aggregates across conversations via adapter), and per-time-window (using Hammer rate limiter as optional dependency).
- **D-06:** Token counting mode is **configurable**: `:accumulated` (counts tokens of existing messages — default) or `:estimated` (includes estimated response tokens). Developer chooses per policy instance.
- **D-07:** **Hammer** is used for time-window token budgets as an optional dependency. If not available and time-window is configured, returns clear error at boot.

### Tool Policy
- **D-08:** Tool policy supports **allowlist or denylist** — configured per conversation or globally. A request containing a disallowed tool call is halted with a PolicyViolation identifying the tool and the policy.

### Content Filtering
- **D-09:** Content filtering uses **developer-provided functions** as pre- and post-call hooks. Functions receive the message and return `{:ok, message}` (pass/modify) or `{:error, reason}` (halt). This is a policy in the middleware chain, not a separate mechanism.

### Jailbreak Detection
- **D-10:** Default detector uses **keyword-based heuristics** — a list of known patterns ("ignore previous instructions", "DAN", "you are now", role-play injection markers). Score based on keyword matches against a configurable threshold.
- **D-11:** Detection scope is **configurable**: `:last_message` (default — only the latest user message) or `:all_user_messages` (all user messages in the batch). Developer chooses via policy opts.
- **D-12:** `JailbreakDetector` behaviour allows developers to **replace the default detection logic** with custom implementations (OpenAI moderation API, ML classifiers, etc.).

### Claude's Discretion
- Exact keyword patterns for default jailbreak detection
- Scoring algorithm and default threshold
- Request context struct field names (the "conn"-like struct)
- Policy behaviour callback signature details
- NimbleOptions schema structure for guardrails config
- Preset compositions (exact policies per preset)
- How tool calls are identified in messages for tool policy
- Integration point in the converse/2 pipeline (Phase 8)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (Phases 1, 3, 4)
- `lib/phoenix_ai/store/adapter.ex` — Adapter behaviour + sub-behaviours pattern
- `lib/phoenix_ai/store/memory/pipeline.ex` — Pipeline pattern (ordered strategy execution, pinned message handling)
- `lib/phoenix_ai/store/memory/strategy.ex` — Strategy behaviour (reference for Policy behaviour design)
- `lib/phoenix_ai/store/message.ex` — Message struct with token_count field (used by token budget)
- `lib/phoenix_ai/store/conversation.ex` — Conversation struct
- `lib/phoenix_ai/store.ex` — Public API facade (guardrails will integrate here)
- `lib/phoenix_ai/store/config.ex` — NimbleOptions config (guardrails options added here)
- `lib/phoenix_ai/store/long_term_memory.ex` — Sub-behaviour check pattern (`function_exported?`, `{:error, :ltm_not_supported}`)

### PhoenixAI Peer Dependency
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/agent.ex` — Agent with tool_calls
- `~/Projects/opensource/phoenix-ai/lib/phoenix_ai/message.ex` — PhoenixAI.Message struct (tool_calls field)

### Planning
- `.planning/REQUIREMENTS.md` — GUARD-01, GUARD-03 through GUARD-10 requirements
- `.planning/phases/01-storage-foundation/01-CONTEXT.md` — Phase 1 decisions
- `.planning/phases/03-memory-strategies/03-CONTEXT.md` — Phase 3 decisions (Pipeline, Strategy behaviour)
- `.planning/phases/04-long-term-memory/04-CONTEXT.md` — Phase 4 decisions (sub-behaviours, error tuples)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Store.Memory.Pipeline` — reference for ordered execution pattern; guardrails pipeline will be similar but with halt/modify semantics instead of filter semantics
- `PhoenixAI.Store.Memory.Strategy` behaviour — reference for Policy behaviour design (`@callback` pattern)
- `PhoenixAI.Store.Message` with `token_count` field — ready for token budget calculation
- `PhoenixAI.Store.Config` with NimbleOptions — extend with guardrails options
- `PhoenixAI.Store.Adapter` with `get_messages/2` — load messages for token counting

### Established Patterns
- Behaviours with `@callback` for all pluggable components
- `{:ok, result} | {:error, term}` return types
- NimbleOptions validation at init time
- Telemetry spans for all public operations
- Sub-behaviours with `function_exported?` checks

### Integration Points
- Guardrails run BEFORE the AI call — in the future `converse/2` pipeline (Phase 8)
- For now, exposed as standalone `check_policies/2` function that developers call explicitly
- Token budget reads from adapter (message token_counts)
- Tool policy inspects message tool_calls field

</code_context>

<specifics>
## Specific Ideas

- The request context struct ("conn"-like) should carry: messages, user_id, conversation_id, tool_calls (if any), metadata. Policies read and optionally modify this struct.
- Presets: `:default` = TokenBudget(max: 100_000) + JailbreakDetection, `:strict` = TokenBudget + ToolPolicy + ContentFilter + JailbreakDetection, `:permissive` = JailbreakDetection only
- Hammer integration for time-window: `Hammer.check_rate("token_budget:#{user_id}", window_ms, max_tokens)` — returns `:allow` or `{:deny, _}`
- Content filtering hooks as policies: `{ContentFilter, pre: &MyApp.check_pii/1, post: &MyApp.check_response/1}`

</specifics>

<deferred>
## Deferred Ideas

- **GUARD-02 (cost budget)** — Deferred to Phase 6 where CostRecord data is available. Cost budget is a guardrail but requires cost tracking infrastructure first.

</deferred>

---

*Phase: 05-guardrails*
*Context gathered: 2026-04-04*
