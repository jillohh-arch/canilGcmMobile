import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';

// --- Design tokens from mockup ---
const Color _bg = Color(0xFF050D10);
const Color _cyan = Color(0xFF4DD0E1);
const Color _textPrimary = Color(0xFFFFFFFF);
const Color _textSecondary = Color(0xFFB0C4CC);
const Color _textMuted = Color(0xFF5A7280);
const Color _green = Color(0xFF2ECC71);

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;
  const HistoryDetailScreen({super.key, required this.entry});
  @override
  Widget build(BuildContext context) => RegistroDetalhePage(entry: entry);
}

class RegistroDetalhePage extends StatelessWidget {
  final HistoryEntry entry;
  const RegistroDetalhePage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final detail = RecordDetail.fromEntry(entry);
    return Scaffold(
      backgroundColor: _bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _bg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _DetailHeader(detail: detail, onBack: () => Navigator.of(context).pop(), onMenuTap: () => _openRecordMenu(context)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail.status.toLowerCase().contains('final')) ...[
                          _ResultadoSection(detail: detail),
                          const SizedBox(height: 16),
                        ],
                        _InformacoesSection(detail: detail),
                        const SizedBox(height: 16),
                        _TimelineSection(detail: detail),
                        const SizedBox(height: 16),
                        _AuditSection(detail: detail),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _CtaBar(
                onPdfTap: () => _notify(context, 'Geração de PDF preparada.'),
                onShareTap: () => _notify(context, 'Compartilhamento preparado.'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecordMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cyan.withAlpha(77)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MenuRow(icon: Icons.edit_outlined, label: 'Editar registro', onTap: () { Navigator.of(ctx).pop(); _notify(context, 'Edição do registro preparada.'); }),
                Divider(height: 1, color: _cyan.withAlpha(30)),
                _MenuRow(icon: Icons.copy_all_outlined, label: 'Copiar resumo operacional', onTap: () { Navigator.of(ctx).pop(); _notify(context, 'Resumo operacional copiado.'); }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: _textPrimary, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF0F2026),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _DetailHeader extends StatelessWidget {
  final RecordDetail detail;
  final VoidCallback onBack;
  final VoidCallback onMenuTap;
  const _DetailHeader({required this.detail, required this.onBack, required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: _cyan.withAlpha(10),
        border: Border(bottom: BorderSide(color: _cyan.withAlpha(31))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                _HeaderIconBtn(text: '‹', size: 36, onTap: onBack),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DETALHE DO REGISTRO', style: GoogleFonts.inter(color: _cyan, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      const SizedBox(height: 2),
                      Text(detail.headerTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _HeaderIconBtn(text: '⋯', size: 32, onTap: onMenuTap),
              ],
            ),
          ),
          // Summary card
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cyan.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cyan.withAlpha(51)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: detail.color.withAlpha(38),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        _summaryEmoji(detail.type),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(detail.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          '${_fmtDate(detail.dateTime)} • ${_fmtTime(detail.dateTime)} • ${detail.location}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION: RESULTADO
// =============================================================================

class _ResultadoSection extends StatelessWidget {
  final RecordDetail detail;
  const _ResultadoSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final outcomes = _parseOutcomes(detail.source.details);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('RESULTADO'),
        const SizedBox(height: 8),
        if (outcomes.isEmpty)
          _ResultCard(
            emoji: '✓',
            color: _green,
            label: 'FINALIZADO',
            value: detail.status,
          )
        else
          ...outcomes.map((o) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ResultCard(
              emoji: o.emoji,
              color: o.color,
              label: o.label.toUpperCase(),
              value: o.detail,
            ),
          )),
      ],
    );
  }

  List<_OutcomeDisplay> _parseOutcomes(Map<String, dynamic> details) {
    final raw = details['_outcomes'];
    if (raw is! List || raw.isEmpty) {
      final resultado = details['Resultado'];
      if (resultado is String && resultado.trim().isNotEmpty && !resultado.toLowerCase().contains('final')) {
        return [_OutcomeDisplay(emoji: '✓', color: _green, label: resultado, detail: '')];
      }
      return [];
    }

    return raw.map<_OutcomeDisplay>((item) {
      final value = item is Map ? (item['result'] ?? item.values.first)?.toString() ?? '' : item.toString();
      return _mapResultToDisplay(value);
    }).toList();
  }

  _OutcomeDisplay _mapResultToDisplay(String value) {
    final lower = value.toLowerCase().replaceAll('_', ' ');
    if (lower.contains('drug')) return _OutcomeDisplay(emoji: '🚨', color: const Color(0xFFE74C3C), label: 'Droga apreendida', detail: '');
    if (lower.contains('weapon')) return _OutcomeDisplay(emoji: '🔫', color: const Color(0xFFE74C3C), label: 'Arma apreendida', detail: '');
    if (lower.contains('person') || lower.contains('detain')) return _OutcomeDisplay(emoji: '🚔', color: const Color(0xFFF39C12), label: 'Pessoa detida', detail: '');
    if (lower.contains('bo')) return _OutcomeDisplay(emoji: '📋', color: const Color(0xFF3498DB), label: 'BO registrado', detail: '');
    if (lower.contains('support')) return _OutcomeDisplay(emoji: '🤝', color: _green, label: 'Apoio prestado', detail: '');
    if (lower.contains('no ') || lower.contains('sem')) return _OutcomeDisplay(emoji: '✓', color: _green, label: 'Sem constatação', detail: '');
    return _OutcomeDisplay(emoji: '✓', color: _green, label: value, detail: '');
  }
}

class _OutcomeDisplay {
  final String emoji;
  final Color color;
  final String label;
  final String detail;
  const _OutcomeDisplay({required this.emoji, required this.color, required this.label, required this.detail});
}

class _ResultCard extends StatelessWidget {
  final String emoji;
  final Color color;
  final String label;
  final String value;
  const _ResultCard({required this.emoji, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                if (value.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(value, style: GoogleFonts.inter(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION: INFORMACOES
// =============================================================================

class _InformacoesSection extends StatelessWidget {
  final RecordDetail detail;
  const _InformacoesSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final rows = <_InfoItem>[
      _InfoItem(emoji: '⏱', label: 'Duração', value: detail.duration),
      _InfoItem(emoji: '👤', label: 'Condutor', value: detail.handlerName),
      _InfoItem(emoji: '🐕', label: 'Cão', value: detail.dogName),
      _InfoItem(emoji: '👥', label: 'Equipe', value: detail.team),
      _InfoItem(emoji: '🚗', label: 'Veículo', value: _vehicle(detail)),
      _InfoItem(emoji: '📍', label: 'Local', value: detail.location),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('INFORMAÇÕES'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                _InfoRowV2(item: rows[i]),
                if (i < rows.length - 1) Divider(height: 16, color: Colors.white.withAlpha(10)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _vehicle(RecordDetail d) {
    final details = d.source.details;
    for (final key in const ['Veículo', 'Veiculo', 'vehicle', 'Viatura']) {
      if (details.containsKey(key)) {
        final v = details[key]?.toString().trim() ?? '';
        if (v.isNotEmpty && v != 'null') return v;
      }
    }
    return 'Viatura padrão';
  }
}

class _InfoItem {
  final String emoji;
  final String label;
  final String value;
  const _InfoItem({required this.emoji, required this.label, required this.value});
}

class _InfoRowV2 extends StatelessWidget {
  final _InfoItem item;
  const _InfoRowV2({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(item.emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(item.label, style: GoogleFonts.inter(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            item.value.isEmpty ? '—' : item.value,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
            style: GoogleFonts.inter(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SECTION: TIMELINE
// =============================================================================

class _TimelineSection extends StatelessWidget {
  final RecordDetail detail;
  const _TimelineSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final events = detail.internalEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('LINHA DO TEMPO · ${events.length} EVENTOS'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < events.length; i++)
                _TimelineEventRow(event: events[i], isLast: i == events.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineEventRow extends StatelessWidget {
  final InternalEvent event;
  final bool isLast;
  const _TimelineEventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final style = _eventStyle(event.title);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(_fmtTime(event.time), style: GoogleFonts.inter(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: style.color.withAlpha(30),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(child: Text(style.emoji, style: const TextStyle(fontSize: 12))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                if (event.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(event.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: _textMuted, fontSize: 10)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _EventStyle _eventStyle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('iniciado') || lower.contains('início')) return const _EventStyle(emoji: '▶', color: Color(0xFF4DD0E1));
    if (lower.contains('chegada') || lower.contains('local')) return const _EventStyle(emoji: '📍', color: Color(0xFF3498DB));
    if (lower.contains('cão') || lower.contains('varredura') || lower.contains('empregado')) return const _EventStyle(emoji: '🐾', color: Color(0xFFF1C40F));
    if (lower.contains('foto') || lower.contains('anexa')) return const _EventStyle(emoji: '📷', color: Color(0xFF9B59B6));
    if (lower.contains('verifica') || lower.contains('área')) return const _EventStyle(emoji: '🛡', color: Color(0xFF2ECC71));
    if (lower.contains('finaliz') || lower.contains('conclu')) return const _EventStyle(emoji: '✓', color: Color(0xFF2ECC71));
    if (lower.contains('andamento') || lower.contains('pendente')) return const _EventStyle(emoji: '⏳', color: Color(0xFFF39C12));
    if (lower.contains('sincroniz')) return const _EventStyle(emoji: '☁', color: Color(0xFF4DD0E1));
    if (lower.contains('atualiz')) return const _EventStyle(emoji: '✏', color: Color(0xFF3498DB));
    return const _EventStyle(emoji: '•', color: Color(0xFF4DD0E1));
  }
}

class _EventStyle {
  final String emoji;
  final Color color;
  const _EventStyle({required this.emoji, required this.color});
}

// =============================================================================
// SECTION: AUDIT TRAIL
// =============================================================================

class _AuditSection extends StatelessWidget {
  final RecordDetail detail;
  const _AuditSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('TRILHA DE AUDITORIA'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(13)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < detail.auditEvents.length; i++)
                _AuditRow(event: detail.auditEvents[i], isLast: i == detail.auditEvents.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEvent event;
  final bool isLast;
  const _AuditRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final text = event.user.trim().isEmpty
        ? '${event.action} • ${_fmtDate(event.timestamp)} às ${_fmtTime(event.timestamp)}'
        : '${event.action} ${event.user} • ${_fmtDate(event.timestamp)} às ${_fmtTime(event.timestamp)}';
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: _cyan, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: GoogleFonts.inter(color: _textMuted, fontSize: 11, height: 1.3),
                children: [
                  if (event.user.trim().isNotEmpty) ...[
                    TextSpan(text: '${event.action} '),
                    TextSpan(text: event.user, style: GoogleFonts.inter(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' • ${_fmtDate(event.timestamp)} às ${_fmtTime(event.timestamp)}'),
                  ] else
                    TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CTA BAR
// =============================================================================

class _CtaBar extends StatelessWidget {
  final VoidCallback onPdfTap;
  final VoidCallback onShareTap;
  const _CtaBar({required this.onPdfTap, required this.onShareTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0.0, 0.8, 1.0],
          colors: [_bg, _bg, Color(0x00050D10)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: _CtaButton(
              label: 'Gerar PDF',
              icon: Icons.picture_as_pdf_outlined,
              filled: false,
              onTap: onPdfTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CtaButton(
              label: 'Compartilhar',
              icon: Icons.share_outlined,
              filled: true,
              onTap: onShareTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _CtaButton({required this.label, required this.icon, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: filled ? _cyan : _cyan.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: _cyan.withAlpha(77)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: filled ? _bg : _cyan, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: filled ? _bg : _cyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SHARED WIDGETS
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: GoogleFonts.inter(color: _cyan, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: _cyan.withAlpha(38))),
      ],
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final String text;
  final double size;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.text, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: _cyan.withAlpha(15),
          borderRadius: BorderRadius.circular(size / 4),
          border: Border.all(color: _cyan.withAlpha(51)),
        ),
        alignment: Alignment.center,
        child: Text(text, style: GoogleFonts.inter(color: _textPrimary, fontSize: size * 0.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: _cyan, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: GoogleFonts.inter(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// UTILITIES
// =============================================================================

String _fmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
String _fmtTime(DateTime d) => DateFormat('HH:mm').format(d);

String _summaryEmoji(HistoryEntryType type) {
  switch (type) {
    case HistoryEntryType.incident:
      return '🛡';
    case HistoryEntryType.health:
      return '⚕';
    case HistoryEntryType.training:
      return '🎯';
    case HistoryEntryType.nutrition:
      return '🍖';
  }
}
