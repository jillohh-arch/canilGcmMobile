# FIX — Resumo da Detecção no hub de Treinos (derivar do estado real por linha)

## Sintoma
No hub de Treinos, o card de **Detecção** mostra badge **"EM FORMAÇÃO"** e o subtítulo fixo **"Drogas/Armas E Pólvora: em formação"**. Mas o estado real (já corrigido na entrada de Detecção) é: **Drogas OPERACIONAL**, **Armas e Cadáver NÃO INICIADAS**. O resumo está desatualizado e claramente **hardcoded** — inclusive "Pólvora", que nem é uma das linhas oficiais.

## Causa
O card resume a Detecção com **texto fixo**, em vez de **derivar** dos status reais das linhas (`detection_lines`).

## Regra correta
O card de Detecção no hub deve **derivar** badge, subtítulo e "última" dos status reais das **3 linhas** — `drogas`, `armas`, `cadaver` (as linhas oficiais são **Drogas, Armas, Cadáver**; não existe "Pólvora").

**Badge agregado** (prioridade):
- alguma linha `in_formation` → **EM FORMAÇÃO**
- senão, alguma `operational` → **OPERACIONAL**
- senão → **NÃO INICIADA**

**Subtítulo** — resumir o estado por linha de forma honesta, derivado dos status. No caso atual: **"Drogas operacional · Armas e Cadáver não iniciadas"**.

**"última"** — a data da sessão mais recente entre todas as linhas de detecção (incluindo manutenção).

## Tarefas
1. Localizar onde o card de Detecção do hub monta badge / subtítulo / "última" (`training_hub_screen.dart` ou o serviço que o alimenta).
2. Substituir o texto fixo pela **derivação dos status reais** das `detection_lines`.
3. Conferir que as linhas são **Drogas / Armas / Cadáver** — remover qualquer "Pólvora" legado.
4. Atualizar a "última" para a sessão mais recente entre as linhas.

## Pronto quando
- O card de Detecção no hub mostra badge e subtítulo **coerentes com o estado real** — hoje: **OPERACIONAL**, "Drogas operacional · Armas e Cadáver não iniciadas".
- **Nada hardcoded** — tudo derivado dos status das linhas.

## Validar com evidência
Print do hub com o card de Detecção refletindo Drogas operacional; depois iniciar uma das outras linhas e ver o resumo atualizar sozinho.

## Nota (fora do escopo agora)
O mesmo princípio — **resumo derivado de dados, não texto fixo** — vale para **Busca & Captura** e **Guarda & Proteção**, mas elas têm estrutura diferente (não usam o modelo de linhas da Detecção). Tratar em sessão separada.
