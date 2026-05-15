import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/incidents/domain/incident_progress_update.dart';

/// Tela de detalhe expandido de um item do histórico.
/// Usa Hero animation para transição suave do item clicado.
class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D10),
      body: SafeArea(
        child: Column(
          children: [
            // Header com botão voltar
            _buildDetailHeader(context),
            // Conteúdo scrollável
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildResultSection(),
                    _buildInfoSection(),
                    _buildProgressSection(),
                    _buildMediaSection(),
                    _buildAuditSection(),
                  ],
                ),
              ),
            ),
            // CTA bar
            _buildCtaBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF4DD0E1).withAlpha(10),
      ),
      child: Column(
        children: [
          // Top row: back + title + actions
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DETALHE DO REGISTRO',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4DD0E1),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Hero(
                      tag: entry.heroTag,
                      flightShuttleBuilder: (
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
                          entry.category,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF4DD0E1).withAlpha(20),
                  border: Border.all(color: const Color(0xFF4DD0E1).withAlpha(51)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.more_horiz, color: Color(0xFF4DD0E1), size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Summary card
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF4DD0E1).withAlpha(15),
        border: Border.all(color: const Color(0xFF4DD0E1).withAlpha(51)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Ícone grande
          Hero(
            tag: '${entry.heroTag}_icon',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: entry.categoryColor.withAlpha(38),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(entry.categoryIcon, color: entry.categoryColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildSummaryMeta(),
                  style: GoogleFonts.inter(
                    color: const Color(0xFFB0C4CC),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummaryMeta() {
    final parts = <String>[];
    parts.add(DateFormat('dd/MM/yyyy').format(entry.time));
    parts.add(DateFormat('HH:mm').format(entry.time));
    if (entry.location.isNotEmpty) {
      parts.add(entry.location);
    }
    return parts.join(' · ');
  }

  // ─── RESULTADO ───────────────────────────────────────────────
  Widget _buildResultSection() {
    final resultado = entry.details['Resultado']?.toString() ?? '';
    if (resultado.isEmpty || resultado == 'Em andamento') {
      return const SizedBox.shrink();
    }

    final isSuccess = resultado.toLowerCase().contains('êxito') ||
        resultado.toLowerCase().contains('apreend') ||
        resultado.toLowerCase().contains('localiz');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('RESULTADO'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2ECC71).withAlpha(15),
            border: Border.all(color: const Color(0xFF2ECC71).withAlpha(51)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withAlpha(38),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isSuccess ? Icons.check : Icons.info_outline,
                  color: const Color(0xFF2ECC71),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuccess ? 'RESULTADO POSITIVO' : 'RESULTADO',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF2ECC71),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      resultado,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── INFORMAÇÕES (key/value) ─────────────────────────────────
  Widget _buildInfoSection() {
    final visibleDetails = <MapEntry<String, String>>[];

    for (final kv in entry.details.entries) {
      // Pula campos internos e vazios
      if (kv.key.startsWith('_')) continue;
      final value = kv.value?.toString().trim() ?? '';
      if (value.isEmpty || value == 'null') continue;
      if (kv.key == 'Resultado') continue; // já mostrado acima
      visibleDetails.add(MapEntry(kv.key, value));
    }

    if (visibleDetails.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('INFORMAÇÕES'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            border: Border.all(color: Colors.white.withAlpha(20)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: visibleDetails.asMap().entries.map((mapEntry) {
              final index = mapEntry.key;
              final kv = mapEntry.value;
              final isLast = index == visibleDetails.length - 1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: Color(0x0AFFFFFF)),
                        ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _iconForKey(kv.key),
                      color: const Color(0xFF4DD0E1),
                      size: 13,
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: Text(
                        kv.key,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF7A8A92),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        kv.value,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── LINHA DO TEMPO DE PROGRESSO (ocorrências) ───────────────
  Widget _buildProgressSection() {
    final updates = entry.details['_progressUpdates'];
    if (updates == null || updates is! List || updates.isEmpty) {
      return const SizedBox.shrink();
    }

    final typedUpdates = updates as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('LINHA DO TEMPO · ${typedUpdates.length} EVENTOS'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(15)),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: typedUpdates.asMap().entries.map((mapEntry) {
              final index = mapEntry.key;
              final update = mapEntry.value;
              final isLast = index == typedUpdates.length - 1;

              String title = '';
              String meta = '';
              String time = '';

              if (update is IncidentProgressUpdate) {
                title = update.title;
                meta = update.description;
                time = DateFormat('HH:mm').format(update.timestamp);
              } else if (update is Map) {
                title = update['title']?.toString() ?? '';
                meta = update['description']?.toString() ?? '';
                final ts = update['timestamp'];
                if (ts is DateTime) {
                  time = DateFormat('HH:mm').format(ts);
                }
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: Color(0x0AFFFFFF)),
                        ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        time,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF5A7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DD0E1).withAlpha(26),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.circle,
                        color: Color(0xFF4DD0E1),
                        size: 8,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF7A8A92),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── MÍDIAS / IMAGENS ─────────────────────────────────────────
  Widget _buildMediaSection() {
    final media = entry.details['_mediaAttachments'];
    if (media == null || media is! List || media.isEmpty) {
      return const SizedBox.shrink();
    }

    final attachments = media.cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('MÍDIAS · ${attachments.length}'),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: attachments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              final url = attachment['url']?.toString() ?? '';
              final type = attachment['type']?.toString() ?? 'image';

              if (url.isEmpty) return const SizedBox.shrink();

              if (type.contains('image') || type.contains('photo')) {
                return GestureDetector(
                  onTap: () => _showFullImage(context, url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(20)),
                        ),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFF5A7280),
                          size: 28,
                        ),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4DD0E1),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }

              // Outros tipos de mídia (vídeo, documento)
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type.contains('video')
                          ? Icons.videocam_outlined
                          : Icons.insert_drive_file_outlined,
                      color: const Color(0xFF4DD0E1),
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.contains('video') ? 'Vídeo' : 'Arquivo',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF7A8A92),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black87,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── TRILHA DE AUDITORIA ─────────────────────────────────────
  Widget _buildAuditSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('TRILHA DE AUDITORIA'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(5),
            border: Border.all(color: Colors.white.withAlpha(13)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              _buildAuditRow(
                icon: Icons.push_pin,
                text: 'Criado por ${entry.authorName.isNotEmpty ? entry.authorName : "—"}',
                date: DateFormat('dd/MM/yyyy HH:mm').format(entry.time),
              ),
              if (entry.editedAt != null)
                _buildAuditRow(
                  icon: Icons.edit,
                  text: 'Editado',
                  date: DateFormat('dd/MM/yyyy HH:mm').format(entry.editedAt!),
                ),
              if (entry.details['Status'] == 'Concluída' ||
                  entry.details['Fim'] != null)
                _buildAuditRow(
                  icon: Icons.check_circle_outline,
                  text: 'Finalizado',
                  date: entry.details['Fim']?.toString() ?? '',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditRow({
    required IconData icon,
    required String text,
    required String date,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4DD0E1), size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$text · $date',
              style: GoogleFonts.inter(
                color: const Color(0xFF7A8A92),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CTA BAR ─────────────────────────────────────────────────
  Widget _buildCtaBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF050D10).withAlpha(0),
            const Color(0xFF050D10),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                // TODO: gerar PDF
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF4DD0E1).withAlpha(26),
                  border: Border.all(color: const Color(0xFF4DD0E1).withAlpha(77)),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Color(0xFF4DD0E1), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Gerar PDF',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4DD0E1),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                // TODO: compartilhar
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF4DD0E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share, color: Color(0xFF050D10), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'COMPARTILHAR',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF050D10),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: const Color(0xFF4DD0E1),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: const Color(0xFF4DD0E1).withAlpha(38),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForKey(String key) {
    switch (key.toLowerCase()) {
      case 'duração':
        return Icons.timer_outlined;
      case 'condutor':
      case 'veterinário':
        return Icons.person_outline;
      case 'cão':
        return Icons.pets;
      case 'equipe':
        return Icons.group_outlined;
      case 'veículo':
        return Icons.directions_car_outlined;
      case 'local':
      case 'localização':
        return Icons.location_on_outlined;
      case 'clima':
        return Icons.cloud_outlined;
      case 'peso':
        return Icons.monitor_weight_outlined;
      case 'vacinas':
        return Icons.vaccines_outlined;
      case 'tipo':
        return Icons.category_outlined;
      case 'status':
        return Icons.info_outline;
      default:
        return Icons.label_outline;
    }
  }
}
