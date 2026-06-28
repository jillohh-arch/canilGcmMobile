import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_line.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';

/// Tela A — Manutenção em Detecção
/// Cão operacional: seleciona linha + tipo de cenário + foco
class DetectionMaintenanceScreen extends StatefulWidget {
  final Dog dog;

  const DetectionMaintenanceScreen({super.key, required this.dog});

  @override
  State<DetectionMaintenanceScreen> createState() =>
      _DetectionMaintenanceScreenState();
}

class _DetectionMaintenanceScreenState
    extends State<DetectionMaintenanceScreen> {
  final _focusController = TextEditingController();
  final _obsController = TextEditingController();

  static final _lines = DetectionLine.officialTypes
      .map(
        (type) => _DetectionLine(
          name: DetectionLine.displayNameForType(type),
          icon: DetectionLine.iconForType(type),
        ),
      )
      .toList(growable: false);

  // Cenários
  static const _scenarios = [
    'Caixas (reforço)',
    'Veículo',
    'Ambiente fechado',
    'Área aberta',
    'Bagagem',
  ];

  // Materiais de odor
  static const _materials = ['Nose-MP Drogas', 'Droga real', 'Scentlogix'];

  // Sugestões de foco
  static const _focusSuggestions = [
    'Discriminação',
    'Indicação passiva',
    'Veículo',
    'Rotina',
  ];

  // Ratings
  static const _ratings = ['Falhou', 'Regular', 'Bom', 'Ótimo'];

  int _selectedLineIndex = 0;
  String? _selectedScenario;
  String? _selectedMaterial;
  int? _selectedRating;

  @override
  void dispose() {
    _focusController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  String _getLineStatus(int index) {
    final specialties = widget.dog.specialties ?? [];
    final lineName = _lines[index].name.toLowerCase();
    for (final s in specialties) {
      if (s.toLowerCase().contains(lineName) ||
          s.toLowerCase().contains('detec')) {
        return 'operacional';
      }
    }
    if (index == 0) return 'operacional'; // Default: primeira linha ativa
    return 'não iniciada';
  }

  bool _isLineEnabled(int index) {
    return _getLineStatus(index) != 'não iniciada';
  }

  Future<void> _saveSession() async {
    if (_selectedRating == null) {
      AppFeedback.warning(context, 'Selecione o resultado da sessão');
      return;
    }

    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      date: DateTime.now(),
      trainingType: 'Detecção',
      substanceUsed: _lines[_selectedLineIndex].name,
      location: _selectedScenario ?? '',
      weather: '',
      handlerNotes: _obsController.text.trim(),
      metadata: {
        'specialty': 'deteccao',
        'mode': 'manutencao',
        'line': _lines[_selectedLineIndex].name,
        'scenario': _selectedScenario,
        'material': _selectedMaterial,
        'focus': _focusController.text.trim(),
        'rating': _ratings[_selectedRating!],
      },
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addTrainingSession(session);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      AppFeedback.success(context, 'Sessão de detecção salva!');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLineSelector(),
                    const SizedBox(height: 16),
                    _buildFocusCard(),
                    const SizedBox(height: 16),
                    _buildScenarioChips(),
                    const SizedBox(height: 16),
                    _buildMaterialChips(),
                    const SizedBox(height: 16),
                    _buildRatingRow(),
                    const SizedBox(height: 16),
                    _buildObservations(),
                    const SizedBox(height: 20),
                    _buildRecentSessions(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildCTA(),
    );
  }

  Widget _buildHeader() {
    final status = _getLineStatus(_selectedLineIndex);
    final isOp = status == 'operacional';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.success.withAlpha(40)),
        ),
      ),
      child: Column(
        children: [
          // Top row
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MANUTENÇÃO OPERACIONAL',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Detecção',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('👃', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Operational status card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withAlpha(50)),
            ),
            child: Column(
              children: [
                BinomioHeader(
                  dog: widget.dog,
                  subtitle: isOp
                      ? 'OPERACIONAL EM ${_lines[_selectedLineIndex].name.toUpperCase()}'
                      : 'EM FORMAÇÃO',
                  subtitleColor: isOp ? AppTheme.success : AppTheme.warning,
                  dogBorderColor: AppTheme.success,
                  conductorBorderColor: AppTheme.success,
                  showStatusDot: true,
                  statusDotColor: isOp ? AppTheme.success : AppTheme.warning,
                  avatarSize: 44,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOp ? 'FORMADO' : 'FORMAÇÃO',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Stats row
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppTheme.success.withAlpha(40)),
                    ),
                  ),
                  child: Consumer<TrainingViewModel>(
                    builder: (_, vm, _) {
                      final detSessions = vm.trainings
                          .where(
                            (t) =>
                                t.trainingType.toLowerCase().contains('detec'),
                          )
                          .toList();
                      final count = detSessions.length;
                      int? lastDays;
                      if (detSessions.isNotEmpty) {
                        detSessions.sort((a, b) => b.date.compareTo(a.date));
                        lastDays = DateTime.now()
                            .difference(detSessions.first.date)
                            .inDays;
                      }
                      return Row(
                        children: [
                          _statItem('SESSÕES', '$count'),
                          _statItem(
                            'ÚLTIMA',
                            lastDays != null ? '${lastDays}d' : '—',
                          ),
                          _statItem('CERTIFICADO', '🏅'),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('LINHA A TREINAR'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_lines.length, (i) {
            final enabled = _isLineEnabled(i);
            final selected = _selectedLineIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedLineIndex = i);
                      }
                    : null,
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.success.withAlpha(20)
                        : AppTheme.textPrimary.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppTheme.success
                          : enabled
                          ? AppTheme.textPrimary.withAlpha(20)
                          : AppTheme.textPrimary.withAlpha(10),
                      width: 1.5,
                    ),
                  ),
                  child: Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: Column(
                      children: [
                        Text(
                          _lines[i].icon,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lines[i].name,
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selected
                              ? '● OPERACIONAL'
                              : enabled
                              ? 'DISPONÍVEL'
                              : 'NÃO INICIADA',
                          style: GoogleFonts.inter(
                            color: selected
                                ? AppTheme.success
                                : AppTheme.textTertiary,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFocusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(20),
            AppTheme.success.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 FOCO DESTA SESSÃO',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _focusController,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'O que quer aprimorar?',
              hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
              filled: true,
              fillColor: AppTheme.background.withAlpha(65),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _focusSuggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  _focusController.text = s;
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withAlpha(65)),
                  ),
                  child: Text(
                    s,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('TIPO DE CENÁRIO'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _scenarios.map((s) {
            final selected = _selectedScenario == s;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedScenario = selected ? null : s);
              },
              child: _chip(s, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMaterialChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('MATERIAL DE ODOR'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _materials.map((m) {
            final selected = _selectedMaterial == m;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedMaterial = selected ? null : m);
              },
              child: _chip(m, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRatingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('RESULTADO DA SESSÃO'),
            const Spacer(),
            Text(
              'avaliação geral',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_ratings.length, (i) {
            final selected = _selectedRating == i;
            final isBad = i == 0;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedRating = i);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? (isBad
                              ? AppTheme.error.withAlpha(25)
                              : AppTheme.success.withAlpha(25))
                        : AppTheme.textPrimary.withAlpha(8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? (isBad ? AppTheme.error : AppTheme.success)
                          : AppTheme.textPrimary.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _ratings[i],
                      style: GoogleFonts.inter(
                        color: selected
                            ? (isBad ? AppTheme.error : AppTheme.success)
                            : AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildObservations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('OBSERVAÇÕES'),
            const Spacer(),
            Text(
              'opcional',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _obsController,
          maxLines: 3,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Notas sobre a sessão, comportamento, ajustes...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.primary.withAlpha(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSessions() {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, _) {
        final recent = vm.trainings
            .where((t) => t.trainingType.toLowerCase().contains('detec'))
            .take(3)
            .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MANUTENÇÕES RECENTES',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...recent.map((s) => _recentCard(s)),
          ],
        );
      },
    );
  }

  Widget _recentCard(TrainingSessionModel session) {
    final day =
        '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}';
    final rating = session.metadata?['rating'] ?? '';
    final scenario = session.metadata?['scenario'] ?? session.location;
    final focus = session.metadata?['focus'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              day,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  focus.isNotEmpty ? '$focus · $scenario' : scenario,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  session.substanceUsed ?? 'Detecção',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (rating.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rating.toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppTheme.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCTA() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.2, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '💾 SALVAR SESSÃO',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helpers ---

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _chip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.primary.withAlpha(30)
            : AppTheme.textPrimary.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppTheme.primary
              : AppTheme.textPrimary.withAlpha(25),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DetectionLine {
  final String name;
  final String icon;
  const _DetectionLine({required this.name, required this.icon});
}
