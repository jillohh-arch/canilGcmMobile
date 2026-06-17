# Sessao 2026-06-03 - Notificacoes e prontuario de saude

## Objetivo

Consolidar a Parte 14 (notificacoes) e a Parte 15 (Saude / Prontuario do cao), deixando o app com:

- acesso global a notificacoes pelo sino no header;
- badge baseado em pendencias realmente abertas;
- tela de notificacoes com acoes e regras de auditoria;
- prontuario de saude reorganizado em abas;
- nutricao integrada ao prontuario;
- FAB unico de saude abrindo o Hub de acoes;
- APK release validado e merge em `main`.

## Estado Git

- Branch de trabalho: `parte15-etapa5-6-saude-historico-auditoria`
- Commit da feature: `459606e feat: consolida notificacoes e prontuario de saude`
- Merge em `main`: `859b94f merge: consolida notificacoes e prontuario de saude`
- Push concluido para `origin/main`.
- Status final apos push: `main` alinhada com `origin/main`, sem pendencias locais.

## Parte 14 - Notificacoes

### Modelo e servicos

- `NotificationItem` foi estendido para campos e semantica de acao aberta:
  - `action_required`
  - `resolved_at`
  - `archived_at`
  - dados de acao/deep link para roteamento.
- `NotificationService` passou a separar pendencia acionavel de aviso.
- Badge passou a contar apenas notificacoes com:
  - `action_required == true`
  - `resolved_at == null`
  - nao arquivadas.

### Header global

- Header passou a usar:
  - hamburguer a esquerda sem badge;
  - sino a direita com contador de pendencias.
- O item "Notificacoes" e badge interno do menu foram removidos do hamburguer.

### Tela e acoes

- Tela de notificacoes organizada em:
  - `Requer acao`
  - `Avisos`
- Convite de guarnicao pode ser aceito/recusado inline.
- Assinatura e evolucao de treino abrem tela de revisao/avaliacao; nao resolvem em um clique.
- Avisos podem ser marcados como lidos e arquivados via soft archive.
- Pendencias nao podem ser apagadas/limpas manualmente; saem da lista apenas quando a acao real e resolvida.

### Backend, rules e backfill

- Functions passaram a marcar notificacoes relacionadas como resolvidas quando a acao real acontece:
  - convite respondido;
  - assinatura feita;
  - evolucao de treino avaliada.
- Criado utilitario de backfill:
  - `tools/backfill_notification_resolution.js`
- `firestore.rules` e testes de rules foram ajustados para proteger o contrato:
  - delete segue bloqueado;
  - arquivar pendencia aberta nao e permitido;
  - avisos podem ser arquivados sem apagar o registro real.

## Parte 15 - Saude / Prontuario do cao

### Tela principal

- Criada tela dedicada:
  - `lib/features/health/presentation/screens/dog_health_prontuario_screen.dart`
- Prontuario reorganizado em abas:
  - `Resumo`
  - `Vacinas`
  - `Peso`
  - `Nutricao`
  - `Docs`
- Nao foi criada aba "Historico"; o historico completo abre em tela focada.
- O tab bar inferior do app foi preservado; mockups serviram como referencia visual, nao como navegacao nova.

### Resumo

- Aba Resumo virou hub de leitura:
  - proximas acoes;
  - evolucao compacta do peso;
  - ultimos eventos;
  - atalho para historico unificado.
- Removido botao de acao da aba Resumo.

### Vacinas, Peso e Docs

- Vacinas reorganizadas com carteira, proximas aplicacoes e historico do tema.
- Peso passou a usar `weight_records` como fonte canonica.
- `health_events.weight` permanece apenas como leitura legada/coexistencia.
- Aba Docs manteve documentos raiz, sem migrar para `dogs/{dogId}/documents`.
- Upload de PDF/laudo segue funcionando, mas a acao agora fica no Hub de saude.

### Nutricao

- Nutricao foi integrada ao prontuario reaproveitando a base existente:
  - `NutritionService`
  - `NutritionViewModel`
  - `NutritionPrescription`
  - `todayFeedings`
  - `FeedingRegistrationScreen`
- `hydration_notes` ficou como campo simples na prescricao.
- Suplementos ganharam dominio proprio:
  - `lib/features/nutrition/domain/nutrition_supplement.dart`
- Tela de registro de nutricao passou a ter duas abas:
  - `Alimentacao`
  - `Suplementos`
- Registro de suplemento coleta:
  - nome do produto;
  - quantidade/dose;
  - motivo.

### FAB e Hub de acoes de saude

- Botoes de acao dentro das abas foram removidos.
- Criado FAB unico com icone de saude no prontuario.
- FAB abre o Hub de acoes de saude usando o visual dos mockups:
  - card do cao;
  - cards por categoria;
  - selecao com destaque;
  - botao `Continuar`.
- Acoes disponiveis no Hub:
  - Vacina;
  - Peso;
  - Nutricao;
  - Documento/PDF;
  - Antiparasitario;
  - Exame;
  - Consulta;
  - Medicacao;
  - Sintoma observado;
  - Cirurgia;
  - Outro.
- Peso abre modal com slider pre-carregado no peso atual.
- Nutricao abre o fluxo de alimentacao/suplementos.
- Documento/PDF abre o fluxo de anexar laudo/documento.

### Historico unificado

- `history_data_loader`, filtros e tela de historico foram ajustados para o modo de prontuario.
- Historico unificado agrega eventos de saude, peso, documentos e nutricao sem recriar uma agregacao paralela desnecessaria.

## Arquivos principais alterados/criados

### Notificacoes

- `lib/core/domain/notification_item.dart`
- `lib/core/services/notification_service.dart`
- `lib/core/services/push_notification_service.dart`
- `lib/core/widgets/binomio_header.dart`
- `lib/features/occurrences/presentation/screens/pending_screen.dart`
- `lib/features/occurrences/presentation/widgets/pending_badge.dart`
- `functions/src/index.ts`
- `firestore.rules`
- `tools/backfill_notification_resolution.js`
- `test/core/domain/notification_item_test.dart`
- `tools/rules_tests/rules_tests.mjs`

### Saude / Prontuario

- `lib/features/health/presentation/screens/dog_health_prontuario_screen.dart`
- `lib/features/health/presentation/screens/health_type_selector_screen.dart`
- `lib/features/health/data/health_service.dart`
- `lib/features/dogs/data/dog_profile_service.dart`
- `lib/features/dogs/data/weight_history_service.dart`
- `lib/features/nutrition/data/nutrition_service.dart`
- `lib/features/nutrition/domain/nutrition_prescription.dart`
- `lib/features/nutrition/domain/nutrition_supplement.dart`
- `lib/features/nutrition/presentation/screens/feeding_registration_screen.dart`
- `lib/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart`
- `lib/features/history/presentation/screens/history_data_loader.dart`
- `lib/features/history/presentation/screens/history_filters.dart`
- `lib/features/history/presentation/screens/history_screen.dart`

### Specs e mockups adicionados ao repo

- `temp/docs/ESPEC_TECNICA_PARTE_14.md`
- `temp/docs/ESPEC_TECNICA_PARTE_15.md`
- `temp/mockups/notificacoes_v2.html`
- `temp/mockups/saude_hub.png`
- `temp/mockups/saude_prontuario.png`

## Validacoes

- `dart analyze` focado nas telas/fluxos de saude e nutricao tocados: sem issues.
- `flutter build apk --debug`: passou.
- `flutter build apk --release`: passou.
- APK release copiado para:
  - `G:\Meu Drive\app k9\claude\app-release.apk`
- Tamanho do APK copiado:
  - `157383138` bytes
- SHA1 do APK:
  - `A915EBA115A2A9442FEF1FEA8C0D44C7B158A31A`
- Validacao no celular reportada pelo usuario antes do commit/merge/push.

## Observacoes importantes

- O prontuario de saude ficou como modulo de saude, sem especialidades operacionais.
- Especialidades operacionais permanecem no contexto de treino/hub operacional.
- Acoes acionaveis de notificacao nao podem ser esquecidas por limpeza manual; a resolucao deve vir do estado real.
- Treino/promocao continua dependente de Function para transicoes sensiveis.
- O build pode imprimir `O sistema nao pode encontrar o caminho especificado` depois de concluir; nesta sessao isso foi apenas ruido pos-build, pois o APK foi gerado e conferido byte a byte no Drive.

## Proximos cuidados

- Validar visual fino do FAB/Hub de saude em aparelhos com alturas diferentes.
- Conferir se todos os eventos de nutricao/suplementos aparecem como esperado no historico unificado.
- Quando houver tela Admin web, ligar o CRUD de configuracoes/curriculos/papeis sem mudar os contratos mobile ja consolidados.
