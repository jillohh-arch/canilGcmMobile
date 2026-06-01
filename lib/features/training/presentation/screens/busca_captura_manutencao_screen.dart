import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/gps_tracking_screen.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

class BuscaCapturaManutencaoScreen extends StatefulWidget {
  final Dog dog;

  const BuscaCapturaManutencaoScreen({super.key, required this.dog});

  @override
  State<BuscaCapturaManutencaoScreen> createState() =>
      _BuscaCapturaManutencaoScreenState();
}

class _BuscaCapturaManutencaoScreenState
    extends State<BuscaCapturaManutencaoScreen> {
  bool _useGpsTracker = true;
  String _figurante = 'Fig. Souza';
  String _odorObject = 'Camiseta';
  String _ambiente = 'Urbano';
  String _desempenho = 'Bom';
  final TextEditingController _notesController = TextEditingController();

  final List<String> _allReinforcedItems = [
    'Rastreamento',
    'Indicação passiva',
    'Indicação ativa',
    'Contenção',
    'Indicação em altura',
    'Indicação em veículo',
    'Cruzamento de pistas',
  ];
  final Set<String> _selectedReinforcedItems = {
    'Rastreamento',
    'Indicação passiva',
    'Contenção',
  };

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.background,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Page Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.success.withAlpha(
                            38,
                          ), // rgba(46, 204, 113, 0.15)
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.centerLeft,
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: AppTheme.textPrimary,
                                  size: 20,
                                ),
                              ),
                            ),
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
                                  const SizedBox(height: 2),
                                  Text(
                                    'Busca & Captura',
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
                                color: AppTheme.success.withAlpha(
                                  31,
                                ), // rgba(46, 204, 113, 0.12)
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '🎯',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Dog operational status box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withAlpha(
                              15,
                            ), // rgba(46, 204, 113, 0.06)
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.success.withAlpha(
                                51,
                              ), // rgba(46, 204, 113, 0.2)
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.success,
                                        width: 2.0,
                                      ),
                                      color: AppTheme.surfacePanelAlt,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      widget.dog.name.isNotEmpty
                                          ? widget.dog.name[0]
                                          : 'K',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${widget.dog.name} · Condutor',
                                          style: GoogleFonts.inter(
                                            color: AppTheme.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: AppTheme.success,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'OPERACIONAL HÁ 18 MESES',
                                              style: GoogleFonts.inter(
                                                color: AppTheme.success,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.success.withAlpha(38),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'FORMADO',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.only(top: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: AppTheme.success.withAlpha(38),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildOpStat('SESSÕES', '87'),
                                    _buildOpStat('ÚLTIMA', '7 dias'),
                                    _buildOpStat('DIST. TOTAL', '42 km'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scroll Area
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Maintenance alert
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                left: BorderSide(
                                  color: AppTheme.warning,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('⏰', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Recomendado treino semanal',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.warning,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Última manutenção há 7 dias. Mantenha a rotina para preservar o cão afiado.',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // GPS Tracker toggle
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(
                                13,
                              ), // rgba(77, 208, 225, 0.05)
                              border: Border.all(
                                color: AppTheme.primary.withAlpha(
                                  64,
                                ), // rgba(77, 208, 225, 0.25)
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withAlpha(38),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '📡',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Rastreador GPS',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Distância e trajeto registrados automaticamente',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.textTertiary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _useGpsTracker,
                                  onChanged: (val) {
                                    setState(() {
                                      _useGpsTracker = val;
                                    });
                                  },
                                  activeThumbColor: AppTheme.primary,
                                  activeTrackColor: AppTheme.primary.withAlpha(
                                    77,
                                  ),
                                  inactiveThumbColor: AppTheme.textMuted,
                                  inactiveTrackColor: AppTheme.textPrimary
                                      .withAlpha(26),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Section: Configuração Rápida
                          Text(
                            'CONFIGURAÇÃO RÁPIDA',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Config block
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.textPrimary.withAlpha(13),
                              border: Border.all(
                                color: AppTheme.textPrimary.withAlpha(20),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildConfigRow(
                                  icon: '👤',
                                  label: 'FIGURANTE',
                                  value: _figurante,
                                  onTap: () => _showOptionsSelector(
                                    'Figurante',
                                    [
                                      'Fig. Souza',
                                      'Fig. Oliveira',
                                      'Fig. Lima',
                                    ],
                                    (v) {
                                      setState(() => _figurante = v);
                                    },
                                  ),
                                ),
                                _buildConfigRow(
                                  icon: '🧥',
                                  label: 'OBJETO DE ODOR',
                                  value: _odorObject,
                                  onTap: () => _showOptionsSelector(
                                    'Objeto de odor',
                                    ['Camiseta', 'Meia', 'Chaveiro', 'Boné'],
                                    (v) {
                                      setState(() => _odorObject = v);
                                    },
                                  ),
                                ),
                                _buildConfigRow(
                                  icon: '🌆',
                                  label: 'AMBIENTE',
                                  value: _ambiente,
                                  onTap: () => _showOptionsSelector(
                                    'Ambiente',
                                    ['Urbano', 'Rural', 'Mata'],
                                    (v) {
                                      setState(() => _ambiente = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Section: O que foi reforçado
                          Text(
                            'O QUE FOI REFORÇADO',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Tags wrap
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _allReinforcedItems.map((item) {
                              final isSelected = _selectedReinforcedItems
                                  .contains(item);
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    if (isSelected) {
                                      _selectedReinforcedItems.remove(item);
                                    } else {
                                      _selectedReinforcedItems.add(item);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withAlpha(31)
                                        : AppTheme.textPrimary.withAlpha(13),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primary
                                          : AppTheme.textPrimary.withAlpha(20),
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected) ...[
                                        const Text(
                                          '✓ ',
                                          style: TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      Text(
                                        item,
                                        style: GoogleFonts.inter(
                                          color: isSelected
                                              ? AppTheme.primary
                                              : AppTheme.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Section: Desempenho da sessão
                          Text(
                            'DESEMPENHO DA SESSÃO',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Performance ratings row
                          Row(
                            children: ['Ruim', 'Regular', 'Bom', 'Ótimo'].map((
                              rating,
                            ) {
                              final isActive = _desempenho == rating;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      _desempenho = rating;
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppTheme.primary.withAlpha(31)
                                          : AppTheme.textPrimary.withAlpha(13),
                                      border: Border.all(
                                        color: isActive
                                            ? AppTheme.primary
                                            : AppTheme.textPrimary.withAlpha(
                                                20,
                                              ),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      rating,
                                      style: GoogleFonts.inter(
                                        color: isActive
                                            ? AppTheme.primary
                                            : AppTheme.textTertiary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Observations section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'OBSERVAÇÕES',
                                style: GoogleFonts.inter(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                'opcional',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _notesController,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText:
                                  'Notas sobre a sessão, comportamento, ajustes...',
                              hintStyle: GoogleFonts.inter(
                                color: AppTheme.textMuted,
                              ),
                              filled: true,
                              fillColor: AppTheme.primary.withAlpha(10),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppTheme.primary.withAlpha(51),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: AppTheme.primary),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Section: Sessões recentes
                          Text(
                            'SESSÕES RECENTES',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),

                          _buildRecentCard(
                            '03/05',
                            'Manutenção urbana',
                            'Rastreamento · Contenção · Bom',
                            '524m',
                            '18min',
                          ),
                          _buildRecentCard(
                            '26/04',
                            'Manutenção mata',
                            'Rastreamento · Indicação · Ótimo',
                            '1.2km',
                            '24min',
                          ),
                          _buildRecentCard(
                            '19/04',
                            'Manutenção rasteira',
                            'Indicação em altura · Bom',
                            '380m',
                            '14min',
                          ),

                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Ver todas as 87 sessões →',
                              style: GoogleFonts.inter(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom CTA Row
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppTheme.background,
                        AppTheme.background.withAlpha(0),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textTertiary,
                          side: BorderSide(
                            color: AppTheme.textPrimary.withAlpha(26),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 20,
                          ),
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
                            if (_useGpsTracker) {
                              final trackingService = GpsTrackingService();
                              final handlerId = _resolveHandlerId();
                              final result = await Navigator.of(context)
                                  .push<GpsTrackResult?>(
                                    MaterialPageRoute(
                                      builder: (_) => GpsTrackingScreen(
                                        activityLabel:
                                            'Busca & Captura · Manutenção',
                                        dogName: widget.dog.name,
                                        handlerName: handlerId,
                                        trackingService: trackingService,
                                      ),
                                    ),
                                  );
                              if (result != null && context.mounted) {
                                await _persistBcSession(result);
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sessão registrada com sucesso!',
                                  ),
                                ),
                              );
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _useGpsTracker
                                ? AppTheme.success
                                : AppTheme.primary,
                            foregroundColor: AppTheme.background,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            _useGpsTracker
                                ? '▶ INICIAR COM RASTREADOR'
                                : 'SALVAR REGISTRO',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpStat(String label, String value) {
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

  Widget _buildConfigRow({
    required String icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppTheme.textPrimary.withAlpha(10),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(
    String date,
    String title,
    String subtitle,
    String dist,
    String time,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(10)),
      ),
      child: Row(
        children: [
          Text(
            date,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '📏 $dist',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '⏱ $time',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOptionsSelector(
    String title,
    List<String> options,
    ValueChanged<String> onSelected,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary.withAlpha(61),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...options.map(
                (opt) => ListTile(
                  title: Text(
                    opt,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () {
                    onSelected(opt);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _resolveHandlerId() {
    try {
      final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
      return shiftVM.handlerId ?? 'Condutor';
    } catch (_) {
      return 'Condutor';
    }
  }

  Future<void> _persistBcSession(GpsTrackResult result) async {
    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      date: DateTime.now(),
      trainingType: 'Busca & Captura',
      location: '',
      weather: '',
      handlerNotes: '',
      metadata: {
        'specialty': 'busca_captura',
        'mode': 'manutencao',
        'ambiente': _ambiente,
        'figurante': _figurante,
        'odor_object': _odorObject,
        'gps': true,
        'gps_track': result.toJson(),
      },
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addTrainingSession(session);
    } catch (_) {
      // Silently fail — data is saved locally via GPS service
    }
  }
}
