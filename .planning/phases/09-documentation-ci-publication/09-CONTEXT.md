# Phase 9: Documentation, CI & Publication - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the library publishable on Hex.pm: complete ExDoc documentation with guides, GitHub Actions CI pipeline, README, CHANGELOG, LICENSE, and `mix hex.publish --dry-run` passing cleanly.

</domain>

<decisions>
## Implementation Decisions

### ExDoc Documentation
- **D-01:** Generate 4 extra guides beyond API reference: "Getting Started", "Adapters Guide", "Memory & Guardrails", "Telemetry & Events". Each lives in `guides/` directory and appears in ExDoc sidebar.
- **D-02:** Complete `@doc` with `## Examples` on ALL public functions across all modules. Not just the top-level facade — adapters, guardrails, cost tracking, event log all get full docs.
- **D-03:** Every public module keeps its existing `@moduledoc`. Add `@moduledoc` to any module missing one. Every public function gets `@spec`.

### CI / GitHub Actions
- **D-04:** Matrix: Elixir 1.15 + 1.17, OTP 26 + 27 (4 combinations). Covers minimum supported and latest.
- **D-05:** CI checks: `mix test` (with Postgres service container), `mix credo --strict`, `mix dialyzer` (PLT cached), `mix docs` (no warnings). All must pass.
- **D-06:** Dialyzer runs with warnings-as-errors — CI fails on any warning. Use `@dialyzer` annotations only where strictly necessary.
- **D-07:** Cache strategy: PLT cache keyed by Elixir+OTP version + mix.lock hash. Deps cache keyed by mix.lock.

### Publication on Hex
- **D-08:** Version 0.1.0 — API may change, standard for new Elixir libs.
- **D-09:** CHANGELOG follows Keep a Changelog format (keepachangelog.com) — sections: Added, Changed, Fixed per version.
- **D-10:** LICENSE file is MIT (already declared in `package/0`).

### README
- **D-11:** README structure: Hex/CI/Docs badges → tagline → Features list → Quick Start code example (ETS + converse/3) → Links to HexDocs guides. Complete but not overwhelming.

### Typespecs & Dialyzer
- **D-12:** Add `@spec` to every public function that doesn't have one. Run `mix dialyzer` and fix all warnings before CI is set up.

### Package Files
- **D-13:** Package includes: `lib/`, `priv/`, `mix.exs`, `README.md`, `LICENSE`, `CHANGELOG.md` — already configured in `package/0`.

### Claude's Discretion
- ExDoc theme/colors (default is fine)
- Guide content structure and examples within each guide
- Exact CI workflow naming and job structure
- Whether to add mix format check to CI
- PLT warm-up strategy details

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Implementation (all phases)
- `mix.exs` — Package metadata, deps, docs config, package file list
- `lib/phoenix_ai/store.ex` — Main facade (~630 lines, 27 @doc entries, needs completion)
- `lib/phoenix_ai/store/adapter.ex` — Adapter behaviour with sub-behaviours (0 @doc — needs all)
- `lib/phoenix_ai/store/config.ex` — NimbleOptions schema (2 @doc entries)
- `lib/phoenix_ai/store/converse_pipeline.ex` — Pipeline orchestration (1 @doc)
- `lib/phoenix_ai/store/telemetry_handler.ex` — Telemetry handler (has docs)
- `lib/phoenix_ai/store/handler_guardian.ex` — Guardian GenServer (1 @doc)
- `lib/phoenix_ai/store/cost_tracking.ex` — Cost orchestrator (1 @doc)
- `lib/phoenix_ai/store/event_log.ex` — Event log orchestrator (3 @doc)
- `lib/phoenix_ai/store/guardrails/token_budget.ex` — TokenBudget policy (0 @doc)
- `lib/phoenix_ai/store/guardrails/cost_budget.ex` — CostBudget policy (0 @doc)

### Planning
- `.planning/ROADMAP.md` — Phase 9 success criteria
- `.planning/REQUIREMENTS.md` — DOC-01 requirement

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `mix.exs` already has `package/0` and `docs/0` configured — extend, don't rewrite
- ExDoc `~> 0.34` already in deps
- Credo and Dialyxir already in deps
- `.formatter.exs` exists

### Established Patterns
- All modules have `@moduledoc` — pattern is set, just need `@doc` completion
- `store.ex` has 27 `@doc` entries already — follow same style for remaining functions
- NimbleOptions schema in `config.ex` generates its own docs — leverage in guides

### Integration Points
- `guides/` directory to create — referenced by `docs()` in mix.exs
- `.github/workflows/ci.yml` — new file
- Root files: `README.md`, `LICENSE`, `CHANGELOG.md` — new files

</code_context>

<specifics>
## Specific Ideas

- Getting Started guide should get a new dev from `mix deps.get` to a working `converse/3` call in under 5 minutes
- README badges: Hex version, CI status, HexDocs link
- CI should use Postgres service container for Ecto adapter tests

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-documentation-ci-publication*
*Context gathered: 2026-04-05*
