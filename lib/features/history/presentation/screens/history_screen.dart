import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/routine/domain/routine_model.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';

part 'history_models.dart';
part 'history_filters.dart';
part 'history_timeline_list.dart';
part 'history_timeline_item.dart';
part 'history_data_loader.dart';

/// Cores do tema (consistentes com o mockup)
final _bgColor = AppTheme.background;
const _cyanAccent = Color(0xFF4DD0E1);
const _purpleAccent = Color(0xFF9B59B6);
const _redAccent = Color(0xFFE74C3C);
const _yellowAccent = Color(0xFFF1C40F);
const _textPrimary = Colors.white;
const _textSecondary = Color(0xFFB0C4CC);
const _textTertiary = Color(0xFF7A8A92);
const _textMuted = Color(0xFF5A7280);
const _borderSubtle = Color(0x14FFFFFF);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// Filtro de período selecionado
  String _periodFilter = 'Esta semana';

  /// Filtro de tipo selecionado
  String _typeFilter = 'Tudo';

  String? _lastLoadedDogId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    if (!shiftVM.hasActiveShift) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: Text(
            'Nenhum turno ativo.',
            style: GoogleFonts.inter(color: Colors.white70),
          ),
        ),
      );
    }

    final dogId = shiftVM.activeDogId!;

    // Recarrega dados se o cão mudou
    if (_lastLoadedDogId != dogId) {
      _lastLoadedDogId = dogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAllData();
      });
    }

    final entries = _buildFilteredEntries(dogId);
    final groupedEntries = _groupEntriesByDay(entries);

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título + Export
            _buildTitleRow(),
            // Filtros de período
            _buildPeriodFilters(),
            // Filtros de tipo
            _buildTypeFilters(),
            // Resumo
            _buildFilterSummary(entries.length),
            // Timeline
            Expanded(
              child: _buildTimeline(groupedEntries, dogId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Histórico',
            style: GoogleFonts.inter(
              color: _textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // TODO: export PDF
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _cyanAccent.withAlpha(26),
                border: Border.all(color: _cyanAccent.withAlpha(77)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf, color: _cyanAccent, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    'Exportar PDF',
                    style: GoogleFonts.inter(
                      color: _cyanAccent,
                      fontSize: 12,
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

  Widget _buildFilterSummary(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(fontSize: 12, color: _textTertiary),
              children: [
                TextSpan(
                  text: '$count registros',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              // TODO: mais filtros
            },
            child: Text(
              'Mais filtros →',
              style: GoogleFonts.inter(
                color: _cyanAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
