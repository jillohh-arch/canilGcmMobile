# Adendo — Resultado da Validação + Prioridade #1 (Verificador de Selo)
### 27/05/2026, após validação técnica das 3 frentes pelo Claude Code

---

## 🔴 PRIORIDADE #1 ABSOLUTA — Verificador de integridade ausente

**O problema:** o hash é **gerado e exibido**, mas **nunca recalculado e comparado** para detectar adulteração. Existe `HashService.verify`, mas sem uso produtivo que recompute por `hash_version`. O PDF só mostra o hash armazenado (`occurrence_pdf_generator.dart:2614`).

**Por que é o #1 acima de tudo:** sem verificação, todo o aparato de integridade (Parte 9, fotos no hash, v3 com assinaturas) é **decorativo**. O app não detecta se uma foto foi trocada ou um dado mexido direto no Firestore. A propriedade central do projeto — "este registro não foi adulterado" — não está ativa. O teste "trocar foto → selo quebra" não tem como acontecer porque não há quem quebre o selo.

### O que o verificador precisa fazer
1. Ao abrir uma ocorrência selada (e ao gerar o PDF), pegar os dados **atuais**.
2. Ler o `hash_version` gravado.
3. **Recalcular** o hash com a serialização determinística **idêntica à da geração**, respeitando a versão:
   - v1: sem photo_hashes
   - v2: com photo_hashes (ação + finalização)
   - v3: com photo_hashes + `team` + `signatures` (sem `signature_hash`)
4. **Comparar** com o hash armazenado.
5. Exibir o veredito: **✅ Íntegro** ou **🔴 Selo quebrado / possível adulteração** — no detalhe e no PDF.

### Pontos de atenção (decisivos)
- **Espelhar EXATAMENTE a geração.** Se a serialização da verificação divergir em um campo, uma ordem ou um formato, vai dar **falso positivo de adulteração**. O verificador deve reusar a mesma função de serialização da geração, não uma cópia paralela.
- **Timezone.** A auditoria forense apontou inconsistência (ocorrência usa hora local, amendment usa UTC). Isso precisa ser **normalizado para UTC nos dois** antes de o verificador funcionar — senão acusa falso positivo ao verificar em outro fuso.
- **Fotos: rasa vs profunda.** Decisão de design a tomar:
  - **Rasa** (rápida): compara os `photo_hash` armazenados com o payload. Detecta mexida em estrutura/metadados, **não** detecta troca do binário.
  - **Profunda** (cara): rebaixa o binário do Storage e recalcula o SHA-256. Detecta troca real de foto. É o que sustenta o teste "trocar foto → quebra".
  - Recomendação: rasa por padrão (abertura rápida) + profunda sob demanda (botão "verificar fotos"), ou profunda só na geração do PDF oficial.

---

## ✅ O que está CONFIRMADO bom (base sólida)
- Hash inclui fotos (v2) — `finalize_occurrence_screen.dart:337,378`.
- **Hash v3 inclui `team` e `signatures`** no payload; `signature_hash` fica fora (evita ciclo) — `occurrence_finalization_service.dart:287`. A co-assinatura tem fundamento probatório.
- Hash original preservado ao criar aditamento — `amendment_repository.dart:111`.
- Local editável com auditoria — `occurrence_event_repository.dart:40`.
- Natureza editável com auditoria antes do selo — `occurrence_repository.dart:86`.
- Foto de finalização sobe pro path certo — `finalize_occurrence_screen.dart:1354`.
- Bloqueio após `finalized`/`awaiting_signatures` no client **e** no Firestore — `occurrence_repository.dart:875`, `firestore.rules:567`.
- Aditamento por titular/membro assinado **imposto na regra do servidor** — `firestore.rules:272,580`.
- `firestore.rules` versionado; regras de `signatures` e `notifications` existem.
- Frente C: autocomplete de condutores (`UserService`/`/users`), limite por `teamSizeMax`, header de equipe, biometria com fallback senha, tela de pendências, PDF de assinaturas — tudo confirmado em código.

---

## ⚠️ Achados secundários (corrigir, não bloqueiam o #1)
1. **Frente B — não reusou o widget da criação.** Foi criada do zero (commit `b29c61d`) com bottom sheet próprio. Funciona e audita, mas duplica a lista de naturezas. Alinhar com o seletor da criação pra evitar divergência futura.
2. **Storage delete amplo** — `storage.rules:79` permite delete por qualquer usuário logado. Fotos de evidência deletáveis por qualquer um é brecha. Fechar.
3. **Coleções ainda amplas** — `create, update: if signedIn()` em treinos/saúde/rotinas/incidentes (`firestore.rules:459,602,614,620`). O banco segue aberto demais em várias áreas. Trabalho de endurecimento de segurança pendente.

---

## Prioridades atualizadas (ordem recomendada)
1. **🔴 Verificador de integridade** — recalcular + comparar por versão, com normalização de timezone. Sem isso, a integridade é teatro. **Faça primeiro.**
2. **Hard deletes** (4 serviços: training/dog/user/command) → soft delete, padrão `HealthService`.
3. **Endurecimento do Firestore/Storage** — fechar coleções amplas + delete de foto. Sessão dedicada de segurança.
4. **Validação real no celular** das 3 frentes (roteiro `VALIDACAO_3_FRENTES.md`), agora com o verificador já existindo (senão o teste do selo não roda).
5. **Frente B** — alinhar o seletor de natureza com o da criação.
6. Backlog antigo (material/odor por linha, offline, /v/{id}, dívida de tokens).

> Observação importante: o teste "trocar foto quebra o selo" do roteiro de validação **só faz sentido depois** que o verificador existir. Até lá, ele fica em espera.
