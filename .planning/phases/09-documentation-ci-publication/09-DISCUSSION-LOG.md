# Phase 9: Documentation, CI & Publication - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-04-05
**Phase:** 09-documentation-ci-publication
**Mode:** discuss (interactive)
**Areas discussed:** ExDoc Documentation, CI/GitHub Actions, Publication, README, Typespecs/Dialyzer, Package Files

## ExDoc Documentation

| Option | Description | Selected |
|--------|-------------|----------|
| Getting Started | Instalação, config mínima, primeiro converse/3 | ✓ |
| Adapters Guide | ETS vs Ecto, adapter custom | ✓ |
| Memory & Guardrails | Memory strategies + guardrails usage | ✓ |
| Telemetry & Events | TelemetryHandler, Store.track/1, event log | ✓ |

**User's choice:** All 4 guides

| Option | Description | Selected |
|--------|-------------|----------|
| Conciso | 1-3 linhas + @spec + Examples nos mais usados | |
| Completo | @doc detalhado com Examples em TODAS as funções | ✓ |
| Mínimo | Apenas @spec + 1 linha | |

**User's choice:** Completo — full @doc with Examples on all public functions

## CI / GitHub Actions

| Option | Description | Selected |
|--------|-------------|----------|
| Elixir 1.15+1.17 / OTP 26+27 | 4 combinações: mínimo + mais recente | ✓ |
| Apenas latest | Elixir 1.17 + OTP 27 | |
| Full matrix | 1.15/1.16/1.17 + OTP 26/27 (9 combos) | |

**User's choice:** 2x2 matrix (recommended)

**Checks selected:** mix test, mix credo --strict, mix dialyzer, mix docs — all 4

## Publication

| Option | Description | Selected |
|--------|-------------|----------|
| 0.1.0 | API may change — standard for new libs | ✓ |
| 1.0.0 | Signals API stability | |

**User's choice:** 0.1.0

| Option | Description | Selected |
|--------|-------------|----------|
| Keep a Changelog | keepachangelog.com format | ✓ |
| Minimal | Simple bullet list | |

**User's choice:** Keep a Changelog format

## README

| Option | Description | Selected |
|--------|-------------|----------|
| Completo | Badges + tagline + Features + Quick Start + Links | ✓ |
| Conciso | Tagline + install + 1 exemplo | |
| Hex-focused | Points to HexDocs | |

**User's choice:** Complete README

## Typespecs & Dialyzer

| Option | Description | Selected |
|--------|-------------|----------|
| Warnings-as-errors | CI fails on any warning | ✓ |
| Best-effort | Runs but doesn't fail CI | |
| Skip | Add later | |

**User's choice:** Warnings-as-errors

## Package Files

| Option | Description | Selected |
|--------|-------------|----------|
| Padrão Elixir | lib/ + priv/ + mix.exs + README + LICENSE + CHANGELOG | ✓ |
| Com .formatter.exs | Also includes .formatter.exs | |

**User's choice:** Standard Elixir package files

## Claude's Discretion

- ExDoc theme/colors
- Guide content structure details
- CI workflow naming and job structure
- Whether to add mix format check
- PLT warm-up strategy
