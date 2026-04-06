# Phase 10: Streaming Support - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-05
**Phase:** 10-streaming-support
**Areas discussed:** Option Validation, Telemetry & Events, Conflict on_chunk + to, Testing Strategy

---

## Option Validation

| Option | Description | Selected |
|--------|-------------|----------|
| Guard clauses no call_ai | Manter consistência com o padrão atual — Keyword.get + is_function/is_pid guard. Zero overhead, zero deps novas | ✓ |
| NimbleOptions schema | Adicionar validação formal via @converse_schema. Mais seguro mas muda o padrão de converse/3 | |
| Você decide | Claude escolhe a melhor abordagem | |

**User's choice:** Guard clauses no call_ai (Recomendado)
**Notes:** Consistent with existing converse/3 pattern that doesn't use NimbleOptions

---

## Telemetry & Events

| Option | Description | Selected |
|--------|-------------|----------|
| Via context map | Adicionar streaming: true/false no context map em store.ex. O span lê do context, e maybe_log_event inclui na metadata do evento | ✓ |
| Retorno do pipeline | ConversePipeline.run retorna {result, %{streaming: bool}} e o span usa como metadata | |
| Você decide | Claude escolhe a melhor abordagem | |

**User's choice:** Via context map (Recomendado)
**Notes:** Leverages existing context map pattern — no pipeline return signature changes needed

---

## Conflict on_chunk + to

| Option | Description | Selected |
|--------|-------------|----------|
| Erro com mensagem clara | Retornar {:error, :conflicting_streaming_options} — força o usuário a escolher um modo. Evita comportamento surpreendente | ✓ |
| Priorizar on_chunk | on_chunk tem precedência, to é ignorado silenciosamente. Mais simples mas pode confundir | |
| Aceitar ambos | Despacha chunks para os dois. Mais flexível mas complexo e pode ter efeitos colaterais | |

**User's choice:** Erro com mensagem clara (Recomendado)
**Notes:** Explicit error prevents ambiguous behavior

---

## Testing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Mox mock do AI module | Definir expectation para AI.stream/2 retornando {:ok, %Response{}} e simulando chunks. Já usamos Mox no projeto | ✓ |
| Test provider com streaming | Criar provider :test_stream que implementa stream/3 com chunks fake. Mais realista mas mais código | |
| Você decide | Claude escolhe a melhor abordagem | |

**User's choice:** Mox mock do AI module (Recomendado)
**Notes:** Already established in project — consistent with existing test patterns

---

## Claude's Discretion

- Exact placement of the conflict check (early in converse/3 vs inside call_ai/2)
- Whether to add a `streaming?/1` helper or inline the check
- Test fixture structure for mock responses

## Deferred Ideas

None — discussion stayed within phase scope
