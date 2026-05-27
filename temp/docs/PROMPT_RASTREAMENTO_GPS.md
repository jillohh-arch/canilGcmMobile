# PROMPT — Rastreamento GPS (componente reutilizável)

> Sessão focada do Claude Code. É o recurso mais técnico da série (background + permissões + mapa). Cole o bloco abaixo.

---

Vamos implementar o **rastreamento GPS de verdade** do app Canil K9 GCM Limeira — um componente reutilizável que captura o trajeto de atividades em campo, **funcionando com a tela apagada**.

**Leia primeiro:**
- `temp/docs/ESPEC_TECNICA_PARTE_6.md` — spec completa (escopo, fluxo, captura, mapa, background, dados, critério de pronto).
- Mockup: `temp/mockups/tela_rastreamento_gps.html` — **protótipo visual** (rastreando + resumo); não vira código, guia o desenho. Mapa em OSM dark, rota ciano, métricas, controles.
- Skills: `canil-k9-context`, `firestore-coexistence`, `flutter-canil-conventions`, `flutter-visual-fidelity`, `audit-trail`.

**Antes de codar — mapeie o que já existe.** Hoje, em Condicionamento (e onde mais?), há um ponto que "ativa o GPS mas não faz nada". Me mostre: onde esse acionamento está, se já existe algum plugin de localização no `pubspec`, e como as sessões de treino (condicionamento / busca & captura) são gravadas hoje. **Estender/adaptar, não duplicar.**

**Decisões já confirmadas (não reabrir):**
- **Background é essencial** (tela apagada / bolso).
- Métricas: **distância, mapa da rota, ritmo (min/km), velocidade média**.
- Mapa: **OpenStreetMap via `flutter_map`**, estilo dark (sem custo por uso). **Não usar Google Maps.**
- Resultado aparece no **Histórico**, detalhe com **mapa**.

**Pontos de entrada (mesmo componente):**
- **Condicionamento** (inclui passeio).
- **Busca & Captura** — treino e formação.

**Ordem sugerida (se a sessão ficar grande):**
1. **Núcleo:** serviço de rastreamento (captura + filtro de ruído + métricas) + background (foreground service Android / "Sempre" iOS) + tela ativa (mapa ao vivo + métricas + pausar/finalizar) + resumo + salvar, **acionado de Condicionamento**.
2. **Histórico:** registro + corpo de detalhe "rastreamento" com o mapa (reusar o `HistoryDetailScaffold`).
3. **Plugar em Busca & Captura** (treino e formação).

**Pontos técnicos críticos (spec 6.4 e 6.6):**
- **Filtrar ruído de GPS** para a distância não inflar: descartar baixa precisão, saltos impossíveis e **deriva parado** (não somar distância no semáforo).
- **Background real:** foreground service com **notificação persistente** "Rastreando · [atividade]"; permissões de background tratadas (negação não trava o app).
- **O back NÃO para o rastreamento** (spec 6.9): sair da tela mantém a captura em background; só **Finalizar** para. Ligar isso ao tratamento de navegação do app.
- **Offline:** pontos coletados localmente, nunca se perdem; tiles do mapa cacheados.

**Dados (spec 6.7):** anexar um objeto `gps_track` à **sessão da atividade** (não doc solto): `points` (ou polyline encoded), `distance_m`, `duration_s`, `avg_pace_s_per_km`, `avg_speed_kmh`, `started_at`, `ended_at`. Auditoria + soft delete. Sem hash imutável (é treino editável).

**Regras do projeto:** branch; `main` buildável; merge `--no-ff` só após validado.

**Pronto quando (spec 6.12):**
1. Inicia de Condicionamento e de B&C (treino e formação).
2. Rastreia em **background** com notificação; **distância não infla** parado.
3. Mapa ao vivo desenha a rota; métricas atualizam.
4. Pausar/retomar; Finalizar → resumo com as 4 métricas e a rota.
5. Salvar grava o `gps_track` na sessão; aparece no histórico; **detalhe mostra o mapa**.
6. **Back não para** o rastreamento.
7. Funciona offline.

**Valide com evidência:** `git log` + **um trajeto de teste real** (andar alguns metros, bloquear a tela, voltar) com print da tela ativa, do resumo, do registro no histórico e do detalhe com o mapa. E confirmar que a distância parado **não** sobe. Não aceitar resumo narrativo.
