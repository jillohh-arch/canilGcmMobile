import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';

const Color _detailBackground = Color(0xFF050D10);
const Color _detailTextPrimary = Color(0xFFF4F7F8);
const Color _detailTextSecondary = Color(0xFFA7B4BA);
const Color _detailBorder = Color(0x523E7180);
const Color _detailBorderStrong = Color(0x804DD0E1);
const Color _detailGreen = Color(0xFF74DB69);
const Color _detailYellow = Color(0xFFFFC23A);
const double _detailBottomNavHeight = 86;

const LinearGradient _detailPanelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xF2112028), Color(0xF207151B), Color(0xF20A1E25)],
);

BoxDecoration _detailPanelDecoration({Color? borderColor}) {
  return BoxDecoration(
    gradient: _detailPanelGradient,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor ?? _detailBorder, width: 1.1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(68),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: AppTheme.primary.withAlpha(12),
        blurRadius: 20,
        offset: const Offset(0, -2),
      ),
    ],
  );
}

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return RegistroDetalhePage(entry: entry);
  }
}

class RegistroDetalhePage extends StatelessWidget {
  final HistoryEntry entry;

  const RegistroDetalhePage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final detail = RecordDetail.fromEntry(entry);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _detailBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _detailBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF061017),
                    Color(0xFF050D10),
                    Color(0xFF050D10),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 188),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DetailHeader(
                        detail: detail,
                        onBack: () => Navigator.of(context).pop(),
                        onMenuTap: () => _openRecordMenu(context),
                      ),
                      const SizedBox(height: 14),
                      MainRecordCard(detail: detail),
                      const SizedBox(height: 12),
                      RecordStatusCard(detail: detail),
                      const SizedBox(height: 12),
                      OperationalDataCard(detail: detail),
                      if (MediaAttachmentsCard.hasMedia(detail)) ...[
                        const SizedBox(height: 12),
                        MediaAttachmentsCard(detail: detail),
                      ],
                      const SizedBox(height: 12),
                      InternalTimelineCard(detail: detail),
                      const SizedBox(height: 12),
                      ObservationCard(detail: detail),
                      const SizedBox(height: 12),
                      AuditTrailCard(detail: detail),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _detailBottomNavHeight + bottomInset,
              child: DetailBottomActionBar(
                onPdfTap: () => _notify(context, 'Geração de PDF preparada.'),
                onShareTap: () =>
                    _notify(context, 'Compartilhamento preparado.'),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DetailOperationalBottomNav(),
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
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: _detailPanelDecoration(
                borderColor: _detailBorderStrong,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuActionRow(
                    icon: Icons.edit_outlined,
                    label: 'Editar registro',
                    onTap: () {
                      Navigator.of(context).pop();
                      _notify(context, 'Edição do registro preparada.');
                    },
                  ),
                  Divider(height: 1, color: _detailBorder),
                  _MenuActionRow(
                    icon: Icons.copy_all_outlined,
                    label: 'Copiar resumo operacional',
                    onTap: () {
                      Navigator.of(context).pop();
                      _notify(context, 'Resumo operacional copiado.');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.inter(
              color: _detailTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF0F2026),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
  }
}

class DetailHeader extends StatelessWidget {
  final RecordDetail detail;
  final VoidCallback onBack;
  final VoidCallback onMenuTap;

  const DetailHeader({
    super.key,
    required this.detail,
    required this.onBack,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DetailIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: onBack,
          semanticLabel: 'Voltar',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DETALHE DO REGISTRO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Hero(
                tag: detail.source.heroTag,
                flightShuttleBuilder:
                    (
                      flightContext,
                      animation,
                      flightDirection,
                      fromHeroContext,
                      toHeroContext,
                    ) {
                      return Material(
                        color: Colors.transparent,
                        child: toHeroContext.widget,
                      );
                    },
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    detail.headerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _detailTextPrimary,
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _DetailIconButton(
          icon: Icons.more_vert_rounded,
          onTap: onMenuTap,
          semanticLabel: 'Mais ações',
        ),
      ],
    );
  }
}

class MainRecordCard extends StatelessWidget {
  final RecordDetail detail;

  const MainRecordCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final accentColor = detail.type == HistoryEntryType.incident
        ? _detailYellow
        : detail.color;

    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      borderColor: detail.type == HistoryEntryType.incident
          ? _detailYellow.withAlpha(130)
          : _detailBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: '${detail.source.heroTag}_icon',
            child: SizedBox(
              width: 66,
              child: Icon(
                detail.type == HistoryEntryType.incident
                    ? Icons.shield_outlined
                    : detail.icon,
                color: accentColor,
                size: 54,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailChip(label: detail.typeChip, color: accentColor),
                const SizedBox(height: 9),
                Text(
                  detail.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _detailTextPrimary,
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  detail.location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _detailTextSecondary,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 28,
                  runSpacing: 8,
                  children: [
                    _CompactMeta(
                      icon: Icons.calendar_month_outlined,
                      text:
                          '${_formatDate(detail.dateTime)} • ${_formatTime(detail.dateTime)}',
                    ),
                    _CompactMeta(
                      icon: Icons.person_rounded,
                      text: detail.author,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecordStatusCard extends StatelessWidget {
  final RecordDetail detail;

  const RecordStatusCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final isFinished = detail.status.toLowerCase().contains('final');
    final statusColor = isFinished ? _detailGreen : _detailYellow;
    final syncColor = detail.syncStatus.toLowerCase().contains('sincron')
        ? _detailGreen
        : _detailYellow;

    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DetailSectionLabel('STATUS DO REGISTRO'),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(16),
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor.withAlpha(150)),
                ),
                child: Icon(
                  isFinished
                      ? Icons.verified_outlined
                      : Icons.pending_actions_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _detailTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isFinished ? 'Sem pendências' : 'Registro ainda ativo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _detailTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SyncChip(
                label: detail.syncStatus.toUpperCase(),
                color: syncColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OperationalDataCard extends StatelessWidget {
  final RecordDetail detail;

  const OperationalDataCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final rows = [
      MapEntry('Binômio:', '${detail.dogName} • ${detail.handlerName}'),
      MapEntry('Tipo:', detail.typeLabel),
      MapEntry('Categoria:', detail.category),
      MapEntry('Local:', detail.location),
      MapEntry('Duração:', detail.duration),
      MapEntry('Equipe:', detail.team),
    ];

    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleWithIcon(
            icon: Icons.assignment_outlined,
            label: 'DADOS OPERACIONAIS',
          ),
          const SizedBox(height: 11),
          for (int i = 0; i < rows.length; i++) ...[
            _OperationalTextRow(label: rows[i].key, value: rows[i].value),
            if (i < rows.length - 1) const SizedBox(height: 3),
          ],
        ],
      ),
    );
  }
}

class MediaAttachmentsCard extends StatelessWidget {
  final RecordDetail detail;

  const MediaAttachmentsCard({super.key, required this.detail});

  static bool hasMedia(RecordDetail detail) => _media(detail).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final media = _media(detail);
    if (media.isEmpty) return const SizedBox.shrink();

    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: _DetailSectionLabel('MÍDIAS ANEXADAS')),
              Text(
                '${media.length} ${media.length == 1 ? "arquivo" : "arquivos"}',
                style: GoogleFonts.inter(
                  color: _detailTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return _MediaThumb(
                  item: media[index],
                  fallbackTime: detail.dateTime.add(
                    Duration(minutes: 11 + (index * 3)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _media(RecordDetail detail) {
    final raw = detail.source.details['_mediaAttachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class InternalTimelineCard extends StatelessWidget {
  final RecordDetail detail;

  const InternalTimelineCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleWithIcon(
            icon: Icons.schedule_rounded,
            label: 'LINHA DO TEMPO',
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < detail.internalEvents.length; i++)
            _InternalTimelineRow(
              event: detail.internalEvents[i],
              color: i == detail.internalEvents.length - 1
                  ? _detailGreen
                  : AppTheme.primary,
              isLast: i == detail.internalEvents.length - 1,
            ),
        ],
      ),
    );
  }
}

class ObservationCard extends StatelessWidget {
  final RecordDetail detail;

  const ObservationCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final notes = detail.notes.trim().isEmpty
        ? 'Nenhuma observação registrada.'
        : detail.notes;

    return _DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleWithIcon(
            icon: Icons.description_outlined,
            label: 'OBSERVAÇÕES',
          ),
          const SizedBox(height: 10),
          Text(
            notes,
            style: GoogleFonts.inter(
              color: notes == 'Nenhuma observação registrada.'
                  ? _detailTextSecondary
                  : _detailTextPrimary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class AuditTrailCard extends StatelessWidget {
  final RecordDetail detail;

  const AuditTrailCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return _DetailPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitleWithIcon(
            icon: Icons.admin_panel_settings_outlined,
            label: 'TRILHA DE AUDITORIA',
          ),
          const SizedBox(height: 11),
          for (int i = 0; i < detail.auditEvents.length; i++)
            _AuditTrailRow(
              event: detail.auditEvents[i],
              isLast: i == detail.auditEvents.length - 1,
            ),
        ],
      ),
    );
  }
}

class DetailBottomActionBar extends StatelessWidget {
  final VoidCallback onPdfTap;
  final VoidCallback onShareTap;

  const DetailBottomActionBar({
    super.key,
    required this.onPdfTap,
    required this.onShareTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF7050D10),
        border: Border(
          top: BorderSide(color: _detailBorderStrong.withAlpha(80)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _DetailActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Gerar PDF',
                  onTap: onPdfTap,
                  outlined: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DetailActionButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Compartilhar',
                  onTap: onShareTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailOperationalBottomNav extends StatelessWidget {
  const DetailOperationalBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF07141B),
        border: Border(
          top: BorderSide(color: AppTheme.primary.withAlpha(45), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(22),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _detailBottomNavHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Expanded(
                child: _DetailNavItem(
                  icon: Icons.home_outlined,
                  label: 'Turno',
                  selected: false,
                ),
              ),
              Expanded(
                child: _DetailNavItem(
                  icon: Icons.history_rounded,
                  label: 'Histórico',
                  selected: true,
                ),
              ),
              SizedBox(width: 106, child: _DetailCenterNavAction()),
              Expanded(
                child: _DetailNavItem(
                  icon: Icons.fitness_center_rounded,
                  label: 'Treino',
                  selected: false,
                ),
              ),
              Expanded(
                child: _DetailNavItem(
                  icon: Icons.pets_rounded,
                  label: 'Cão',
                  selected: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _DetailNavItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : const Color(0xFFB4BFC5);

    return SizedBox(
      height: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 29),
          const SizedBox(height: 5),
          _DetailAutoFitText(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: selected ? 34 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCenterNavAction extends StatelessWidget {
  const _DetailCenterNavAction();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _detailBottomNavHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 76,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF0A2430),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                  bottom: Radius.circular(2),
                ),
                border: Border.all(color: AppTheme.primary, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(58),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppTheme.primary,
                size: 34,
              ),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: 58,
            child: _DetailAutoFitText(
              'Nova Ocorrência',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const _DetailPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _detailPanelDecoration(borderColor: borderColor),
      child: child,
    );
  }
}

class _DetailIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  const _DetailIconButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(icon, color: _detailTextPrimary, size: 34),
          ),
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final Color color;

  const _DetailChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(170)),
      ),
      child: _DetailAutoFitText(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SyncChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 154),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(170)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_rounded, color: color, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: _DetailAutoFitText(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 15),
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: _detailTextSecondary,
              fontSize: 13,
              height: 1.22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitleWithIcon extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitleWithIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 21),
        const SizedBox(width: 12),
        Expanded(child: _DetailSectionLabel(label)),
      ],
    );
  }
}

class _DetailSectionLabel extends StatelessWidget {
  final String label;

  const _DetailSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        color: AppTheme.primary,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.05,
      ),
    );
  }
}

class _OperationalTextRow extends StatelessWidget {
  final String label;
  final String value;

  const _OperationalTextRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 350;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 92 : 118,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _detailTextSecondary,
                  fontSize: 14,
                  height: 1.18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _detailTextPrimary,
                  fontSize: 14,
                  height: 1.18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final Map<String, dynamic> item;
  final DateTime fallbackTime;

  const _MediaThumb({required this.item, required this.fallbackTime});

  @override
  Widget build(BuildContext context) {
    final url = item['url']?.toString() ?? '';
    final type = item['type']?.toString().toLowerCase() ?? '';
    final timestamp = item['timestamp'];
    final time = timestamp is DateTime ? timestamp : fallbackTime;
    final isVideo = type.contains('video');
    final isImage =
        !isVideo &&
        (type.isEmpty || type.contains('image') || type.contains('photo'));

    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.primary.withAlpha(165)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: url.isNotEmpty && isImage
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _MediaFallbackIcon(
                      icon: Icons.broken_image_outlined,
                    ),
                  )
                : _MediaFallbackIcon(
                    icon: isVideo
                        ? Icons.play_circle_outline_rounded
                        : Icons.image_outlined,
                  ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(58))),
          Positioned(
            left: 7,
            top: 7,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: _detailBackground.withAlpha(220),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.play_arrow_rounded : Icons.image_outlined,
                color: _detailTextPrimary,
                size: 16,
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              _formatTime(time),
              style: GoogleFonts.inter(
                color: _detailTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              width: 19,
              height: 19,
              decoration: const BoxDecoration(
                color: _detailGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: _detailBackground,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaFallbackIcon extends StatelessWidget {
  final IconData icon;

  const _MediaFallbackIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101B21),
      alignment: Alignment.center,
      child: Icon(icon, color: AppTheme.primary, size: 28),
    );
  }
}

class _InternalTimelineRow extends StatelessWidget {
  final InternalEvent event;
  final Color color;
  final bool isLast;

  const _InternalTimelineRow({
    required this.event,
    required this.color,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 47,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              _formatTime(event.time),
              style: GoogleFonts.inter(
                color: _detailTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 26,
          height: event.subtitle.trim().isEmpty ? 42 : 58,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (!isLast)
                Positioned(
                  top: 13,
                  bottom: 0,
                  child: Container(width: 1, color: _detailBorderStrong),
                ),
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: _detailBackground, width: 2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _detailTextPrimary,
                    fontSize: 13.5,
                    height: 1.18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                if (event.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _detailTextSecondary,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditTrailRow extends StatelessWidget {
  final AuditEvent event;
  final bool isLast;

  const _AuditTrailRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final text = event.user.trim().isEmpty
        ? '${event.action} • ${_formatDate(event.timestamp)} às ${_formatTime(event.timestamp)}'
        : '${event.action} ${event.user} • ${_formatDate(event.timestamp)} às ${_formatTime(event.timestamp)}';

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: AppTheme.primary,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: _detailTextSecondary,
                fontSize: 12.2,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  const _DetailActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = outlined ? Colors.transparent : AppTheme.primary;
    final foreground = outlined ? AppTheme.primary : _detailBackground;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(180)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 19),
              const SizedBox(width: 8),
              Flexible(
                child: _DetailAutoFitText(
                  label,
                  style: GoogleFonts.inter(
                    color: foreground,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: _detailTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailAutoFitText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _DetailAutoFitText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: style,
          ),
        );
        if (!constraints.maxWidth.isFinite) return fitted;
        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String _formatTime(DateTime date) => DateFormat('HH:mm').format(date);
