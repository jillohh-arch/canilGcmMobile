# Adendo — Diagnóstico da Frente C (27/05/2026)
### Ajusta o plano da PARTE_10 com base no estado real do código

---

## O que JÁ EXISTE (a Frente C está mais pronta do que parecia)
- **Modelo de equipe completo:** `team: List<OccurrenceTeamMember>`, `teamSizeMax` (padrão 3), `signatureRequestAt`, `signatureDeadline` — já no modelo da ocorrência.
- **Status novos já implementados** em `occurrence_status.dart`: `awaitingSignatures`, `finalizedWithPending`.
- **Lógica do hash v3 já escrita:** `occurrence_repository.dart:153` → `final hashVersion = (occurrence?.team.isNotEmpty == true) ? 3 : 2;`
- **Biometria pronta e em uso:** `local_auth: ^2.3.0`, usado no login (`_checkBiometricAndAutoPrompt()`, `_handleBiometricLogin()`). Reusar pro fluxo de assinatura.
- **`flutter_local_notifications: ^21.0.0`** existe (usado no foreground do GPS).
- **`users` collection existe** em `/users/{ra}` — mas não é usada pra gestão de equipe ainda.

## O que FALTA (camada funcional)
- Subcoleção `occurrences/{id}/signatures`.
- Subcoleção `notifications/{userId}/items` + tela "Pendências" + badge contador.
- Autocomplete de condutores lendo a `users` collection.
- Fluxo de assinatura (reusando a biometria do login).
- **Firestore rules específicas + revisão geral de segurança** (ver alerta abaixo).

## Ajuste no plano da PARTE_10
- **Etapa 1 encolheu:** modelo e status já existem. Só faltam as subcoleções `signatures` e `notifications`.
- **Etapas 2–5 seguem** como specadas na PARTE_10.
- **hash v3:** já planejado; só validar que `team` e `signatures` entram na serialização determinística no momento do selo (seção 10.7).

---

## 🔴 ALERTA DE SEGURANÇA — eleva acima da Frente C
O diagnóstico revelou que o `firestore.rules` **permite leitura/escrita ampla em muitas coleções sem restrições específicas**, e não está versionado adequadamente (sem `rules_version`, sem regras por status/coleção).

**Por que isso é maior que a Frente C:**
- O banco está **aberto demais hoje**. Num app com dados de ocorrências policiais (presos, apreensões, identificação), regras frouxas são risco real de vazamento e adulteração — o oposto exato do "registro que defende o condutor".
- **Co-assinatura sem rules é teatro:** biometria na porta da frente com a janela dos fundos aberta. Quem tiver acesso ao Firestore escreve em `signatures` direto, burlando tudo.

**Recomendação:**
1. Tratar o `firestore.rules` como **trabalho de segurança próprio**, não só a Etapa 5 da Frente C.
2. Escrever as regras **incrementalmente junto de cada etapa** — a regra de `signatures` nasce quando a subcoleção nasce; a trava de edição em `awaiting_signatures` nasce quando o estado nasce.
3. Fazer uma **revisão geral da abertura do banco** (fechar coleções amplas demais) — idealmente antes ou em paralelo à Frente C, porque o app inteiro se beneficia. Vale uma sessão dedicada de "endurecimento das regras do Firestore".
4. Sempre validar a restrição **no servidor**, não só no client. O teste de ouro: tentar a ação proibida (assinar como não-membro, editar em `awaiting_signatures`, aditar sem ter assinado) e confirmar que o **Firestore recusa**, mesmo forçando por fora do app.

As regras exigidas pela Frente C estão na seção 10.8 da PARTE_10.
