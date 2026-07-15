# Health v1.0 — Inventário de perfis e capabilities

| Campo | Valor |
|-------|-------|
| Status | Proposto |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `52dae0b683f508affcae0d58cc0931288821d738` |
| Escopo | Modelo real de autorização encontrado no app e implicações para Health v1 |

## 1. Fontes analisadas

- `lib/features/users/domain/user.dart`;
- `lib/features/users/data/user_service.dart`;
- `lib/features/auth/data/auth_service.dart`;
- `lib/features/training/data/training_promotion_service.dart`;
- `firestore.rules` (somente leitura);
- referências a `accessLevel`, roles, claims, profiles e permissions em `lib/`;
- `docs/health/HEALTH_V1_PERMISSION_MATRIX.md` como contrato conceitual aprovado.

## 2. Modelo atual encontrado

O aplicativo não possui hoje uma classe Dart central de capabilities de negócio. Há quatro mecanismos coexistentes:

1. `UserModel.accessLevel`, com valores documentados no código como `Admin` ou `Condutor` e fallback `Condutor`;
2. `UserModel.specialties`, lista literal administrada pelo painel web, incluindo valores como `Condutor K9`, `Adestramento`, `Veterinário` e `Administrativo`;
3. claims de autenticação lidas nas Rules (`admin`, `role`, `roles`, `ra`, `access_profile_id`, `access_scope`, `mobile_access`, `web_access` e claims específicas de treinamento);
4. `access_profiles/{profileId}.permissions[moduleId][action]`, consultado pelas Rules por `hasAccessPermission(moduleId, action)`.

O profile efetivo vem primeiro do espelho `users/{ra}.access_profile_id`/`accessProfileId`; se ausente, usa claim `access_profile_id`; se ainda ausente, o fallback é `operador_k9`. O profile precisa ter `status == active`.

`isAdmin()` concede bypass nas Rules quando existe claim `admin == true`, `role` igual a `admin`/`administrador`, ou esses valores na lista `roles`.

## 3. Perfis, roles e capabilities efetivamente existentes

| Conceito | Valores/formato encontrados | Fonte |
|----------|-----------------------------|-------|
| Nível no model mobile | `Admin`, `Condutor` | `UserModel.accessLevel` |
| Roles em claims | string `role` e lista `roles`; aliases `admin`, `administrador`; roles específicas de training/inventory | `firestore.rules` |
| Perfil de acesso | ID em `access_profile_id`/`accessProfileId`; fallback `operador_k9` | Rules + documento de usuário |
| Permissão efetiva | `permissions[moduleId][action] == true` | `access_profiles` nas Rules |
| Escopo | `access_scope`, com suporte a `own_records` | claims/Rules |
| Health atual | `health_events` usa acesso ao K9 + contrato genérico de auditoria; ação `health/create` aparece somente na atualização de snapshots denormalizados do K9 | `firestore.rules` |

Não foi encontrado no código mobile um catálogo real com nomes `health.read`, `health.reopen_case`, `health.cancel_case` ou demais capabilities granulares da Permission Matrix. Esses nomes permanecem propostas documentais, não permissões implantadas.

## 4. Onde as permissões são verificadas

- Firestore Rules: helpers `isAdmin`, `hasRole`, `activeProfileGrants`, `hasAccessPermission` e verificações por módulo/ação;
- services específicos: Training consulta claims diretamente para reconhecer instrutor;
- model/UI: `accessLevel`, `isK9Instructor`, `trainingRole` e `specialties` orientam comportamentos locais;
- Health legado: não foi encontrada checagem Dart granular de capability antes das operações de `HealthService`. As Rules de `health_events` exigem autenticação, acesso ao K9 e auditoria válida para create/update, mas não chamam `hasAccessPermission('health', ...)`. A ação `health/create` é exigida separadamente apenas para atualizar campos denormalizados `_last_*` no documento do K9.

`lib/core/services/permission_service.dart` trata permissões do dispositivo (localização, storage e fotos) e não é autorização de negócio.

## 5. Inconsistências e lacunas

- `accessLevel` usa capitalização e semântica diferentes dos aliases de claims;
- specialties são strings literais, não grants de autorização;
- algumas features consultam claims diretamente, enquanto outras dependem apenas das Rules;
- o fallback `operador_k9` pode conceder grants definidos externamente e não visíveis no repositório;
- o conteúdo real dos documentos `access_profiles` não está versionado neste repositório;
- a Permission Matrix descreve capabilities Health mais granulares do que as ações Health encontradas nas Rules;
- “Veterinário” em specialties não equivale ao profissional externo do contrato Health v1 e não deve virar role clínica automaticamente.

## 6. Implicações para o Health v1

- a Fase 1B não pode atribuir capabilities Health a `Admin`, `Condutor`, specialties ou profiles;
- contratos Dart de domínio não devem embutir autorização por perfil;
- uma futura fase de autorização precisará mapear capabilities aprovadas para `permissions.health.<action>` ou contrato equivalente;
- o inventário real dos documentos `access_profiles` e claims emitidas pelo backend é gate antes de alterar Rules;
- futuros writes e operações protegidas do Health v1 deverão permanecer indisponíveis — fail-closed — até que o mapeamento de capabilities e as respectivas Rules tenham sido implementados e testados. O Health legado continua submetido às regras atuais durante a coexistência.

## 7. Decisões que ainda não podem ser tomadas

- nomes finais das ações Health no profile;
- grants de cada profile real;
- compatibilidade entre ações genéricas atuais e capabilities granulares;
- política de migração de profiles existentes;
- tratamento de usuários com specialty `Veterinário`;
- necessidade de claims adicionais.

## 8. Recomendações futuras

1. inventariar, de forma read-only e anonimizada, os IDs e grants reais de `access_profiles`;
2. definir tabela explícita capability conceitual → módulo/ação persistida;
3. validar emissão e refresh das claims relacionadas a profile e escopo;
4. criar testes de Rules por capability antes de qualquer ativação funcional;
5. manter specialties apenas como qualificação cadastral, salvo decisão humana expressa em contrário.

Nenhuma capability, role, claim ou permissão foi criada ou alterada nesta fase.
