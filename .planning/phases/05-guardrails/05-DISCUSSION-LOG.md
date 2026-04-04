# Phase 5: Guardrails - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 05-guardrails
**Areas discussed:** Policy Stack Design, PolicyViolation struct, Token Budget & Scoping, Jailbreak Detection

---

## Policy Stack Design

### Q1: How should policies be composed and executed?

| Option | Description | Selected |
|--------|-------------|----------|
| Lista ordenada via config | Sequential execution, first violation returns | |
| Priority-based (como Memory Pipeline) | Each policy has priority/0, system sorts | |
| Middleware chain (estilo Plug) | Each policy receives conn-like struct, can halt or modify | ✓ |

**User's choice:** Middleware chain (estilo Plug)
**Notes:** Allows policies to not just validate but also modify the request (e.g., sanitize content)

### Q2: What operations can a policy perform?

| Option | Description | Selected |
|--------|-------------|----------|
| Pass, halt, ou modificar | Policy can pass, halt with violation, or modify request | ✓ |
| Só pass ou halt | Pure validators, no modification | |

**User's choice:** Pass, halt, ou modificar

### Q3: Should there be preset policy stacks?

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, com presets | :default, :strict, :permissive presets | ✓ |
| Não, só config manual | Developer assembles entire stack | |

**User's choice:** Sim, com presets

---

## PolicyViolation struct

### Q1: What fields should PolicyViolation have?

| Option | Description | Selected |
|--------|-------------|----------|
| Essencial + contexto | policy, reason, message, metadata. No severity — all blocking | ✓ |
| Mínimo | Just policy and reason | |
| Com severity | Adds :warning / :error levels | |

**User's choice:** Essencial + contexto
**Notes:** No severity — every violation is blocking

---

## Token Budget & Scoping

### Q1: How to implement per-time-window token budget?

| Option | Description | Selected |
|--------|-------------|----------|
| Contadores in-memory via ETS | Simple counter, resets on window expiry | |
| Usando Hammer (rate limiter) | Hammer as optional dep, native sliding window | ✓ |
| Sem time window (defer to v2) | Only per-conversation and per-user | |

**User's choice:** Usando Hammer

### Q2: What should token budget count?

| Option | Description | Selected |
|--------|-------------|----------|
| Messages existentes | Sum token_count of existing messages | |
| Estimativa da próxima chamada | Include estimated response tokens | |
| Ambos configurável | Developer chooses :accumulated or :estimated | ✓ |

**User's choice:** Ambos configurável

---

## Jailbreak Detection

### Q1: Default detector sophistication level?

| Option | Description | Selected |
|--------|-------------|----------|
| Heurísticas keyword-based | Known patterns + keyword scoring + configurable threshold | ✓ |
| Regex patterns simples | Just regex matching | |
| Placeholder minimal + behaviour | Almost empty default, focus on behaviour | |

**User's choice:** Heurísticas keyword-based

### Q2: What should the detector analyze?

| Option | Description | Selected |
|--------|-------------|----------|
| Só última mensagem do user | Only the message about to be sent | |
| Todas as mensagens user no batch | All user messages in the call | |
| Configurável | Developer chooses :last_message or :all_user_messages | ✓ |

**User's choice:** Configurável (default :last_message)

---

## Claude's Discretion

- Exact keyword patterns for default jailbreak detection
- Scoring algorithm and default threshold
- Request context struct field names
- Policy behaviour callback signature details
- NimbleOptions schema structure
- Preset compositions
- Tool call identification in messages
- Integration point in converse/2 pipeline

## Deferred Ideas

- GUARD-02 (cost budget) — deferred to Phase 6 where CostRecord data is available
