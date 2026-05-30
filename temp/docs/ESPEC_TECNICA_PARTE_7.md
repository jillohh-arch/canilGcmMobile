# ESPECIFICAÇÃO TÉCNICA — PARTE 7
# Ocorrências — registro completo (deslocamento, fotos, edição de local, finalização)

> Tornar o registro de uma ocorrência **grande e móvel** fiel — no detalhe e no PDF. Nasce de uma ocorrência real: 8 ações, 3 presos, 4 locais (abordagem → residência → Santa Casa → distrito), +10 fotos.
> Mockups: `temp/mockups/ocorrencia_detalhe_grande.html` e `temp/mockups/ocorrencia_editar_local.html`.

---

## 7.0 — Escopo
Duas camadas:
- **Captura:** editar o local de uma ação (busca OSM + pino) · anexar fotos na finalização.
- **Exibição:** todas as fotos (sem corte) · timeline paginando no PDF · mapa de deslocamento — no detalhe e no PDF.
Mais a regra de integridade que amarra as duas.

## 7.1 — Decisões confirmadas
- **Mapa de deslocamento por LOCAL** (um pino por local, não por ação), na ordem cronológica, OSM dark.
- **Editar local** via busca OSM (Nominatim/Photon) — acha POI **e** rua — + **pino arrastável** + "usar localização atual".
- **Fotos na finalização** (B.O., apreensões), separadas das fotos por ação.
- **Todas as fotos** exibidas — fim do corte em 4.
- **Timeline pagina** no PDF (quantas folhas precisar).
- **Integridade:** editar livre **antes de selar**; depois do hash, vira **retificação registrada** (não apaga o original).

## 7.2 — Captura: local da ação
- Toda ação **captura lat/lng** (GPS atual) por padrão ao registrar.
- Tela "**Local da ação**" (mockup) permite **trocar/corrigir**: campo de busca com **autocomplete OSM** (POI + endereço de rua), lista de sugestões com endereço, **pino arrastável** no mini-mapa, botão "**usar minha localização atual**", coordenadas em mono.
- Funciona **retroativo** — editar o local de uma ação já registrada (caso real: condutor atualiza o app a 5 quarteirões do local e corrige depois).
- **Precisão:** POI e rua o OSM acerta; número exato pode cair aproximado → o pino resolve o ajuste fino.
- **Auditável:** a correção fica na trilha; **não apaga** o ponto original. Guardar `location_source` (gps_atual | busca | ajuste_manual).

## 7.3 — Captura: fotos na finalização
- A tela de finalização (já tem nº do **B.O.**, entorpecentes, apreensões) ganha **anexo de fotos**: foto do boletim, das apreensões, etc.
- São **fotos de resultado** — distintas das fotos por ação. Guardar em `finalization_photos[]`.
- Aparecem no detalhe e no PDF na **seção de resultado/finalização**.

## 7.4 — Exibição: detalhe da ocorrência (mockup aprovado)
- **Header:** natureza (editável — Parte 8/Frente B) · status · protocolo (mono) · condutor · janela de tempo.
- **Resumo (chips):** presos · apreensões · nº de ações · nº de locais · nº de fotos.
- **Mapa de deslocamento:** pinos por local numerados na ordem + trilha ligando + legenda com horário de chegada. Tocar no pino → rola até a ação. **Ações sem coordenada não quebram o mapa** (plota só as que têm).
- **Timeline agrupada por local:** numeração do pino bate com o mapa; cada ação com hora (mono), título, descrição, e **todas** as fotos da ação ("+N" abre o resto).
- **Resultado/finalização:** nº B.O., apreensões, fotos do desfecho.
- **Selo de integridade:** hash SHA-256 (já existe no código).

## 7.5 — Exibição: PDF
Herda a mesma lógica, **paginando**. Ordem:
1. Cabeçalho institucional + dados da ocorrência.
2. **Mapa de deslocamento** (estático, com legenda numerada dos locais).
3. **Timeline completa**, paginada por quantas folhas precisar (cada ação: hora, local, descrição, referência às fotos).
4. **Resultado/finalização** (B.O., apreensões).
5. **Anexo fotográfico** — **todas** as fotos numeradas, agrupadas por ação + finalização. **Sem limite de 4.**
6. Selo/hash + QR de verificação.

## 7.6 — Modelo de dados
- **Ação** (`occurrences/{id}/events/{eventId}`): `lat`, `lng`, `place_label` (nome/endereço resolvido), `location_source`, `photos[]` (refs Storage).
- **Finalização**: `bo_number`, `seizures`, `finalization_photos[]`.
- **Retificação pós-selo:** registrada na trilha (append), sem reescrever o ponto/registro original.

## 7.7 — Geocoding (busca de local)
- **Nominatim ou Photon (OSM)** — sem custo, coerente com o `flutter_map`. Respeitar rate limit + user-agent; **debounce** na digitação.
- **Reverse geocoding** opcional: ao capturar o GPS atual, resolver um `place_label` legível.
- Fallback: package `geocoding` nativo, se necessário.

## 7.8 — Integridade
- **Antes de selar:** editar local / fotos / natureza é livre.
- **Depois do hash:** mudanças viram **retificação anexada** à trilha de auditoria; o documento original permanece íntegro e verificável.

## 7.9 — Critério de pronto
1. Cada ação guarda `lat/lng` + `place_label`.
2. Editar local: busca OSM (POI e rua) + pino arrastável + usar localização atual; **retroativo**; auditável.
3. Fotos na finalização (B.O., apreensões), além das fotos por ação.
4. Detalhe mostra **todas** as fotos, timeline por local e o mapa de deslocamento.
5. PDF **pagina** a timeline, mostra o mapa e anexa **todas** as fotos numeradas.
6. Ação **sem coordenada não quebra** o mapa.
7. Integridade: editar antes de selar livre; retificação registrada depois.
