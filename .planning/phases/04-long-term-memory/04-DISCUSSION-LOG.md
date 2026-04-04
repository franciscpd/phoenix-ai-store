# Phase 4: Long-Term Memory - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 04-long-term-memory
**Areas discussed:** Modelo de Facts, Extração & Timing, Profile Summary, Injeção no Contexto

---

## Modelo de Facts

### Q1: Como os facts devem ser modelados no storage?

| Option | Description | Selected |
|--------|-------------|----------|
| Key-value simples | Cada fact é {user_id, key, value}. Simples, fácil de consultar e atualizar. | ✓ |
| Key-value com namespace | {user_id, namespace, key, value} — agrupa facts por domínio. | |
| Key-value versionado | Mantém histórico de valores anteriores. | |

**User's choice:** Key-value simples
**Notes:** None

### Q2: Onde armazenar facts?

| Option | Description | Selected |
|--------|-------------|----------|
| Novos callbacks no Adapter | Adicionar save_fact/get_facts/delete_fact ao Adapter behaviour existente. | ✓ |
| Módulo separado com behaviour próprio | FactStore behaviour independente. | |
| Ecto-only (sem InMemory) | Facts só com persistência real. | |

**User's choice:** Novos callbacks no Adapter
**Notes:** None

### Q3: Tipo do value

| Option | Description | Selected |
|--------|-------------|----------|
| String pura | value é sempre string. Simples, sem ambiguidade. | ✓ |
| Tipo flexível (any term) | Aceita qualquer Elixir term. ETS nativo, Ecto JSONB. | |

**User's choice:** String pura
**Notes:** None

### Q4: Upsert behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Upsert silencioso | Sobrescreve sem aviso. Mesmo padrão do save_conversation. | ✓ |
| Upsert com flag de mudança | Retorna {:ok, fact, :updated} vs {:ok, fact, :created}. | |
| Erro se já existe | Retorna {:error, :already_exists}. | |

**User's choice:** Upsert silencioso
**Notes:** None

### Q5: Limite de facts por user

| Option | Description | Selected |
|--------|-------------|----------|
| Sem limite | Developer controla via API. | |
| Limite configurável | max_facts_per_user via NimbleOptions. | ✓ |

**User's choice:** Limite configurável
**Notes:** None

---

## Extração & Timing

### Q1: Quando a extração de facts deve acontecer?

| Option | Description | Selected |
|--------|-------------|----------|
| Explícita via API | Developer chama extract_facts. Controle total. | |
| Automática após cada turno | Integrada no pipeline do converse/2. | |
| Automática no fim da conversa | Trigger quando conversa é fechada. | |

**User's choice:** Other — Configurável em qualquer um dos 3 casos
**Notes:** User wants all 3 modes available as config options, with ability to enable/disable. Maximum flexibility.

### Q2: Sync ou async?

| Option | Description | Selected |
|--------|-------------|----------|
| Síncrona | Segue padrão da Summarization. Previsível. | |
| Assíncrona via Task | Fire-and-forget. Performante. | |
| Configurável (sync ou async) | Developer escolhe via extraction_mode. | ✓ |

**User's choice:** Configurável (sync ou async)
**Notes:** None

### Q3: Escopo da extração

| Option | Description | Selected |
|--------|-------------|----------|
| Só mensagens novas | Incremental com cursor. Eficiente em tokens. | ✓ |
| Conversa completa | Sempre manda toda a conversa. Simples. | |
| Configurável | Developer escolhe :incremental ou :full. | |

**User's choice:** Só mensagens novas
**Notes:** None

---

## Profile Summary

### Q1: Formato do profile

| Option | Description | Selected |
|--------|-------------|----------|
| Texto livre | Parágrafo gerado pela AI. Natural para injeção. | |
| Estruturado com seções | Template com seções fixas. Previsível. | |
| Híbrido | Texto livre principal + metadata estruturado. | ✓ |

**User's choice:** Híbrido
**Notes:** None

### Q2: Refinamento do profile

| Option | Description | Selected |
|--------|-------------|----------|
| AI recebe profile atual + novos facts | AI decide o que muda. Simples e natural. | ✓ |
| Merge automático por seção | Compara seções e faz merge. | |
| Append + condensação | Novos insights adicionados, periodicamente condensados. | |

**User's choice:** AI recebe profile atual + novos facts
**Notes:** None

### Q3: Timing do profile update

| Option | Description | Selected |
|--------|-------------|----------|
| Operação separada | extract_facts e update_profile independentes. | ✓ |
| Junto com extração | Uma só chamada faz tudo. | |

**User's choice:** Operação separada
**Notes:** None

---

## Injeção no Contexto

### Q1: Onde no pipeline?

| Option | Description | Selected |
|--------|-------------|----------|
| Antes das strategies, como pinned | Facts + profile viram system messages pinned. | ✓ |
| Depois das strategies | Adicionados ao resultado final. | |
| Como parte do context map | Entram no context map, não como messages. | |

**User's choice:** Antes das strategies, como pinned
**Notes:** None

### Q2: Formato da injeção

| Option | Description | Selected |
|--------|-------------|----------|
| Uma system message com todos os facts | Uma única mensagem pinned com lista de facts. Profile como outra separada. | ✓ |
| Uma system message por fact | Cada fact vira mensagem separada. | |
| Embutido no system prompt existente | Concatenados ao system prompt. | |

**User's choice:** Uma system message com todos os facts
**Notes:** None

### Q3: Automática ou opt-in?

| Option | Description | Selected |
|--------|-------------|----------|
| Opt-in via config | inject_long_term_memory: true. Default: false. | ✓ |
| Automática se facts existem | Injetados automaticamente. Zero config. | |
| Sempre via função explícita | Developer chama inject_context manualmente. | |

**User's choice:** Opt-in via config
**Notes:** None

---

## Claude's Discretion

- Exact Adapter callback signatures and return types for facts
- Fact struct fields beyond {user_id, key, value}
- Profile struct internal representation
- Extraction and profile update prompt templates
- Default max_facts_per_user value
- Cursor tracking mechanism for incremental extraction
- Task.Supervisor configuration for async mode
- Ecto migration table structure for facts and profiles

## Deferred Ideas

None — discussion stayed within phase scope
