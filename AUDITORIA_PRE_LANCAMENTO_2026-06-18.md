# Auditoria Pré-Lançamento — Canil K9 GCM Limeira

**Data:** 2026-06-18
**Versão atual:** 1.0.0+2
**Escopo:** Análise estática do código, sem alteração de arquivos.
**Foco:** auditoria técnica, arquitetura/boas práticas Flutter, design e UX.

---

## TL;DR — Veredito Pré-Lançamento

O app está **maduro para teste fechado (TestFlight/Faixa de Testadores Internos)**, **MAS NÃO ESTÁ PRONTO para Google Play público ou App Store**. Existem 4 bloqueadores objetivos:

1. **`applicationId = "com.example.canil_gcm"`** — namespace genérico do template Flutter. A Play Store **vai rejeitar** ou você ficará preso a esse ID para sempre.
2. **`signingConfig = signingConfigs.getByName("debug")`** — APK release está assinado com chave debug. **Nenhuma loja aceita.**
3. **Sem pasta `ios/`** — projeto iOS nunca foi gerado. App Store impossível.
4. **`FirebaseAppCheck` ativado com `AndroidDebugProvider` permanente** em produção — em release isso deixa o App Check inútil.

Os dois primeiros são **bloqueadores formais de loja**. O 3º bloqueia totalmente iOS. O 4º é um buraco de segurança em produção.

Fora isso, o app tem qualidade técnica acima da média: arquitetura coerente, regras Firestore robustas (1970 linhas, com claims, audit trail, soft delete), trilha de auditoria com SHA-256, integração com Cloud Functions, ProGuard configurado, 26 testes (inclui rules tests), e documentação interna sólida em `temp/docs/` e `temp/memory/`.

---

## 1. PERFIL DO PROJETO

| Item | Valor |
|------|-------|
| Stack | Flutter (Dart 3.11+), Firebase (Auth/Firestore/Storage/Functions/Messaging/App Check) |
| State management | Provider + ChangeNotifier (consistente em todas as features) |
| Navegação | Navigator manual + `IndexedStack` (README menciona go_router, mas **não é usado** — discrepância de doc) |
| Tema | Apenas `darkTheme` aplicado, sem `lightTheme` nem `ThemeMode.system` |
| Backend | Firebase + Cloud Functions região `southamerica-east1` |
| IA | Cloud Function `generateOccurrenceAiDraft` (não há OpenAI key no client — ótimo) |
| Painel admin | App web React separado (mesmo Firestore) |
| Plataformas configuradas | ✅ Android · ❌ iOS · ⚠️ Web (parcial, só hosting de verificação) |
| Versão | 1.0.0+2 |
| Tamanho APK release | ~157 MB (gigante — ver seção performance) |

**Domínio:** prontuário operacional, defesa profissional, gestão de turnos e ocorrências do canil K9 da Guarda Civil Municipal de Limeira. 6 condutores ativos, 2 cães em uso real (Bono e Apolo).

---

## 2. ARQUITETURA E ORGANIZAÇÃO

### Features identificadas (clean architecture por feature)
`auth · dogs · users · profiles · shifts · occurrences · training · health · nutrition · conditioning · history · app_shell`

Estrutura padrão em cada feature: `data/` · `domain/` · `presentation/{screens,viewmodels,widgets,controllers,view_models}`.

> ⚠️ **Inconsistência menor:** algumas features usam `presentation/viewmodels/` (training, dogs, auth, shifts), outras usam `presentation/view_models/` (occurrences). Não quebra nada, só polui imports e dificulta navegação. Padronizar pós-lançamento.

### Core compartilhado bem estruturado
`core/services/` (~30 services), `core/widgets/` (~20 widgets de UI tática), `core/domain/`, `core/theme/`, `core/mixins/SoftDeletable`, `core/utils/`.

### Bootstrap em `main.dart`
- ✅ `Firebase.initializeApp()` sem `DefaultFirebaseOptions` — depende dos arquivos `google-services.json` (presente)
- ✅ `FirebaseMessaging.onBackgroundMessage` configurado
- ⚠️ `App Check` ativado com **`AndroidDebugProvider`** dentro de try/catch. Em release isso desativa proteção real. Precisa de Play Integrity provider.
- ⚠️ **Não tem `firebase_options.dart`** (gerado pelo FlutterFire CLI) — funciona, mas dificulta multi-flavor e CI.
- ⚠️ **9 `ChangeNotifierProvider` instanciados eagerly no root** — todos sobem juntos. Razoável agora, mas se crescer vale migrar pra `lazy: true` ou `Provider.value` por escopo.

### Pontos fortes
- Separação data/domain/presentation respeitada
- Repositórios encapsulam `FirebaseFirestore` corretamente
- ViewModels usam stream subscription com dispose adequado
- Mixin `SoftDeletable` reutilizado

### Pontos a melhorar (não bloqueiam lançamento, mas degradam manutenção)
- Arquivos enormes na feature `shifts` (`dynamic_activity_sheet*` quebrado em 11 partes — sinal de complexidade)
- 22 arquivos com `// ignore:` ou `// ignore_for_file:` — vale revisar
- 4 `catch (e) {}` vazios espalhados em 5 arquivos críticos (occurrence_view_model, detection_formation_screen, active_shift_dashboard, edit_event_screen, handler_profile_page) — engolem erros silenciosamente

---

## 3. SEGURANÇA — Análise por categoria

### 🟢 EXCELENTE: Firestore Rules
`firestore.rules` tem **1970 linhas** com:
- Sistema de roles, claims, perfis de acesso (`access_profiles`)
- Função `emailMatchesRa()` para validar identidade do usuário
- Hierarquia de permissões por módulo + ação
- Validação de payload (`keys().hasOnly([...])`) em quase todos os `create`/`update`
- Auditoria obrigatória inline (`canCreateAuditedRecord`, `appendsInlineAuditOnUpdate`)
- Soft delete só permitido com `delete_reason` preenchido
- Bloqueio de write em `vehicles`, `inventory_*`, `binomials`, `effective_movements` (só admin web cria/edita)
- Fallback `match /{document=**} { allow read, write: if false; }`
- Regras especiais para fluxo de assinaturas, amendments e participações em ocorrência

**Esse arquivo é o maior diferencial de segurança do projeto.** Não tenho ressalvas materiais; só recomendaria escrever testes de rules adicionais para os caminhos novos (já existe `tools/rules_tests/rules_tests.mjs`).

### 🟢 BOM: Storage Rules
- Tipos MIME validados (image/*, application/pdf)
- Limites de tamanho explícitos por endpoint (10MB/20MB)
- Caminhos segmentados por dogId e protegidos por `canAccessDogRecord`
- Falback `allow read, write: if false`

### 🟢 BOM: Sem secrets hardcoded
Grep por `AIza|sk-|pk_live|Bearer|api_key|apiKey|API_KEY` em `lib/`: **zero matches**. A integração com IA é via `cloud_functions.httpsCallable('generateOccurrenceAiDraft')` — chave do LLM fica no backend. Correto.

URLs `https://` externas presentes em `lib/`:
- `https://photon.komoot.io` (geocoding — OK)
- `https://api.open-meteo.com` (clima — OK)
- `https://*.basemaps.cartocdn.com` (tiles de mapa — OK)
- `https://canil-gcm.web.app/v` (verificador público — OK)
- Tudo HTTPS, sem `http://` inseguro.

### 🟡 ATENÇÃO: App Check
```dart
await FirebaseAppCheck.instance
    .activate(providerAndroid: const AndroidDebugProvider())
```
`AndroidDebugProvider` em release **não protege nada**. O App Check vira teatro.
**Solução:** trocar por `AndroidProvider.playIntegrity` (e, ao gerar build de debug local, manter `androidDebug` via flavor).

### 🟡 ATENÇÃO: Auth por R.A. → email sintético
`signInWithRaAndPassword(ra, password)` monta `email = '$ra@gcm.com.br'`. Funciona, mas:
- Se um RA for descomissionado, o email continua sendo aceito por força do Auth
- Não há fluxo de reset de senha visível para o condutor

### 🟡 ATENÇÃO: `.gitignore`
- Arquivos `*.env` ignorados ✅
- **`google-services.json` NÃO está no `.gitignore`** e está commitado (`android/app/google-services.json`). Para projeto Firebase isso é tecnicamente aceitável (as chaves Web do Firebase não são secretas — segurança vem das rules), mas é prática institucional questionável quando você vai abrir o repo.
- **`local.properties` está commitado** com `flutter.sdk=C:\\flutter` e `sdk.dir=C:\\android\\sdk` — vaza ambiente do dev. **Adicionar ao gitignore**.
- Pasta `.kilo/worktrees/` e `.claude/worktrees/` com 28+ pubspec duplicados — sujeira que cresce com o tempo. Já está parcialmente no gitignore (`.claude/worktrees/`), mas `.kilo/worktrees/` **não** está.
- Arquivos `.iml` (`android/canil_gcm_android.iml`) commitados — IDE-specific, ignorar.

### 🟡 LGPD/PII
- Projeto coleta: nome, RA, foto, GPS, biometria (`local_auth`).
- Não localizei: política de privacidade, termo de consentimento, fluxo de exclusão de dados.
- Como o app é uso interno e órgão público, isso pode estar coberto por instrução normativa da GCM, mas é bom formalizar.

---

## 4. CONFIGURAÇÕES ANDROID — Estado

### 🔴 BLOQUEADORES de loja
| Item | Estado | Impacto |
|------|--------|---------|
| `applicationId` | `com.example.canil_gcm` | **Bloqueador**: padrão do template; Play Console rejeita "com.example.*". Definir ex.: `br.gov.limeira.gcm.canilk9` |
| `signingConfig` (release) | `signingConfigs.getByName("debug")` | **Bloqueador**: APK release assinado com debug-key. Criar keystore real, armazenar fora do repo |
| Namespace Kotlin | `com.example.canil_gcm` em `MainActivity.kt` | Acompanha mudança do applicationId |

### 🟢 BEM CONFIGURADO
- `minifyEnabled = true` + `shrinkResources = true` (R8 ativo)
- `proguard-rules.pro` com regras corretas para Firebase, Glide, OkHttp, Flutter
- `multiDexEnabled = true`
- `isCoreLibraryDesugaringEnabled = true` (necessário pra `flutter_local_notifications`)
- Java/Kotlin 17
- Splash via `LaunchTheme` configurado em `styles.xml`

### 🟡 PERMISSÕES — manifest declara
Internet, GPS (fine+coarse), foreground service location, wake lock, leitura de mídia, câmera, notificações, vibração, gravação de áudio, biometria. **Todas justificadas pelo escopo do app**, mas:
- `READ_EXTERNAL_STORAGE` sem `maxSdkVersion="32"` — Android 13+ exige `READ_MEDIA_IMAGES` (que já está) e ignora READ_EXTERNAL_STORAGE. Limite explícito reduz warning na Play Console.
- `FOREGROUND_SERVICE_LOCATION` exige declaração do tipo de uso de localização desde Android 14 — verificar se runtime declara o `foregroundServiceType` corretamente.
- Falta `android:label="K9 Ops"` ser revisto — esse vai ser o nome do app na home. Confirmar que é como você quer mostrar.

### 🟡 ÍCONE / SPLASH
- `flutter_launcher_icons` configurado e ícones presentes em `mipmap-*dpi/`.
- Splash usa `launch_background.xml` padrão — não vi `flutter_native_splash` no pubspec. Pode quer instalar pra ter splash bonito multi-plataforma.

---

## 5. iOS — Estado

**A pasta `ios/` não existe no projeto.**

Implicações:
- Build iOS impossível.
- App Store impossível.
- Você precisa rodar `flutter create --platforms=ios .` na pasta do projeto, configurar `Info.plist` (todas as Usage Descriptions: NSCameraUsageDescription, NSLocationWhenInUseUsageDescription, NSLocationAlwaysAndWhenInUseUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSFaceIDUsageDescription), adicionar `GoogleService-Info.plist`, configurar bundle ID, signing, deployment target ≥ 13.

**Se o público são só guardas Android, isso é uma decisão consciente.** Mas então atualize o README e desligue ios em `flutter_launcher_icons` (já está com `ios: false`, ótimo).

---

## 6. PERFORMANCE — Achados objetivos

### 🔴 APK release ~157 MB
Conforme `SESSAO_2026-06-03`, o APK release final tem **~157 MB**. Isso é grande demais para um app de gestão. Causas prováveis:
- `flutter_map_tile_caching` + tiles em assets
- `google_fonts` baixando fontes em runtime mas também empacotando
- 24 imagens PNG em `assets/images/` (cards, ícones, ações) que poderiam virar SVG ou ser comprimidas
- ABI universal — não está dividindo por arquitetura

**Soluções:**
1. Gerar **App Bundle** (`flutter build appbundle --release`) — Play Store entrega APK por arquitetura, baixa pra ~50 MB por device.
2. `--split-per-abi` se ficar em APK puro.
3. Comprimir PNGs grandes (pngcrush/pngquant).
4. Converter ícones de cards pra SVG via `flutter_svg`.
5. Avaliar uso real de `flutter_map_tile_caching` (a auditoria interna diz que **está declarado mas não usado** — remover).

### 🟡 Logs em produção
**94 ocorrências** de `print()` ou `debugPrint()` em 22 arquivos de `lib/`. `debugPrint` é silencioso em release, mas qualquer `print()` puro vaza pra logcat. Vale rodar `flutter analyze` com `avoid_print` ativado.

### 🟡 Sem Crashlytics / Sentry
**Não localizei nenhum logging remoto** (`FirebaseCrashlytics`, `Sentry`, `FlutterError.onError`). Para um app que precisa "defender o condutor 6 meses depois", você quer saber **agora** se algo crashou em campo, não receber feedback verbal do guarda.

**Recomendação forte:** adicionar `firebase_crashlytics` antes do teste fechado.

### 🟡 Sem offline-first
Conforme auditoria interna anterior: o app depende totalmente de conectividade Firestore. SDK do Firestore tem cache nativo, mas writes em campo sem sinal podem ser perdidos. Para uso operacional em viaturas, isso é um risco real.

---

## 7. QUALIDADE DE CÓDIGO

### 🟢 Testes — 26 arquivos em `test/`
Cobrem:
- `audit_service`, `hash_service`, `integrity_verification_service`, `occurrence_finalization_service`, `active_shift_identity_service`
- `notification_item`, `soft_deletable`
- Repositories: `occurrence_repository`, `occurrence_event_repository`, `amendment_repository_extended`
- Domain: `occurrence`, `occurrence_event`, `occurrence_models`, `detection_phase_config`, `occurrence_nature`
- Data services: `detection_service`, `dog_command_service`, `training_service`, `training_program_service`
- ViewModels: `health_viewmodel`, `occurrence_view_model_initial_event`
- 1 widget test: `detection_formation_screen_test`
- 1 integration test: `fronte_c_integration_test`
- 1 helper: `firebase_test_helper` (com `fake_cloud_firestore`)

**Boa cobertura para a camada crítica (auditoria, integridade, soft delete).** Falta cobertura widget e e2e.

### 🟡 Lints
`analysis_options.yaml` só inclui `flutter_lints` padrão. Para um projeto público você ganharia muito com `very_good_analysis` ou pelo menos ativar:
- `avoid_print`
- `prefer_const_constructors` / `prefer_const_literals_to_create_immutables`
- `require_trailing_commas`
- `unawaited_futures`
- `use_build_context_synchronously`

### 🟡 Código grande
Auditoria anterior cita `guard_protection_screen.dart` com 2384 linhas e `occurrence_pdf_generator.dart` com 2546 linhas. A feature `shifts` foi quebrada em 11 arquivos parciais (`_dynamic_activity_sheet_*`) — sinal de complexidade indomável. Refatoração não bloqueia o lançamento, mas é dívida.

### 🟢 TODOs / FIXMEs
Apenas 4 ocorrências de TODO/FIXME/HACK em 3 arquivos (`seal_detail_sheet`, `login_screen`, `seal_definitions`). Muito limpo pra um projeto desse porte.

---

## 8. UI / UX

- ✅ Tema escuro (`AppTheme.darkTheme`) — apropriado pro contexto operacional/tático
- ❌ **Não tem `darkTheme` + `lightTheme` + `ThemeMode.system`** — força escuro mesmo se Android estiver em claro. Decisão proposital ("tom institucional sério" no resumo executivo), mas vale documentar.
- ✅ Componentes táticos próprios (`tactical_card_*`, `hud_*`) — design system razoável
- ✅ Tem widget `app_feedback.dart` (provavelmente snackbar/dialog padronizados)
- ⚠️ Sem i18n — todo texto está em pt-BR hardcoded. OK pra uso interno em Limeira; não OK se for replicar pra outros municípios.
- ⚠️ Sem `Semantics` nem labels de acessibilidade — risco se algum guarda precisar TalkBack
- ⚠️ Sem `LayoutBuilder`/responsividade tablet — provavelmente celular-only
- ⚠️ Auditoria interna cita: "sem indicador de loading no histórico", "PopScope em só 7 telas críticas, não em todas"

---

## 9. CHECKLIST DE LANÇAMENTO

### 🔴 Bloqueadores formais (para Play Store / App Store)
- [ ] Trocar `applicationId` de `com.example.canil_gcm` para algo institucional (ex.: `br.gov.sp.limeira.gcm.canilk9`)
- [ ] Criar keystore de release, configurar `key.properties` fora do repo, ajustar `build.gradle.kts` `signingConfigs.release`
- [ ] Trocar `AndroidDebugProvider` por `playIntegrity` em release no App Check
- [ ] Gerar pasta `ios/` e configurar tudo, OU declarar oficialmente "Android-only"
- [ ] Decidir destino: Play Store pública, faixa interna, sideload via apk? Cada um exige config diferente.

### 🟠 Importantes (recomendado antes do lançamento)
- [ ] Adicionar `firebase_crashlytics` (ou Sentry)
- [ ] Adicionar `firebase_options.dart` via FlutterFire CLI (preparar multi-flavor)
- [ ] Configurar `flutter_native_splash` (splash tela cheia)
- [ ] Build via `--split-per-abi` ou `appbundle` → reduzir 157 MB
- [ ] Comprimir PNGs de `assets/images/`
- [ ] Remover `flutter_map_tile_caching` do pubspec (não é usado)
- [ ] Adicionar `local.properties` e `*.iml` ao `.gitignore`; mover `.kilo/worktrees/` pro ignore
- [ ] Cobrir os `catch (e) {}` vazios com logging ao menos
- [ ] Configurar `FlutterError.onError` e `PlatformDispatcher.instance.onError`
- [ ] Decidir e implementar política de retenção/exclusão de dados (LGPD)
- [ ] Verificar se Cloud Function `generateOccurrenceAiDraft` tem rate limit e checagem de auth/role
- [ ] Validar que o endpoint `/v/{id}` está deployado em `canil-gcm.web.app` (referenciado no PDF)

### 🟡 Boas práticas (pode esperar pós-lançamento)
- [ ] Refatorar `guard_protection_screen.dart` (2384 linhas)
- [ ] Refatorar `occurrence_pdf_generator.dart` (2546 linhas)
- [ ] Padronizar `viewmodels/` vs `view_models/`
- [ ] Adicionar lints estritos (`very_good_analysis`)
- [ ] Implementar offline-first com `hive` ou `isar` na fila de writes
- [ ] Adicionar i18n (mesmo só pt-BR, prepara o caminho)
- [ ] Cobrir 100% das telas com `PopScope` adequado
- [ ] Adicionar testes widget e e2e
- [ ] Loading skeleton no histórico

---

## 10. PONTOS FORTES (pra não esquecer)

- Trilha de auditoria + soft delete bem implementados
- Integridade SHA-256 com verificador público
- Regras Firestore extremamente robustas (raras de ver tão completas)
- IA via Cloud Function (chave protegida)
- ProGuard configurado corretamente
- Documentação interna em `temp/docs/` e `temp/memory/` é de excelente qualidade
- Decisões arquiteturais conscientes (refatoração gradual, soft delete, EXIF preservado, hash imutável)
- Modelos de dados bem isolados em `domain/`
- Cloud Functions na região correta (`southamerica-east1`)
- Hash canônico alinhado entre Dart e Function (v1..v4) — raríssimo de fazer direito

---

## Conclusão

**O app está tecnicamente sólido**. A camada de segurança é provavelmente o ponto mais forte que vi num app Flutter desse porte. O que falta é **pré-flight de loja**: identidade do pacote, chave de assinatura real, App Check em modo produção, e decisão sobre iOS.

**Recomendo:**
1. Resolver os 4 bloqueadores formais (1-2 dias).
2. Adicionar Crashlytics e otimizar tamanho do APK (1-2 dias).
3. Publicar em faixa de testes fechada (interno) por 1-2 semanas com os 6 condutores.
4. Promover para produção depois.

---

*Relatório gerado por análise estática do código em 18/06/2026. Nenhum arquivo do projeto foi alterado.*
