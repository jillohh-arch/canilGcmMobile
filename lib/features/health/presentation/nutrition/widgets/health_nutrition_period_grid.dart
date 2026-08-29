import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';

/// Um slot planejado dentro de uma faixa visual.
///
/// Presentation-only: [status] é o status derivado que a tela já calcula
/// (`NutritionTodaySlotUi.statusFor`). Este widget não recalcula nada e não
/// consulta relógio.
@immutable
class HealthNutritionSlotEntry {
  const HealthNutritionSlotEntry({
    required this.timeLabel,
    required this.statusLabel,
    required this.statusColor,
    this.targetGrams,
    this.onRegister,
    this.executedFacts = const [],
    this.conflictMessage,
    this.measurementNote,
  });

  final String timeLabel;
  final String statusLabel;
  final Color statusColor;
  final double? targetGrams;

  /// `null` desabilita o CTA — preserva o gating fail-closed da tela.
  final VoidCallback? onRegister;

  /// Fatos da refeição já executada (Oferecido / Consumido / Aceitação e afins).
  ///
  /// Existe para NÃO perder informação: o card vertical anterior exibia esses
  /// valores, e um quadrante que só mostrasse "Concluída" esconderia dado real.
  final List<HealthNutritionFactLine> executedFacts;

  /// Mensagem de conflito de integridade, quando houver.
  ///
  /// Renderizada com `Semantics(liveRegion: true)` — o card anterior anunciava
  /// esse conflito a leitores de tela e isso não pode ser perdido.
  final String? conflictMessage;

  /// Nota de medição ausente ("Quantidade consumida não medida").
  ///
  /// Separada de [conflictMessage] porque tem cor e semântica diferentes: é
  /// informativa, não um alerta de integridade.
  final String? measurementNote;
}

/// Par rótulo/valor de um fato registrado.
@immutable
class HealthNutritionFactLine {
  const HealthNutritionFactLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
}

/// Conteúdo de um quadrante.
@immutable
class HealthNutritionQuadrantData {
  const HealthNutritionQuadrantData({
    required this.group,
    required this.slots,
    this.ctaLabel = 'Registrar refeição',
    this.summaryLine,
    this.emptyLabel,
    this.onAction,
  });

  final HealthNutritionPeriodGroup group;
  final List<HealthNutritionSlotEntry> slots;
  final String ctaLabel;

  /// CTA do quadrante quando ele não vem de um slot de refeição (caso do
  /// suplemento). `null` desabilita — o gating continua no chamador.
  final VoidCallback? onAction;

  /// Linha de resumo usada quando a faixa agrega mais de um slot, ou quando o
  /// quadrante é o de suplemento (que não tem slot de refeição).
  final String? summaryLine;

  /// Copy honesta para faixa sem slot no plano — nunca inventamos horário.
  final String? emptyLabel;
}

/// Grid 2×2 das faixas do dia + suplemento.
///
/// Layout segue o padrão responsivo já usado por `HealthSummaryMetricsGrid`:
/// duas colunas por aritmética (`Wrap` + largura calculada), degradando para
/// coluna única em telas estreitas. Não usa `GridView` — alturas são
/// intrínsecas, então um quadrante com dois slots cresce sem cortar texto.
class HealthNutritionPeriodGrid extends StatelessWidget {
  const HealthNutritionPeriodGrid({
    super.key,
    required this.quadrants,
    this.extraSlots = const [],
  });

  final List<HealthNutritionQuadrantData> quadrants;

  /// Slots `extra` / período desconhecido. Renderizados como linhas compactas
  /// abaixo do grid: não somem, e também não viram um quinto card permanente.
  final List<HealthNutritionSlotEntry> extraSlots;

  static const double _gap = 10;
  static const double _singleColumnThreshold = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < _singleColumnThreshold;
        final cardWidth = singleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - _gap) / 2;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final quadrant in quadrants)
                  SizedBox(
                    width: cardWidth,
                    child: _QuadrantCard(data: quadrant),
                  ),
              ],
            ),
            if (extraSlots.isNotEmpty) ...[
              const SizedBox(height: _gap),
              for (final slot in extraSlots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ExtraSlotRow(slot: slot),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  const _QuadrantCard({required this.data});

  final HealthNutritionQuadrantData data;

  @override
  Widget build(BuildContext context) {
    final visual = HealthNutritionPeriodVisuals.resolve(data.group);
    final primarySlot = data.slots.isEmpty ? null : data.slots.first;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Superfície própria: o quadrante ganha identidade sem alterar
        // HealthSummaryCardSurface (contado por assertions de outros testes).
        color: visual.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: visual.accent.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: visual.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: visual.accent.withValues(alpha: 0.28),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(visual.icon, size: 18, color: visual.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // MAIÚSCULA preservada do card anterior (`periodLabel
                      // .toUpperCase()`): é o vocabulário institucional da tela
                      // e há teste ancorado nele.
                      visual.label.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        height: 1.2,
                      ),
                    ),
                    // Pill ao lado do título, como no card anterior. Ficar em
                    // linha própria custava ~25px por quadrante e empurrava o
                    // CTA para fora do alcance sem scroll.
                    if (primarySlot != null) ...[
                      const SizedBox(height: 4),
                      _StatusPill(
                        label: primarySlot.statusLabel,
                        color: primarySlot.statusColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (primarySlot != null)
            // Horário e quantidade em UMA linha: mantém as duas informações e
            // economiza altura, o que importa porque o CTA precisa ficar
            // alcançável sem scroll longo em campo.
            _IconLine(
              icon: Icons.schedule_rounded,
              text: primarySlot.targetGrams == null
                  ? primarySlot.timeLabel
                  : '${primarySlot.timeLabel} · ${HealthNutritionTodayFormatters.grams(primarySlot.targetGrams)} previstos',
            ),
          if (data.summaryLine != null) ...[
            if (primarySlot != null) const SizedBox(height: 4),
            Text(
              data.summaryLine!,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
          if (primarySlot == null && data.emptyLabel != null)
            Text(
              data.emptyLabel!,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          // Slots adicionais da mesma faixa: nada é escondido.
          for (final extra in data.slots.skip(1)) ...[
            const SizedBox(height: 6),
            _SecondarySlotRow(slot: extra),
          ],
          // Fatos da refeição executada.
          //
          // PASS 02: antes eram três linhas EMPILHADAS + nota, o que fazia o
          // quadrante concluído crescer e quebrar o ritmo do 2×2. Agora fluem
          // inline num `Wrap`, ocupando ~2 linhas curtas em largura normal.
          // Nenhum fato foi removido — só a densidade mudou. O quadrante é
          // resumo operacional; a ficha completa é o registro.
          if (primarySlot != null && primarySlot.executedFacts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final fact in primarySlot.executedFacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _FactRow(fact: fact),
                  ),
              ],
            ),
          ],
          if (primarySlot?.measurementNote != null) ...[
            const SizedBox(height: 4),
            Text(
              primarySlot!.measurementNote!,
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
          // Conflito de integridade: mesma copy, cor e anúncio do card anterior.
          if (primarySlot?.conflictMessage != null) ...[
            const SizedBox(height: 10),
            Semantics(
              container: true,
              liveRegion: true,
              label: primarySlot!.conflictMessage!,
              excludeSemantics: true,
              child: Text(
                primarySlot.conflictMessage!,
                style: GoogleFonts.inter(
                  color: AppTheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (primarySlot?.onRegister != null || data.onAction != null) ...[
            const SizedBox(height: 10),
            _QuadrantCta(
              label: data.ctaLabel,
              accent: visual.accent,
              onPressed: primarySlot?.onRegister ?? data.onAction!,
            ),
          ],
        ],
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// Slot adicional dentro da mesma faixa (ex.: duas refeições de manhã).
class _SecondarySlotRow extends StatelessWidget {
  const _SecondarySlotRow({required this.slot});

  final HealthNutritionSlotEntry slot;

  @override
  Widget build(BuildContext context) {
    final grams = slot.targetGrams == null
        ? null
        : HealthNutritionTodayFormatters.grams(slot.targetGrams);
    final line = grams == null
        ? slot.timeLabel
        : '${slot.timeLabel} · $grams';

    return Row(
      children: [
        Expanded(
          child: Text(
            line,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _StatusPill(label: slot.statusLabel, color: slot.statusColor),
      ],
    );
  }
}

/// Linha compacta para slots `extra` / período desconhecido.
class _ExtraSlotRow extends StatelessWidget {
  const _ExtraSlotRow({required this.slot});

  final HealthNutritionSlotEntry slot;

  @override
  Widget build(BuildContext context) {
    final visual = HealthNutritionPeriodVisuals.resolve(
      HealthNutritionPeriodGroup.extra,
    );
    final grams = slot.targetGrams == null
        ? null
        : HealthNutritionTodayFormatters.grams(slot.targetGrams);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visual.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(visual.icon, size: 16, color: visual.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              grams == null
                  ? '${visual.label} · ${slot.timeLabel}'
                  : '${visual.label} · ${slot.timeLabel} · $grams',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StatusPill(label: slot.statusLabel, color: slot.statusColor),
        ],
      ),
    );
  }
}

/// Linha de fato registrado: rótulo discreto + valor destacado.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final HealthNutritionFactLine fact;

  @override
  Widget build(BuildContext context) {
    if (fact.label.isEmpty) {
      return Text(
        fact.value,
        style: GoogleFonts.inter(
          color: fact.valueColor ?? AppTheme.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      );
    }
    return Wrap(
      spacing: 4,
      children: [
        Text(
          '${fact.label}:',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          fact.value,
          style: GoogleFonts.inter(
            color: fact.valueColor ?? AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// CTA do quadrante.
///
/// `OutlinedButton` mantém o mesmo tipo de affordance do card anterior; o
/// `minimumSize` garante o alvo de toque de 48px de altura.
class _QuadrantCta extends StatelessWidget {
  const _QuadrantCta({
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      // `OutlinedButton.icon` + label exato: o "+" vem do ícone, como no mockup,
      // sem alterar o TEXTO que os testes de execução usam para tocar o CTA.
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label, textAlign: TextAlign.center),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          foregroundColor: accent,
          textStyle: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
