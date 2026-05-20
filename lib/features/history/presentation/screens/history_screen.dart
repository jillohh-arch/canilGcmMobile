import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
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
  String _periodFilter = 'Hoje';
  String _typeFilter = 'Tudo';
  DateTimeRange? _customRange;
  String? _lastLoadedDogId;

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
    final callsign = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: fbUser,
    );

    final allEntries = _buildAllEntries(dogId);
    final filteredEntries = _filterEntries(allEntries);
    final groupedEntries = _groupEntriesByDay(filteredEntries);
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
                shiftStartTime: shiftVM.shiftStartTime,
              ),
              _PageTitleRow(onExport: _exportPdf),
              _PeriodFilterChips(
                selected: _periodFilter,
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  if (v == 'Personalizado') {
                    _openDateRangePicker();
                    return;
                  }
                  setState(() => _periodFilter = v);
                },
              ),
              _CategoryFilterChips(
                selected: _typeFilter,
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _typeFilter = v);
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

  void _exportPdf() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'PDF do histórico em desenvolvimento',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _hCyan.withAlpha(200),
        behavior: SnackBarBehavior.floating,
      ),
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
  final DateTime? shiftStartTime;

  const _HistoryShiftHeader({
    required this.dog,
    required this.callsign,
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
        border: const Border(
          bottom: BorderSide(color: Color(0x1E4DD0E1)),
        ),
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
                      ? dog.name.substring(0, dog.name.length.clamp(0, 4)).toUpperCase()
                      : 'K9',
                  borderColor: AppTheme.primary,
                ),
                Positioned(
                  left: 30,
                  child: _HAvatar(
                    imageUrl: null,
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
          _HActionButton(
            icon: Icons.compare_arrows_rounded,
            onTap: () {},
          ),
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
        child: Center(
          child: Icon(icon, color: AppTheme.primary, size: 16),
        ),
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
