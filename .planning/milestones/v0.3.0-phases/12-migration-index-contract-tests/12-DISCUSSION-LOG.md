# Phase 12: Migration Index & Contract Tests - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-07
**Phase:** 12-migration-index-contract-tests
**Areas discussed:** Migration Strategy

---

## Migration Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Template + mix task upgrade | Update template + add --upgrade flag to mix task for existing projects | ✓ |
| Only template, docs explain | Update template only, manual instructions in CHANGELOG | |
| Template + separate migration | Update template + separate .eex template with --cost-cursor-index flag | |

**User's choice:** Template + mix task upgrade
**Notes:** --upgrade flag is more user-friendly than manual migration creation. Makes upgrade path seamless.

---

## Claude's Discretion

- Naming convention for upgrade migration template
- Scope of --upgrade flag (just cost cursor index vs all missing indexes)
- Test organization

## Deferred Ideas

None
