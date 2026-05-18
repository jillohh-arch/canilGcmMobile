# Resumo Executivo — App Canil K9 GCM Limeira

## O que é

Aplicativo mobile (Flutter + Firebase) de gestão operacional do canil da GCM Limeira-SP. Funciona como prontuário institucional dos cães policiais, registrando treinos, ocorrências, saúde e alimentação. Gera PDFs com valor institucional, trilha de auditoria completa e hash SHA-256 para integridade — servindo como arquivo de defesa profissional dos condutores.

## Por que existe

"Há discussão de que quem trabalha no canil não faz nada." Condutores K9 enfrentam questionamentos de gestores sobre legitimidade e volume do trabalho. Caso fundador: Jilles Ragonha foi questionado por alimentar o Bono com 800g/dia (conhecimento técnico) enquanto o veterinário institucional prescrevia 300g — pagou laudo nutricional do próprio bolso. O app transforma decisões técnicas em registros institucionais sólidos.

## Quem usa

- 6 guardas civis municipais de Limeira (condutores K9)
- Cães: Bono (Malinois 6 anos, operacional) e Apolo (Malinois 2 anos, formação)
- Painel web React separado para gestores (mesmo Firestore)

## Stack técnica

| Camada | Tecnologia |
|--------|-----------|
| Mobile | Flutter (Dart 3.11+) |
| State | Provider (Riverpod futuro) |
| Backend | Firebase: Auth, Firestore, Storage, App Check |
| Navegação | Navigator manual |
| Gráficos | fl_chart |
| PDF | pdf + printing |
| GPS | geolocator |
| Painel web | React (codebase separado) |

## Estado atual (v1.0.0+2 em produção)

**Funciona:** Login, seleção de cão, turno, dashboard básico, registro de ocorrências/treinos/saúde.

**Falta:** Resolver duplicação views/features, remover gamificação, Hub de Treinos com especialidades, Protocolo Ragonha (Detecção), rastreador GPS, wizard de finalização de ocorrência, PDFs institucionais com SHA-256, trilha de auditoria completa, selos de conformidade, biblioteca de comandos por cão, relatório mensal.

## Roadmap

| Etapa | Escopo | Estimativa |
|-------|--------|-----------|
| 1 | Limpeza técnica (duplicação, gamificação) | 1 semana |
| 2 | Sistema visual (tema, widgets base) | 3-4 dias |
| 3 | Telas de alto impacto (Dashboard, Prontuário, Histórico) | 2-3 semanas |
| 4 | Especialidades (Obediência, B&C, Detecção, G&P) | 3-4 semanas |
| 5 | Ocorrências (auditoria, wizard, PDF) | 1-2 semanas |
| 6 | Features novas (Triagem, selos, certificação) | A definir |

**Total para base estável: 8-12 semanas.**

## Riscos críticos

- **Coexistência com painel React** — mudanças destrutivas no Firestore podem quebrar o painel. Mitigação: protocolo de 4 fases.
- **Base ativa pequena** — 6 condutores usando diariamente, qualquer regressão é sentida imediatamente.
- **Protocolo Ragonha** — regras rígidas (10 acertos consecutivos, 1 erro zera). Implementação incorreta invalida o registro.
- **Refatoração gradual** — manter app funcional durante migração exige commits pequenos e testes frequentes.

## Decisões já tomadas

1. Refatoração gradual, não reescrita do zero
2. Gamificação removida → selos de conformidade binários
3. Aba Rotina removida (alimentação → Nutrição, passeios → Condicionamento)
4. Bottom Nav fixo: Turno · Histórico · FAB(Ocorrência) · Treino · Cão
5. App detecta formação vs manutenção automaticamente
6. Trilha de auditoria + soft delete obrigatórios
7. EXIF preservado em fotos
8. PDF com SHA-256 + QR code
9. Tom institucional sério (sem inglês decorativo, sem RPG)

## Métricas de sucesso

- 100% das ocorrências geram PDF com hash verificável
- Ações frequentes em 3 taps ou menos
- Relatório mensal exportável com totais de plantões, ocorrências e treinos
- Condutor apresenta histórico completo em menos de 2 minutos
- Discussão "canil não trabalha" respondida com dados concretos e PDFs formais
