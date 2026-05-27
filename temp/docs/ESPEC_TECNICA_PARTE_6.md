# ESPECIFICAÇÃO TÉCNICA — PARTE 6
# Rastreamento GPS (componente reutilizável)

> Rastreamento GPS **de verdade** (com background) para registrar o trajeto de atividades em campo. É um **componente reutilizável**, acionável de várias atividades — não uma tela isolada.
>
> **Real, não mockado:** captura pontos reais do GPS e grava no Firestore. Mockup de referência: `temp/mockups/tela_rastreamento_gps.html`.

---

## 6.0 — Escopo e pontos de entrada

O rastreamento é um **módulo único** acionado de:
- **Condicionamento físico** — inclui o **passeio** (tudo dentro de Condicionamento). Foco: performance física (distância, ritmo, velocidade).
- **Busca & Captura** — **treino e formação**. Foco: a rota mostra a área coberta pela busca.

Mesmo motor de captura nos dois; muda só o contexto e a sessão à qual o trajeto é anexado.

## 6.1 — Decisões confirmadas
- **Background é essencial** — rastreia com a tela apagada / celular no bolso.
- **Métricas:** distância, mapa da rota, ritmo (min/km), velocidade média.
- **Mapa: OpenStreetMap** (`flutter_map`) com estilo dark — sem custo por uso.
- **Resultado aparece no Histórico**, e o detalhe mostra o **mapa da rota**.

## 6.2 — Fluxo (abrir → fechar → onde aparece)
- **Abrir:** [atividade] → **Iniciar** → tela de rastreamento (empilha via `push`).
- **Durante:** rastreia. **O "voltar" NÃO para o rastreamento** — sai da tela e segue em background (notificação persistente "Rastreando"); voltar reabre a tela ativa. Parar **só** pelo botão **Finalizar**.
- **Finalizar:** → tela de **Resumo** → **Salvar** (grava e volta ao hub de Treinos) ou **Descartar** (com confirmação).
- **Onde aparece:** registro no **Histórico** (ex: "Treino · Condicionamento" / "Busca & Captura") com distância e tempo no resumo; tocar abre o **detalhe** com o **mapa da rota + as 4 métricas**. O **card da atividade no hub** atualiza a "última" (ex: "hoje · 4,12 km").

## 6.3 — Estados
`preparando → rastreando ⇄ pausado → finalizado (resumo) → salvo | descartado`
- `rastreando` e `pausado` **persistem em background** (foreground service no Android / localização "Sempre" no iOS).

## 6.4 — Captura e métricas
- Coletar pontos a cada **~5 s ou ~10 m** (parâmetro), com timestamp e precisão.
- **Filtrar ruído de GPS** (crítico para a distância não inflar):
  - descartar pontos com precisão pior que ~20–30 m;
  - descartar saltos com velocidade impossível;
  - **não somar distância quando praticamente parado** (deriva) — senão "anda" no semáforo.
- **Distância:** soma dos trechos válidos (haversine).
- **Tempo:** decorrido, **descontando pausas**.
- **Ritmo:** tempo ÷ distância (min/km). **Velocidade média:** distância ÷ tempo.
- **Rota:** lista de pontos (polyline) para o mapa.

## 6.5 — Mapa
- `flutter_map` + OSM, tiles em **estilo dark** (coerente com o app).
- **Ao vivo:** desenhar a polyline **ciano** conforme captura; marcador de **início (verde)** e **posição atual (ciano)**.
- **Resumo/detalhe:** rota completa (início verde, fim com bandeira).

## 6.6 — Permissões e background
- Pedir permissão de localização; se negada, **explicar por que precisa** sem travar o app.
- **Background:** `ACCESS_BACKGROUND_LOCATION` + **foreground service** com notificação persistente (Android); localização **"Sempre"** (iOS). A notificação mostra "Rastreando · [atividade]".
- Tratar **GPS desligado / sem sinal** — avisar e pausar a captura sem perder o que já tem.

## 6.7 — Modelo de dados
O trajeto é **anexado à sessão da atividade** que o acionou (condicionamento ou B&C), não um documento solto. A sessão ganha um objeto `gps_track`:

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `points` | array\<obj\> | `{ lat, lng, ts, acc }` — ou **polyline encoded** se ficar grande |
| `distance_m` | int | distância total (m) |
| `duration_s` | int | tempo em movimento (sem pausas) |
| `avg_pace_s_per_km` | int | ritmo médio |
| `avg_speed_kmh` | number | velocidade média |
| `started_at` / `ended_at` | timestamp | início / fim |

Se `points` ficar pesado, salvar como **polyline encoded** ou subdocumento, para não estourar o tamanho do doc.

## 6.8 — Histórico e detalhe
- O registro aparece no histórico com o tipo da atividade + resumo (distância/tempo).
- **Detalhe:** usa o `HistoryDetailScaffold` (casca) + um **corpo novo "rastreamento"**: mapa da rota (OSM dark) + as 4 métricas.
- Registro de treino é **editável com auditoria** — **sem hash imutável** (mesma regra dos outros treinos).

## 6.9 — Navegação (liga ao fix de back)
- A tela de rastreamento **empilha** (`push`).
- **O back não para o rastreamento:** sai da tela; o rastreamento segue em background; voltar reabre a tela ativa. A notificação persiste e permite reabrir a sessão.
- **Parar só via Finalizar.** Ao **Salvar/Descartar**, desempilha e volta ao hub.

## 6.10 — Offline
- GPS funciona **sem internet** — pontos coletados localmente e sincronizados ao salvar / quando a conexão voltar.
- **Tiles do mapa:** cachear; sem internet a captura continua (a rota desenha quando os tiles carregam), **os pontos nunca se perdem**.

## 6.11 — Auditoria / soft delete
A sessão com rastreamento segue as regras de **auditoria** e **soft delete** do projeto.

## 6.12 — Critério de pronto
1. Iniciar o rastreamento de **Condicionamento** e de **Busca & Captura** (treino e formação).
2. Rastreia em **background** (tela apagada) com notificação persistente; **a distância não infla** parado.
3. Mapa **ao vivo** desenha a rota; métricas atualizam em tempo real.
4. **Pausar/retomar**; **Finalizar** → resumo com as 4 métricas e a rota.
5. **Salvar** grava o `gps_track` anexado à sessão; aparece no **histórico**; o **detalhe mostra o mapa**.
6. **O back não para** o rastreamento.
7. Funciona **offline** (pontos não se perdem).
8. **Nada hardcoded.**
