# Bíblia Técnica Web - Canil GCM K9

Gerado em: 2026-06-05  
Projeto Firebase: `canil-gcm`  
Base de domínio: app mobile Flutter em `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm`  
Objetivo: planejar o novo painel web do zero, herdando os contratos corretos do mobile e adicionando módulos próprios de gestão.

> O web não será uma versão grande do mobile. Ele será o console de gestão do Canil K9.
> O mobile continua sendo a base operacional de campo. O web será a base de gestão, administração,
> relatórios, cadastros, matriz de treinamento e controle de estoque.

---

## 1. Decisão Arquitetural

Vamos começar um projeto web novo, do zero.

Stack escolhida:

| Camada | Decisão |
|---|---|
| Linguagem | TypeScript |
| Framework | Next.js com App Router |
| UI | Tailwind CSS + shadcn/ui |
| Auth | Firebase Auth |
| Dados | Cloud Firestore |
| Arquivos | Firebase Storage |
| Server-side | Cloud Functions existentes + novas Functions quando necessário |
| Deploy | Firebase App Hosting ou Firebase Hosting, a decidir conforme uso server-side |
| Gráficos | Recharts ou Tremor/Recharts, a decidir no scaffold |
| Tabelas | TanStack Table |
| Formulários | React Hook Form + Zod |
| Datas | date-fns |

Motivo:

- TypeScript reduz erro em contratos Firestore complexos.
- Next.js é adequado para painel administrativo.
- Tailwind/shadcn acelera dashboard, tabelas, filtros, cards e forms.
- Firebase já é a fonte operacional do projeto.
- O web precisará de telas densas, CRUD, relatórios e filtros, não de UX mobile.

---

## 2. Papel do Web no Ecossistema

### Mobile

Usado em campo:

- assumir turno;
- registrar ocorrência;
- registrar treino;
- registrar saúde/nutrição;
- rastrear trilha;
- assinar/revisar;
- receber notificações;
- operar com foco em poucos toques.

### Web

Usado em gestão:

- administrar efetivo K9;
- administrar efetivo humano;
- administrar viaturas;
- consultar e auditar ocorrências;
- aprovar evolução de treino;
- gerenciar Matriz de Treinamento;
- controlar estoque;
- gerar relatórios;
- acompanhar indicadores;
- configurar cadastros e permissões.

Regra superior:

> O web herda regras de domínio, Firestore, Functions, auditoria e integridade.  
> O web não herda bottom nav, FAB, sheets, telas estreitas ou atalhos mobile.

---

## 3. Princípios Não Negociáveis

1. **Nada institucional some sem trilha.**
   - Preferir `deleted_at`, `deleted_by`, `delete_reason`.
   - Hard delete só quando regra permitir explicitamente.

2. **Ações sensíveis rodam no servidor.**
   - Aprovar evolução.
   - Atribuir Instrutor K9.
   - Selar ocorrência.
   - Assinar ocorrência.
   - Corrigir histórico.
   - Futuramente: publicar versão de Matriz de Treinamento.

3. **Ocorrência finalizada é documento selado.**
   - Hash/verificador são parte do domínio.
   - Web deve respeitar `integrity_hash`, `hash_version`, `finalized_at`.

4. **Treino não é ocorrência.**
   - Treino é auditável, mas não tem hash de prova.
   - Não introduzir selo probatório em treino.

5. **Pendência acionável não é lixeira.**
   - `action_required == true && resolved_at == null` significa pendência aberta.
   - `read_at` só marca leitura.
   - `archived_at` só para avisos.

6. **Currículo de treino é dado, não código.**
   - No web, o nome de produto será **Matriz de Treinamento**.
   - O Firestore continua usando `training_programs`.

7. **Coexistência importa.**
   - O mobile ainda lê caminhos legados.
   - O web deve começar seguro, sem migração destrutiva.

---

## 4. Módulos Web

Módulos do sistema:

1. Login e Controle de Acesso
2. Dashboard
3. Efetivo K9
4. Efetivo Humano
5. Efetivo de Viaturas
6. Ocorrências
7. Treinamentos
8. Matriz de Treinamento
9. Saúde e Prontuário
10. Estoque
11. Relatórios
12. Notificações e Pendências
13. Administração
14. Auditoria e Integridade

---

## 5. Estrutura Recomendada do Projeto

Nome sugerido:

```txt
canil-gcm-web
```

Estrutura:

```txt
src/
  app/
    (auth)/
      login/
    (app)/
      dashboard/
      k9/
      humans/
      vehicles/
      occurrences/
      training/
      training-matrix/
      health/
      inventory/
      reports/
      notifications/
      admin/
    api/
  components/
    ui/
    layout/
    data-table/
    charts/
    forms/
    status/
  features/
    auth/
    dashboard/
    dogs/
    humans/
    vehicles/
    occurrences/
    training/
    training-matrix/
    health/
    inventory/
    reports/
    notifications/
    admin/
    audit/
  lib/
    firebase/
      client.ts
      admin.ts
      functions.ts
      storage.ts
    permissions/
      roles.ts
      guards.ts
    routes/
      paths.ts
    firestore/
      converters.ts
      timestamps.ts
    utils/
  styles/
    globals.css
```

Padrão por feature:

```txt
features/<module>/
  data/
    queries.ts
    mutations.ts
    converters.ts
  domain/
    types.ts
    schema.ts
    mappers.ts
  components/
  screens/
```

Regras:

- `domain/types.ts`: tipos TypeScript.
- `domain/schema.ts`: Zod schemas.
- `data/queries.ts`: leituras Firestore.
- `data/mutations.ts`: chamadas controladas, preferindo Functions.
- `components/`: UI local do módulo.
- `screens/`: composição de página.

---

## 6. Rotas Web

Rotas iniciais:

```txt
/login
/dashboard
/k9
/k9/new
/k9/[dogId]
/k9/[dogId]/health
/k9/[dogId]/training
/k9/[dogId]/occurrences
/k9/[dogId]/documents

/humans
/humans/new
/humans/[ra]

/vehicles
/vehicles/new
/vehicles/[vehicleId]

/occurrences
/occurrences/[occurrenceId]
/occurrences/[occurrenceId]/review
/occurrences/[occurrenceId]/integrity

/training
/training/promotions
/training/promotions/[requestId]

/training-matrix
/training-matrix/[modality]
/training-matrix/[modality]/versions

/health
/health/alerts

/inventory
/inventory/items
/inventory/items/[itemId]
/inventory/movements
/inventory/categories
/inventory/suppliers

/reports
/reports/occurrences
/reports/training
/reports/health
/reports/inventory
/reports/effectives

/notifications
/admin
/admin/users
/admin/roles
/admin/settings
```

Rota pública já existente no Firebase Hosting:

```txt
/v/** -> Function verifyOccurrence
```

Decisão:

- manter verificador público existente;
- o novo web pode criar uma tela administrativa de integridade, mas não substituir o verificador público sem plano.

---

## 7. Papéis e Permissões

Papéis iniciais:

| Papel | Uso |
|---|---|
| Admin | administração total do sistema |
| Gestor | consulta gerencial, relatórios, efetivo, ocorrências |
| Instrutor K9 | aprovar/rejeitar evolução, consultar treinos e matriz |
| Condutor | consulta operacional e ações próprias |

Claims já existentes para Instrutor K9:

- `role: "instrutor_k9"`
- `roles: ["instrutor_k9"]`
- `instrutor_k9: true`
- `training_role: "instrutor_k9"`
- `training_instructor: true`

Espelho em `users/{ra}`:

- `is_k9_instructor`
- `training_role`
- `claim_role`
- `claim_refresh_required`

Function existente:

- `setK9InstructorRole`

Regras:

- UI pode ler espelho em `users`.
- Autorização real deve depender de claims e rules.
- Admin web deve chamar Function para alterar papéis, não editar claims diretamente.

Papéis novos a decidir:

- `admin`
- `gestor`
- `inventory_manager`
- `fleet_manager`
- `health_manager`

Decisão pendente:

- se usaremos um claim `roles: string[]` como principal para todos os papéis ou se manteremos campos específicos por compatibilidade.

Recomendação:

- padronizar no web em `roles: string[]`;
- manter compatibilidade com claims antigos;
- espelhar permissões necessárias em `users/{ra}` para UI.

---

## 8. Dashboard

Dashboard deve ser a primeira tela após login.

Blocos sugeridos:

- cães ativos;
- turnos ativos;
- ocorrências abertas;
- ocorrências aguardando assinatura;
- promoções de treino pendentes;
- alertas de saúde;
- estoque crítico;
- documentos/laudos recentes;
- atividades recentes;
- gráfico de ocorrências por período;
- gráfico de treinos por modalidade;
- cards de produtividade.

Dados de origem:

- `dogs`
- `active_shifts`
- `occurrences`
- `promotion_requests`
- `notifications`
- `dogs/{dogId}/health_events`
- `dogs/{dogId}/training`
- `inventory_items`
- `inventory_movements`

Decisão:

- Dashboard v1 pode usar consultas diretas e agregações client-side para MVP.
- Dashboard v2 deve ter agregações server-side se ficar pesado.

---

## 9. Efetivo K9

Módulo: `Efetivo K9`

Objetivo:

- CRUD completo de cães;
- perfil detalhado do K9;
- visão operacional, saúde, treino, ocorrências e documentos.

Coleção herdada:

```txt
dogs/{dogId}
```

Subcoleções herdadas:

```txt
dogs/{dogId}/specialties
dogs/{dogId}/training
dogs/{dogId}/training_sessions
dogs/{dogId}/health_events
dogs/{dogId}/weight_records
dogs/{dogId}/feeding_events
dogs/{dogId}/nutritional_prescriptions
dogs/{dogId}/nutrition_supplements
dogs/{dogId}/documents
dogs/{dogId}/commands
dogs/{dogId}/external_certifications
```

CRUD K9 deve incluir:

- nome;
- raça;
- sexo;
- nascimento;
- matrícula/patrimônio;
- microchip;
- cor;
- status;
- foto;
- condutor principal;
- peso atual;
- faixa ideal de peso;
- observações;
- condição corporal;
- data de entrada;
- data de aposentadoria/licença, quando houver.

Perfil K9 deve mostrar:

- hero do cão;
- status operacional;
- condutor vinculado;
- especialidades;
- Matriz de Treinamento por modalidade;
- saúde;
- nutrição;
- documentos;
- ocorrências;
- histórico.

Regras:

- update deve ser auditado;
- remoção deve ser soft delete;
- especialidades operacionais não pertencem ao prontuário de saúde;
- `dogs/{dogId}/training/{modality}` é a fonte de progressão.

---

## 10. Efetivo Humano

Módulo: `Efetivo Humano`

Objetivo:

- CRUD completo dos GCMs/condutores;
- perfil detalhado do servidor;
- papéis, permissões, histórico e vínculo operacional.

Coleção herdada:

```txt
users/{ra}
```

Subcoleções:

```txt
users/{ra}/devices
```

Campos recomendados:

- RA;
- nome;
- email;
- telefone;
- função/cargo;
- status;
- foto;
- roles;
- `is_k9_instructor`;
- `training_role`;
- auth uid;
- data de ingresso;
- observações;
- audit trail;
- soft delete.

Perfil humano deve mostrar:

- dados cadastrais;
- papéis e permissões;
- cães vinculados;
- turnos recentes;
- ocorrências em que participou;
- assinaturas pendentes/realizadas;
- treinos conduzidos;
- promoções avaliadas, se Instrutor K9;
- dispositivos FCM cadastrados.

Ações sensíveis:

- atribuir/remover Instrutor K9 via Function;
- alterar roles administrativas via Function futura;
- desativar usuário com soft delete.

---

## 11. Efetivo de Viaturas

Módulo: `Efetivo de Viaturas`

Coleção herdada:

```txt
vehicles/{vehicleId}
```

Coleções relacionadas:

```txt
active_shifts/{ra}
vehicle_crews/{crewId}
vehicle_crews/{crewId}/members/{ra}
shift_logs/{shiftId}
occurrences/{occurrenceId}
```

CRUD de viatura deve incluir:

- prefixo;
- placa;
- tipo;
- status;
- unidade/setor;
- observações;
- data de cadastro;
- soft delete/auditoria.

Perfil de viatura deve mostrar:

- status atual;
- guarnição ativa;
- cão de serviço vinculado ao turno;
- condutores no turno;
- ocorrências vinculadas;
- histórico de uso;
- alertas/observações.

Regras:

- viatura não deve ser apagada se houver histórico;
- guarnição por viatura deve manter as regras do mobile;
- convite/aceite de guarnição continua via Functions.

---

## 12. Ocorrências no Web

Módulo: `Ocorrências`

Coleções:

```txt
occurrences/{occurrenceId}
occurrences/{occurrenceId}/events/{eventId}
occurrences/{occurrenceId}/signatures/{signatureId}
occurrences/{occurrenceId}/participations/{handlerId}
occurrences/{occurrenceId}/amendments/{amendmentId}
occurrences/{occurrenceId}/correction_requests/{requestId}
```

Funcionalidades v1:

- listagem com filtros;
- detalhe completo;
- timeline de eventos;
- participantes;
- assinaturas;
- status de integridade;
- link para PDF;
- link para verificador público;
- exportação básica.

Filtros:

- período;
- cão;
- condutor;
- viatura;
- natureza;
- status;
- com pendência de assinatura;
- finalizada/com pendência;
- hash íntegro/quebrado/legado.

Ações:

- revisar ocorrência;
- assinar, se aplicável;
- solicitar correção;
- abrir PDF;
- abrir verificador.

Functions obrigatórias:

- `closeOccurrenceForSignatures`
- `signOccurrence`
- `requestOccurrenceCorrection`
- `acceptOccurrenceParticipation`
- `declineOccurrenceParticipation`
- `sealOccurrenceV4`

Regra:

- não implementar no client web uma transição que o mobile já delega a Function.

---

## 13. Treinamentos

Módulo: `Treinamentos`

Objetivo:

- consultar progresso por cão/modalidade;
- listar sessões;
- aprovar/rejeitar promoções;
- acompanhar cães em formação;
- acompanhar cães operacionais;
- fazer ponte com a Matriz de Treinamento.

Coleções:

```txt
dogs/{dogId}/training/{modality}
dogs/{dogId}/training_sessions/{sessionId}
training_sessions/{sessionId}
trainings/{trainingId}
promotion_requests/{requestId}
training_programs/{modality}
```

Funcionalidades:

- Kanban ou tabela de cães por modalidade/status;
- promoções pendentes;
- detalhe de solicitação;
- comparação entre marcos atingidos e currículo atual;
- histórico de módulos concluídos;
- sessões por modalidade;
- filtros por cão, condutor, modalidade, período.

Regras:

- `dogs/{dogId}/training/{modality}` é progressão canônica;
- `specialties` é espelho/coexistência para hub;
- `completed_modules` é snapshot histórico, não deve ser editado direto;
- correções passam por fluxo auditável.

---

## 14. Matriz de Treinamento

Nome de produto:

```txt
Matriz de Treinamento
```

Nome técnico Firestore:

```txt
training_programs
```

Coleções:

```txt
training_programs/{modality}
training_programs/{modality}/modules/{moduleId}
training_programs/{modality}/modules/{moduleId}/milestones/{milestoneId}
```

O que é:

- programa de formação por modalidade;
- módulos sequenciais;
- marcos obrigatórios e complementares;
- versão do currículo;
- ativação/desativação de itens;
- base para formação/operacional.

Modalidades iniciais:

- Busca & Captura;
- Guarda & Proteção;
- Detecção;
- Obediência;
- Condicionamento Físico.

Funcionalidades v1:

- listar matrizes;
- visualizar módulos e marcos;
- ver versão ativa;
- ver cães impactados;
- modo somente leitura para começar.

Funcionalidades v2:

- criar nova matriz;
- editar módulos;
- editar marcos;
- publicar nova versão;
- adicionar marco complementar;
- auditar alterações;
- notificar cães operacionais sobre marco-bônus quando aplicável.

Regra crítica:

- editar matriz não pode reescrever snapshots antigos em `completed_modules`.
- nova versão deve preservar histórico.
- publicação deve ser transição sensível, preferencialmente via Function.

Recomendação:

- v1: leitura administrativa.
- v2: CRUD protegido para Admin/Instrutor K9.
- v3: versionamento formal com workflow de publicação.

---

## 15. Saúde e Prontuário

Módulo: `Saúde`

Coleções herdadas:

```txt
dogs/{dogId}/health_events
dogs/{dogId}/weight_records
dogs/{dogId}/weight_history
dogs/{dogId}/feeding_events
dogs/{dogId}/feedings
dogs/{dogId}/nutritional_prescriptions
dogs/{dogId}/nutrition_prescriptions
dogs/{dogId}/nutrition_supplements
dogs/{dogId}/documents
documentos/{docId}
```

Funcionalidades:

- prontuário completo por cão;
- vacinas;
- peso;
- nutrição;
- suplementos;
- laudos/documentos;
- alertas;
- histórico clínico;
- upload de PDF;
- filtros por data/tipo.

Regras:

- peso canônico: `weight_records`;
- nutrição canônica: `feeding_events` e `nutritional_prescriptions`;
- documentos têm coexistência;
- documentos não devem ser deletados fisicamente;
- saúde é defesa do cão, mas não tem hash de ocorrência.

Para o web:

- tela deve ser mais tabular e analítica que mobile;
- permitir anexos com preview/download;
- relatórios de saúde devem cruzar vacina, peso, nutrição e documentos.

---

## 16. Estoque

Módulo novo, web-first.

Objetivo:

- controlar insumos do canil;
- registrar entrada/saída;
- manter saldo;
- alertar estoque mínimo;
- controlar validade;
- vincular consumo a cão, condutor, ocorrência ou treino quando fizer sentido.

Exemplos de itens:

- ração;
- suplemento;
- medicamentos;
- guia;
- coleira;
- colar de elos;
- focinheira;
- brinquedos/mordedores;
- mangas/trajes;
- materiais de treino;
- EPIs;
- produtos de limpeza;
- documentos/itens administrativos.

Coleções propostas:

```txt
inventory_categories/{categoryId}
inventory_items/{itemId}
inventory_movements/{movementId}
suppliers/{supplierId}
```

### `inventory_categories/{categoryId}`

Campos:

```txt
name
description
active
created_at
updated_at
audit_trail
deleted_at?
```

Exemplos:

- Alimentação;
- Equipamento;
- Saúde;
- Treinamento;
- Limpeza;
- Administrativo.

### `inventory_items/{itemId}`

Campos:

```txt
name
category_id
category_name
unit
current_quantity
minimum_quantity
status
expiration_date?
supplier_id?
supplier_name?
brand?
description?
storage_location?
created_at
updated_at
audit_trail
deleted_at?
```

Unidades:

- kg;
- pacote;
- unidade;
- caixa;
- frasco;
- comprimido;
- metro;
- par.

Status:

- active;
- low_stock;
- out_of_stock;
- expired;
- inactive.

### `inventory_movements/{movementId}`

Campos:

```txt
item_id
item_name
type
quantity
unit
reason
performed_by_ra
performed_by_name
performed_at
related_dog_id?
related_dog_name?
related_user_ra?
related_occurrence_id?
related_training_session_id?
notes?
created_at
audit_trail
deleted_at?
```

Tipos:

- `entrada`;
- `saida`;
- `ajuste`;
- `descarte`;
- `perda`;
- `vencimento`;
- `transferencia`.

Regra:

- saldo de item não deve depender apenas do client.
- v1 pode gravar movimento e atualizar saldo em transação.
- v2 ideal: callable Function para movimento de estoque.

### `suppliers/{supplierId}`

Campos:

```txt
name
document?
contact_name?
phone?
email?
address?
notes?
active
created_at
updated_at
audit_trail
deleted_at?
```

Relatórios de estoque:

- saldo atual;
- estoque crítico;
- vencimentos próximos;
- consumo por período;
- consumo por cão;
- entradas por fornecedor;
- custo por período, se custo for adicionado depois.

Decisões pendentes:

- controlar custo médio agora ou depois;
- exigir lote/validade para ração e medicamentos;
- separar patrimônio permanente de consumo;
- criar aprovação para saída de estoque ou permitir saída direta auditada.

Recomendação:

- começar simples com item + movimento + saldo + mínimo + validade;
- adicionar custo/lote/patrimônio na v2.

---

## 17. Relatórios

Módulo: `Relatórios`

Relatórios iniciais:

- ocorrências por período;
- ocorrências por cão;
- ocorrências por condutor;
- ocorrências por natureza;
- treinos por modalidade;
- evolução por cão;
- saúde por cão;
- vacinas vencidas/a vencer;
- pesagens e tendência;
- consumo de estoque;
- estoque crítico;
- efetivo humano;
- efetivo K9;
- uso de viaturas.

Formatos:

- tela com filtros;
- exportar CSV/XLSX;
- exportar PDF gerencial;
- gráficos no dashboard.

Regras:

- relatórios não podem alterar dados;
- relatórios sensíveis devem respeitar papel/permissão;
- indicadores devem deixar claro o período e filtros usados.

Futuro:

- relatório mensal institucional do canil;
- relatório por cão;
- relatório por condutor;
- pacote PDF de prestação de contas.

---

## 18. Notificações e Pendências

Coleção herdada:

```txt
notifications/{ra}/items/{notificationId}
```

Regras:

- pendência aberta: `action_required == true && resolved_at == null`;
- aviso: todo item sem ação aberta;
- `read_at` não resolve;
- `archived_at` só para aviso;
- delete físico bloqueado.

Tela web:

- seção "Requer ação";
- seção "Avisos";
- filtros por tipo;
- ações por card;
- link para entidade de origem.

Tipos relevantes:

- convite de guarnição;
- assinatura de ocorrência;
- correção de ocorrência;
- evolução de treino;
- aprovação/rejeição de treino;
- bônus de treino;
- ocorrência finalizada;
- estoque crítico, futuro.

---

## 19. Administração

Módulo: `Admin`

Funcionalidades:

- usuários;
- papéis;
- claims;
- viaturas;
- categorias de estoque;
- fornecedores;
- naturezas de ocorrência;
- Matriz de Treinamento;
- parâmetros do sistema.

Regras:

- mudança de papel via Function;
- cadastros com audit trail;
- soft delete;
- logs de auditoria visíveis para Admin.

Functions atuais úteis:

- `setK9InstructorRole`

Functions futuras prováveis:

- `setUserRoles`;
- `publishTrainingMatrixVersion`;
- `createInventoryMovement`;
- `recalculateInventoryItemBalance`;
- `generateMonthlyReport`;
- `exportReport`.

---

## 20. Auditoria

Coleção:

```txt
auditLogs/{logId}
```

Padrão inline:

```txt
audit_trail: [
  {
    action,
    at,
    by,
    by_name,
    by_ra,
    field_name?,
    old_value?,
    new_value?,
    reason?
  }
]
```

Regras:

- create/update relevante deve ter trilha;
- correção deve preservar valor anterior;
- soft delete precisa motivo;
- relatórios podem consumir auditoria;
- logs não devem ser editáveis.

Para o web:

- criar componente comum de "Linha de auditoria";
- mostrar auditoria em páginas de detalhe;
- Admin deve ter busca de auditoria.

---

## 21. Segurança e Firestore Rules

Rules atuais já cobrem:

- users;
- dogs;
- training;
- occurrences;
- notifications;
- vehicle crews;
- health;
- nutrition;
- storage.

Novos módulos exigirão rules:

- `inventory_categories`;
- `inventory_items`;
- `inventory_movements`;
- `suppliers`;
- roles administrativas novas.

Proposta de regras para estoque:

- leitura para usuários autenticados autorizados;
- create/update para Admin ou Inventory Manager;
- movimento de estoque via Function ou transação com rule restrita;
- delete físico bloqueado;
- soft delete com auditoria.

Decisão:

- antes de implementar estoque em produção, criar rules e testes de rules.

---

## 22. Design System Web

Identidade herdada:

- fundo escuro institucional;
- ciano como cor principal;
- verde para operacional/sucesso;
- amarelo para atenção/formação;
- vermelho para erro/crítico;
- fonte principal: Inter;
- fonte mono para dados técnicos: IBM Plex Mono ou equivalente.

Componentes web:

- App Shell com sidebar;
- Topbar com busca global, sino e usuário;
- cards de status;
- tabelas densas;
- filtros persistentes;
- badges de status;
- drawer/modal para ações rápidas;
- páginas de detalhe com abas;
- gráficos;
- timeline.

Não copiar do mobile:

- bottom nav;
- FAB central;
- sheets de 390px;
- cards muito verticais;
- fluxos de muitos passos pequenos.

---

## 23. Modelo de App Shell

Layout proposto:

```txt
Sidebar
  Dashboard
  Efetivo K9
  Efetivo Humano
  Viaturas
  Ocorrências
  Treinamentos
  Matriz de Treinamento
  Saúde
  Estoque
  Relatórios
  Notificações
  Administração

Topbar
  Busca global
  Pendências
  Perfil do usuário
```

Busca global deve encontrar:

- cão;
- GCM/RA;
- viatura;
- ocorrência;
- item de estoque.

---

## 24. MVP Recomendado

### MVP 0 - Fundação

- criar projeto Next.js;
- configurar TypeScript;
- configurar Tailwind/shadcn;
- configurar Firebase client;
- configurar Auth;
- proteger rotas;
- App Shell;
- leitura de usuário atual;
- leitura de claims/roles.

### MVP 1 - Dashboard

- cards básicos;
- pendências abertas;
- cães ativos;
- turnos ativos;
- ocorrências abertas;
- promoções pendentes;
- estoque crítico, se o módulo já existir.

### MVP 2 - Efetivo K9

- listagem;
- detalhe;
- dados básicos;
- saúde resumo;
- treino resumo;
- ocorrência resumo.

### MVP 3 - Efetivo Humano e Viaturas

- CRUD humano;
- perfil GCM;
- CRUD viaturas;
- perfil viatura;
- vínculo com turnos/guarnições.

### MVP 4 - Estoque

- categorias;
- fornecedores;
- itens;
- movimento de entrada/saída;
- estoque mínimo;
- vencimentos.

### MVP 5 - Treinamentos e Matriz

- promoções pendentes;
- aprovar/rejeitar;
- leitura da Matriz de Treinamento;
- detalhe por cão/modalidade.

### MVP 6 - Ocorrências e Relatórios

- consulta;
- detalhe;
- integridade;
- PDF;
- relatórios exportáveis.

---

## 25. Fases de Implementação

Fase 0:

- confirmar pasta/repo do novo web;
- criar `.env.local.example`;
- documentar Firebase config;
- criar regras de contribuição.

Fase 1:

- scaffold Next.js;
- tema;
- layout;
- login;
- Auth guard.

Fase 2:

- Firebase domain layer;
- converters;
- tipos comuns;
- permissões;
- shell.

Fase 3:

- Dashboard v1.

Fase 4:

- Efetivo K9.

Fase 5:

- Efetivo Humano.

Fase 6:

- Viaturas.

Fase 7:

- Estoque.

Fase 8:

- Treinos e Matriz de Treinamento.

Fase 9:

- Ocorrências e integridade.

Fase 10:

- Relatórios.

---

## 26. Contratos Firestore Herdados

Herdar sem renomear:

```txt
users
dogs
active_shifts
shift_logs
vehicles
vehicle_crews
occurrences
notifications
training_programs
promotion_requests
auditLogs
```

Subcoleções críticas:

```txt
dogs/{dogId}/training
dogs/{dogId}/training_sessions
dogs/{dogId}/health_events
dogs/{dogId}/weight_records
dogs/{dogId}/feeding_events
dogs/{dogId}/nutritional_prescriptions
dogs/{dogId}/nutrition_supplements
dogs/{dogId}/documents

occurrences/{occurrenceId}/events
occurrences/{occurrenceId}/signatures
occurrences/{occurrenceId}/participations
occurrences/{occurrenceId}/correction_requests

training_programs/{modality}/modules
training_programs/{modality}/modules/{moduleId}/milestones
notifications/{ra}/items
vehicle_crews/{crewId}/members
users/{ra}/devices
```

Novas coleções propostas:

```txt
inventory_categories
inventory_items
inventory_movements
suppliers
report_exports
system_settings
```

---

## 27. Decisões Pendentes

1. Nome e pasta do novo projeto web.
2. Firebase App Hosting ou Firebase Hosting/Vercel.
3. Modelo final de roles globais.
4. Se estoque v1 terá custo/lote ou só quantidade/validade.
5. Se movimento de estoque será callable Function já na v1.
6. Se relatórios v1 exportam CSV antes de PDF.
7. Se CRUD de Matriz de Treinamento entra antes ou depois de leitura/aprovação.
8. Quais prints visuais do dashboard serão adotados como referência.

---

## 28. Primeiros Arquivos a Criar no Web

Quando iniciar o scaffold:

```txt
.env.local.example
src/lib/firebase/client.ts
src/lib/firebase/functions.ts
src/lib/permissions/roles.ts
src/lib/routes/paths.ts
src/components/layout/app-shell.tsx
src/features/auth/
src/features/dashboard/
src/features/dogs/
```

Primeiro fluxo funcional:

1. Login.
2. Guard de rota autenticada.
3. Shell com sidebar.
4. Dashboard lendo pelo menos `dogs`, `active_shifts`, `occurrences`, `promotion_requests`.

---

## 29. Glossário

| Termo | Significado |
|---|---|
| K9 | Cão operacional do canil |
| GCM | Guarda Civil Municipal |
| RA | Identificador funcional do servidor |
| Binômio | Condutor + cão |
| Guarnição | Equipe vinculada à viatura/turno |
| Matriz de Treinamento | Programa de formação por modalidade |
| Marco | Requisito dentro de um módulo de treino |
| Promoção | Solicitação/aprovação para avançar módulo |
| Pendência | Notificação que requer ação e ainda não foi resolvida |
| Selo | Integridade documental de ocorrência finalizada |
| Soft delete | Arquivamento lógico com trilha, sem apagar fisicamente |

---

## 30. Norte do Projeto

O web deve fazer o canil parecer o que ele é:

- organizado;
- auditável;
- técnico;
- defensável;
- gerencial;
- com dados prontos para responder questionamentos.

O mobile prova o trabalho no campo.  
O web organiza, administra, audita e apresenta esse trabalho.

