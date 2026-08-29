# Mockups Oficiais — Health v1.0

Este diretório reúne os mockups visuais aprovados do novo módulo **Health v1.0** do K9 Ops.

Os arquivos desta pasta devem ser usados como referência oficial de:

- identidade visual;
- composição de tela;
- hierarquia de informação;
- navegação;
- distribuição dos componentes;
- experiência do usuário;
- comportamento esperado das superfícies do módulo Saúde.

---

# Regra de precedência

Os mockups representam a referência visual e de UX.

Quando existir qualquer divergência entre um mockup e a documentação técnica versionada, prevalecem os contratos arquiteturais e de domínio mais recentes, especialmente:

- `docs/HEALTH_V1_ARCHITECTURE.md`
- `docs/HEALTH_IMPLEMENTATION_ROADMAP.md`
- `docs/health/HEALTH_V1_DOMAIN_MODEL.md`
- `docs/health/HEALTH_V1_FIRESTORE_SCHEMA.md`
- `docs/health/HEALTH_V1_READINESS_POLICY.md`
- ADRs em `docs/health/adr/`

Portanto:

> O mockup define como a experiência deve parecer e funcionar visualmente.  
> A documentação técnica define como os dados, estados, regras e integrações devem funcionar.

Nenhuma implementação deve inventar comportamento técnico apenas porque algo aparece de forma simplificada em um mockup.

---

# Identidade visual

Os mockups seguem a identidade oficial do K9 Ops:

- fundo dark navy / azul petróleo;
- cyan como cor principal de destaque;
- verde para estados positivos;
- amarelo/âmbar para atenção;
- vermelho para restrições e estados críticos;
- glassmorphism discreto;
- bordas técnicas suaves;
- cards com profundidade;
- visual premium institucional, operacional e tático;
- tipografia consistente com o restante do aplicativo;
- layout responsivo para smartphone.

A implementação deve buscar alta fidelidade visual sem duplicar componentes globais já existentes no projeto.

---

# Catálogo de mockups

| # | Tela | Status | Fase principal |
|---|---|---|---|
| 01 | Saúde e Prontidão | APROVADO | Fase 2 — Resumo |
| 02 | Hub de Registros | APROVADO | Fluxos de registro |
| 03 | Nutrição | APROVADO | Fase 5 |
| 04 | Registrar Alimentação | APROVADO | Fase 5 |
| 05 | Plano Alimentar | APROVADO | Fase 5 |
| 06 | Histórico Clínico | APROVADO | Fase 3 |
| 07 | Agenda Preventiva | APROVADO | Fase 4 |
| 08 | Consulta Veterinária | APROVADO | Fase 8 |
| 09 | Pesagem | APROVADO | Fase 6 |
| 10 | Vacinação | APROVADO | Fase 7 |
| 11 | Tratamento | APROVADO | Fase 10 |
| 12 | Administração de Dose | APROVADO | Fase 10 |
| 13 | Registro Clínico | APROVADO | Fluxos clínicos |
| 14 | Intercorrência | APROVADO | Fase 11 |
| 15 | Tratamento com Restrição | APROVADO | Fases 10 e 12 |
| 16 | Reavaliação | APROVADO | Fluxo clínico |
| 17 | Resultado de Exame | APROVADO | Fase 9 |

---

# Mockup 01 — Saúde e Prontidão

Arquivo esperado:

```text
01-saude-e-prontidao.png