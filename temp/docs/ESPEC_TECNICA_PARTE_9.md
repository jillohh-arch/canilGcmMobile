# ESPECIFICAÇÃO TÉCNICA — PARTE 9
# Integridade da ocorrência: fotos no hash + retificação pós-selo (versão completa)

> Completa a Frente A. Duas mudanças no que sustenta o "registro defende o condutor 6 meses depois":
> 1. **A foto é evidência** — trocar, adicionar ou remover foto **quebra o selo** (detectável).
> 2. **Selado não é trancado** — após o hash, a correção é via **aditamento completo**, com integridade própria, sem reescrever o original.

---

## 9.0 — Escopo
Fechamento da Frente A. Antes desta parte:
- Editar local (Frente A) e natureza (Frente B) só valem **antes** de selar; após o hash, ficavam bloqueados.
- Fotos eram anexos documentais **fora** do hash de integridade.
Esta parte resolve as duas coisas em um único mecanismo coerente.

## 9.1 — Fotos no hash
- No **upload**, calcular **SHA-256 do binário comprimido** que vai ao Storage e gravar como `photo_hash` no documento da foto/evento.
- A **serialização determinística** que gera o hash da ocorrência passa a incluir, em ordem estável:
  - por evento, a lista dos `photo_hash` das fotos daquela ação;
  - a lista dos `photo_hash` das fotos da finalização.
- Consequências:
  - Trocar uma foto (mesmo na mesma URL/path) → `photo_hash` muda → hash da ocorrência muda → **selo quebra**.
  - Adicionar/remover foto → a lista muda → hash muda.
- **Backward compat:** ocorrências já seladas não têm `photo_hash`. Tratamento sugerido:
  - rodar uma migração que lê o binário do Storage, calcula o hash e grava (one-shot);
  - o que não puder ser recalculado (foto faltando, etc) recebe a marca **"selo legado"** no documento, exibida no detalhe e PDF com clareza ("este registro foi selado antes da v9 da integridade").

## 9.2 — Aditamento (retificação completa)
Após `finalized`, **edição direta continua bloqueada**. A correção é via **aditamento**.
### Modelo
Subcoleção `occurrences/{id}/amendments/{amendmentId}`:
- `id`, `created_at`, `created_by` (handler), `author_label`
- `reason` — **obrigatório**, texto explicando a retificação
- `corrections` — mapa com chaves opcionais:
  - `event_location` — `{ event_id, new_lat, new_lng, new_place_label, new_location_source }`
  - `event_photos_added` — `{ event_id, photo_refs[] }` (cada uma com seu `photo_hash`)
  - `finalization_photos_added` — `{ photo_refs[] }` (com `photo_hash`)
  - `nature_changed` — `{ new_nature }`
- `hash` — SHA-256 do conteúdo do aditamento (selo próprio do aditamento)
- `signature` — confirmação do autor (autenticado)

### Regras
- O hash **original** da ocorrência **nunca é regenerado** — o selo do registro inicial fica intacto.
- Cada aditamento tem **seu próprio hash** (selo do aditamento).
- **Não retira** — a v1 do aditamento só adiciona ou corrige; remoção de itens existentes não está prevista. Se uma foto foi anexada errada, o motivo do aditamento descreve a incorreção, sem apagar.
- **Múltiplos aditamentos** suportados, cronológicos.
- **Aditar um aditamento** não é permitido — para corrigir, criar um novo aditamento.

## 9.3 — Aplicação no detalhe (app)
- O mapa, a timeline e os campos mostram o **estado atual** (aditamentos aplicados por cima do original).
- Itens retificados recebem **marca visual** discreta — por exemplo, um pequeno ícone de aditamento sobre o pino ou um traço sutil na borda — sem esconder o original.
- Ao tocar no item retificado: **"Retificado em [data] por [autor]: [motivo]"**, com link para o aditamento completo.
- O **pino original NÃO some** do histórico — fica acessível dentro da visualização da retificação (o leitor pode ver onde caiu inicialmente).
- Seção **"Retificações"** no fim do detalhe lista os aditamentos cronologicamente: data, autor, motivo, o que foi corrigido, hash próprio.

## 9.4 — Aplicação no PDF
- O **corpo principal** mantém o **registro original**, com o hash original e o QR original. Apresentado como o registro foi selado.
- Após a seção de validação do original, vem a seção **"Aditamentos / Retificações"**, numerada:
  - cada aditamento com data, autor, motivo, o que foi corrigido (campo a campo, com antes/depois),
  - **hash próprio** do aditamento e, idealmente, **QR próprio** para verificação independente.
- Frase de abertura da seção, padronizada: "Este registro foi selado em [data]; abaixo, as retificações posteriores, com integridade verificável."

## 9.5 — Ponto de entrada
- No detalhe de uma ocorrência **selada**: botão/ação **"Adicionar retificação"**.
- Abre formulário com:
  - **Motivo** (texto obrigatório),
  - Opções de correção: local de uma ação · fotos adicionais (por ação ou finalização) · natureza.
- **Pré-visualização** antes de confirmar (o autor confere o que será registrado para sempre).
- Ao confirmar: cria o aditamento, calcula o hash, anexa.

## 9.6 — Critério de pronto
1. Toda foto (ação + finalização) guarda `photo_hash` no upload.
2. O hash da ocorrência inclui os `photo_hash` na serialização determinística.
3. Trocar/adicionar/remover foto **quebra o selo** (verificável).
4. Ocorrências antigas: migração executada ou marcadas como "selo legado", com exibição clara.
5. Após selar, **"Adicionar retificação"** abre o formulário; o aditamento é criado com hash próprio.
6. O hash **original** permanece intacto.
7. Detalhe mostra estado atual com marca visual de aditamento e seção "Retificações".
8. PDF mostra original + seção numerada de aditamentos, cada um com seu hash.
9. Múltiplos aditamentos cronológicos funcionam.
