import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/screens/profile_screen.dart';

part 'history_models.dart';
part 'history_filters.dart';
part 'history_timeline_list.dart';
part 'history_timeline_item.dart';
part 'history_data_loader.dart';

const Color _hBg = Color(0xFF050D10);
const Color _hCyan = Color(0xFF4DD0E1);
const Color _hTextPrimary = Color(0xFFFFFFFF);
const Color _hTextSecondary = Color(0xFFB0C4CC);
const Color _hTextMuted = Color(0xFF5A7280);
const Color _hTextDimmed = Color(0xFF7A8A92);
const Color _hGreen = Color(0xFF2ECC71);
const Color _hYellow = Color(0xFFF1C40F);
const Color _hRed = Color(0xFFE74C3C);
const Color _hPurple = Color(0xFF9B59B6);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _periodFilter = 'Esta semana';
  String _typeFilter = 'Tudo';
  DateTimeRange? _customRange;
  String? _lastLoadedDogId;
  int _visibleCount = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final userVM = Provider.of<UserViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);

    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) {
      return const _HistoryNoShift();
    }

    final dogId = shiftVM.activeDogId!;
    if (_lastLoadedDogId != dogId) {
      _lastLoadedDogId = dogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAllData();
      });
    }

    final dog = dogVM.dogs.cast<Dog?>().firstWhere(
      (d) => d?.id == dogId,
      orElse: () => dogVM.dogs.isNotEmpty ? dogVM.dogs.first : null,
    );

    if (dog == null) {
      return const _HistoryNoShift();
    }

    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final callsign = userVM.displayNameFor(ra: currentRa, firebaseUser: fbUser);
    final handlerUser = userVM.findByRa(currentRa);
    final handlerPhoto = handlerUser?.photoUrl?.trim();
    final firebasePhoto = fbUser?.photoURL?.trim();
    final handlerImageUrl = handlerPhoto != null && handlerPhoto.isNotEmpty
        ? handlerPhoto
        : firebasePhoto != null && firebasePhoto.isNotEmpty
        ? firebasePhoto
        : null;

    final allEntries = _buildAllEntries(dogId);
    final filteredEntries = _filterEntries(allEntries);
    final visibleEntries = filteredEntries.take(_visibleCount).toList();
    final groupedEntries = _groupEntriesByDay(visibleEntries);
    final daysCount = groupedEntries.length;

    return Scaffold(
      backgroundColor: _hBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: _hBg,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _HistoryShiftHeader(
                dog: dog,
                callsign: callsign,
                handlerImageUrl: handlerImageUrl,
                shiftStartTime: shiftVM.shiftStartTime,
              ),
              _PageTitleRow(
                onExport: () => _exportPdf(filteredEntries, dog, callsign),
              ),
              _PeriodFilterChips(
                selected: _periodFilter,
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  if (v == 'Personalizado') {
                    _openDateRangePicker();
                    return;
                  }
                  setState(() {
                    _periodFilter = v;
                    _visibleCount = 30;
                  });
                },
              ),
              _CategoryFilterChips(
                selected: _typeFilter,
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _typeFilter = v;
                    _visibleCount = 30;
                  });
                },
              ),
              _FilterSummaryRow(
                count: filteredEntries.length,
                days: daysCount,
                onMoreFilters: _openFilterSheet,
              ),
              Expanded(
                child: _HistoryTimeline(
                  groups: groupedEntries,
                  hasMore: filteredEntries.length > visibleEntries.length,
                  onLoadMore: () {
                    HapticFeedback.selectionClick();
                    setState(() => _visibleCount += 30);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<HistoryEntry> _filterEntries(List<HistoryEntry> entries) {
    final range = _periodDateRange();

    return entries.where((entry) {
      final inRange =
          !entry.time.isBefore(range.start) && entry.time.isBefore(range.end);
      final typeMatches =
          _typeFilter == 'Tudo' || entry.category == _typeFilter;

      return inRange && typeMatches;
    }).toList()..sort((a, b) => b.time.compareTo(a.time));
  }

  Future<void> _exportPdf(
    List<HistoryEntry> entries,
    Dog dog,
    String handlerName,
  ) async {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nao ha registros no periodo filtrado.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _hCyan.withAlpha(200),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bytes = await _buildHistoryPdf(entries, dog, handlerName);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'historico_${dog.name}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  Future<Uint8List> _buildHistoryPdf(
    List<HistoryEntry> entries,
    Dog dog,
    String handlerName,
  ) async {
    final pdf = pw.Document();
    final range = _periodDateRange();
    final accent = PdfColor.fromHex('5A4080');
    final rangeEnd = range.end.subtract(const Duration(days: 1));
    final dateLabel =
        '${DateFormat('dd/MM/yyyy').format(range.start)} a ${DateFormat('dd/MM/yyyy').format(rangeEnd)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'GUARDA CIVIL MUNICIPAL DE LIMEIRA',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Historico operacional do cao K9',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Text(
                DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(height: 2, color: accent),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F6F2FA'),
              border: pw.Border.all(color: accent, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pdfMetric('Cao K9', dog.name),
                _pdfMetric('Condutor', handlerName),
                _pdfMetric('Periodo', dateLabel),
                _pdfMetric('Registros', entries.length.toString()),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const ['Data', 'Categoria', 'Registro', 'Responsavel'],
            data: entries
                .map(
                  (entry) => [
                    DateFormat('dd/MM HH:mm').format(entry.time),
                    entry.category,
                    '${entry.title}\n${entry.subtitle}',
                    entry.author,
                  ],
                )
                .toList(),
            headerDecoration: pw.BoxDecoration(color: accent),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
            oddRowDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F8FAFB'),
            ),
          ),
        ],
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Canil K9 GCM Limeira',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Pagina ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfMetric(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }
}

class _PageTitleRow extends StatelessWidget {
  final VoidCallback onExport;

  const _PageTitleRow({required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Text(
            'Histórico',
            style: GoogleFonts.inter(
              color: _hTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _hCyan.withAlpha(26),
                border: Border.all(color: _hCyan.withAlpha(77)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📄', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text(
                    'Exportar PDF',
                    style: GoogleFonts.inter(
                      color: _hCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

class _FilterSummaryRow extends StatelessWidget {
  final int count;
  final int days;
  final VoidCallback onMoreFilters;

  const _FilterSummaryRow({
    required this.count,
    required this.days,
    required this.onMoreFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: _hTextDimmed,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: '$count registros',
                  style: const TextStyle(
                    color: _hTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' · $days ${days == 1 ? 'dia' : 'dias'}'),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onMoreFilters,
            child: Text(
              'Mais filtros →',
              style: GoogleFonts.inter(
                color: _hCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryShiftHeader extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? handlerImageUrl;
  final DateTime? shiftStartTime;

  const _HistoryShiftHeader({
    required this.dog,
    required this.callsign,
    this.handlerImageUrl,
    this.shiftStartTime,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = _formatElapsed(shiftStartTime);
    final conductorName = _shortName(callsign);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: const Border(bottom: BorderSide(color: Color(0x1E4DD0E1))),
      ),
      child: Row(
        children: [
          // Avatares sobrepostos
          SizedBox(
            width: 70,
            height: 44,
            child: Stack(
              children: [
                _HAvatar(
                  imageUrl: dog.profileImageUrl,
                  fallbackText: dog.name.isNotEmpty
                      ? dog.name
                            .substring(0, dog.name.length.clamp(0, 4))
                            .toUpperCase()
                      : 'K9',
                  borderColor: AppTheme.primary,
                ),
                Positioned(
                  left: 30,
                  child: _HAvatar(
                    imageUrl: handlerImageUrl,
                    fallbackText: conductorName.length >= 3
                        ? conductorName.substring(0, 3).toUpperCase()
                        : conductorName.toUpperCase(),
                    borderColor: AppTheme.primary.withAlpha(128),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${dog.name} · GCM $conductorName',
                  style: GoogleFonts.inter(
                    color: _hTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hGreen,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Turno ativo',
                      style: GoogleFonts.inter(
                        color: _hGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '· $elapsed',
                      style: GoogleFonts.inter(
                        color: _hTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão trocar cão
          _HActionButton(icon: Icons.compare_arrows_rounded, onTap: () {}),
          const SizedBox(width: 6),
          // Botão perfil
          _HActionButton(
            icon: Icons.person_outline_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  String _shortName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Condutor';
    final pieces = trimmed.split(RegExp(r'\s+'));
    return pieces.length <= 1 ? pieces.first : pieces.last;
  }

  String _formatElapsed(DateTime? start) {
    if (start == null) return '--';
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }
}

class _HAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final Color borderColor;

  const _HAvatar({
    this.imageUrl,
    required this.fallbackText,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A2A30),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (_, _) => _fallbackWidget(),
                errorWidget: (_, _, _) => _fallbackWidget(),
              )
            : _fallbackWidget(),
      ),
    );
  }

  Widget _fallbackWidget() {
    return Container(
      color: const Color(0xFF1A2A30),
      alignment: Alignment.center,
      child: Text(
        fallbackText,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withAlpha(51)),
        ),
        child: Center(child: Icon(icon, color: AppTheme.primary, size: 16)),
      ),
    );
  }
}

class _HistoryNoShift extends StatelessWidget {
  const _HistoryNoShift();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hBg,
      body: Center(
        child: Text(
          'Nenhum turno ativo.\nInicie um turno para ver o histórico.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: _hTextMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
