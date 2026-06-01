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

class BuscaCapturaFormacaoScreen extends StatefulWidget {
  final Dog dog;

  const BuscaCapturaFormacaoScreen({super.key, required this.dog});

  @override
  State<BuscaCapturaFormacaoScreen> createState() =>
      _BuscaCapturaFormacaoScreenState();
}

class _BuscaCapturaFormacaoScreenState
    extends State<BuscaCapturaFormacaoScreen> {
  int _activeTabIndex = 0;

  final List<String> _tabs = [
    'Roadmap',
    'Módulo atual',
    'Histórico',
    'Estatísticas',
  ];

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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                                    'FORMAÇÃO',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.warning,
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
                                color: AppTheme.warning.withAlpha(
                                  31,
                                ), // rgba(241, 196, 15, 0.12)
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
                        // Formation Status / Binomio Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withAlpha(
                              15,
                            ), // rgba(241, 196, 15, 0.06)
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.warning.withAlpha(
                                51,
                              ), // rgba(241, 196, 15, 0.2)
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.warning,
                                    width: 1.5,
                                  ),
                                  color: AppTheme.surfacePanelAlt,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  widget.dog.name.isNotEmpty
                                      ? widget.dog.name[0]
                                      : 'K',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.warning,
                                    fontSize: 9,
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
                                      '${widget.dog.name} · Condutor',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          color: AppTheme.textSecondary,
                                          fontSize: 10,
                                        ),
                                        children: const [
                                          TextSpan(text: 'Em formação no '),
                                          TextSpan(
                                            text: 'Módulo 2',
                                            style: TextStyle(
                                              color: AppTheme.warning,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(text: ' · desde 12/03'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tabs Row
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.textPrimary.withAlpha(16),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_tabs.length, (index) {
                        final isActive = _activeTabIndex == index;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _activeTabIndex = index;
                            });
                          },
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isActive
                                      ? AppTheme.primary
                                      : AppTheme.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _tabs[index],
                              style: GoogleFonts.inter(
                                color: isActive
                                    ? AppTheme.primary
                                    : AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // Tab Content Area
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: [
                        _buildRoadmapTab(),
                        _buildModuloAtualTab(),
                        _buildHistoricoTab(),
                        _buildEstatisticasTab(),
                      ],
                    ),
                  ),
                ],
              ),

              // Fixed bottom CTA
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
                  child: ElevatedButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      final trackingService = GpsTrackingService();
                      String handlerId = 'Condutor';
                      try {
                        final shiftVM = Provider.of<ShiftViewModel>(
                          context,
                          listen: false,
                        );
                        handlerId = shiftVM.handlerId ?? 'Condutor';
                      } catch (_) {}
                      final result = await Navigator.of(context)
                          .push<GpsTrackResult?>(
                            MaterialPageRoute(
                              builder: (_) => GpsTrackingScreen(
                                activityLabel: 'Busca & Captura · Formação',
                                dogName: widget.dog.name,
                                handlerName: handlerId,
                                trackingService: trackingService,
                              ),
                            ),
                          );
                      if (result != null && context.mounted) {
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
                            'mode': 'formacao',
                            'gps': true,
                            'gps_track': result.toJson(),
                          },
                        );
                        try {
                          final vm = Provider.of<TrainingViewModel>(
                            context,
                            listen: false,
                          );
                          await vm.addTrainingSession(session);
                        } catch (_) {}
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'INICIAR SESSÃO DE TREINO',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ABA ROADMAP ---
  Widget _buildRoadmapTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // M1
        _buildModuleCard(
          number: '1',
          title: 'Pareamento de Odor',
          subtitle:
              'Associação primária entre o artigo de referência e a recompensa.',
          status: 'CONCLUÍDO',
          progress: 1.0,
          isCompleted: true,
          isActive: false,
          progressText: '10 marcos atingidos',
        ),
        // M2
        _buildModuleCard(
          number: '2',
          title: 'Indicações Estruturais',
          subtitle:
              'Persistência na indicação em fontes de odor com barreiras simples.',
          status: 'EM TREINO',
          progress: 0.7,
          isCompleted: false,
          isActive: true,
          progressText: '7/10 marcos · 14 sessões',
        ),
        // M3
        _buildModuleCard(
          number: '3',
          title: 'Operacional Urbano',
          subtitle:
              'Rastreamento em vias públicas com alto nível de distrações e ruídos.',
          status: 'BLOQUEADO',
          progress: 0.0,
          isCompleted: false,
          isActive: false,
          progressText: 'Requer Módulo 2 completo',
        ),
        // Final evaluation card
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.textPrimary.withAlpha(26),
              width: 1,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.assignment_turned_in_outlined,
                color: AppTheme.textMuted,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                'Avaliação de Aptidão Final',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Após concluir os 3 módulos, o binômio passará pelo teste final de certificação operacional.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard({
    required String number,
    required String title,
    required String subtitle,
    required String status,
    required double progress,
    required bool isCompleted,
    required bool isActive,
    required String progressText,
  }) {
    Color sideColor = AppTheme.textSoft.withAlpha(80);
    Color numBg = AppTheme.textPrimary.withAlpha(20);
    Color numText = AppTheme.textSoft;
    Color statusBg = AppTheme.textPrimary.withAlpha(20);

    if (isCompleted) {
      sideColor = AppTheme.success;
      numBg = AppTheme.success.withAlpha(38);
      numText = AppTheme.success;
      statusBg = AppTheme.success.withAlpha(31);
    } else if (isActive) {
      sideColor = AppTheme.warning;
      numBg = AppTheme.warning.withAlpha(38);
      numText = AppTheme.warning;
      statusBg = AppTheme.warning.withAlpha(31);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.warning.withAlpha(10)
            : AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: sideColor, width: 3),
          top: BorderSide(color: AppTheme.textPrimary.withAlpha(20), width: 1),
          right: BorderSide(
            color: AppTheme.textPrimary.withAlpha(20),
            width: 1,
          ),
          bottom: BorderSide(
            color: AppTheme.textPrimary.withAlpha(20),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: numBg,
                  border: Border.all(color: numText, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  number,
                  style: GoogleFonts.inter(
                    color: numText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.inter(
                    color: numText,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progressText,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (progress > 0 && progress < 1.0)
                Text(
                  '${(progress * 100).round()}%',
                  style: GoogleFonts.inter(
                    color: AppTheme.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (progress > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(16),
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted ? AppTheme.success : AppTheme.warning,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- ABA MÓDULO ATUAL ---
  Widget _buildModuloAtualTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // Detail Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warning.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warning.withAlpha(51), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.warning.withAlpha(38),
                      border: Border.all(color: AppTheme.warning, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '2',
                      style: GoogleFonts.inter(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Indicações Estruturais',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Consolidar indicações diretas e persistentes em fontes de odor variadas com barreiras simples.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.warning.withAlpha(38),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildDetailMetaItem('SESSÕES', '14'),
                    const SizedBox(width: 24),
                    _buildDetailMetaItem('ACERTOS', '82%'),
                    const SizedBox(width: 24),
                    _buildDetailMetaItem('FOCO', 'Persistência'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section Title: Marcos pedagógicos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MARCOS PEDAGÓGICOS',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Marcos list items
        _buildMarcoItem(
          title: 'Indicação sentada de 5s',
          subtitle: 'Manter a posição de indicação focada por 5 segundos.',
          isAtingido: true,
          sessionsCount: '14 sessões',
        ),
        _buildMarcoItem(
          title: 'Desprezar distrações leves',
          subtitle: 'Ignorar pequenos objetos ou ruídos próximos à fonte.',
          isAtingido: true,
          sessionsCount: '8 sessões',
        ),
        _buildMarcoItem(
          title: 'Persistência em fonte oculta',
          subtitle:
              'Indicação clara em fonte totalmente escondida sob entulho.',
          isAtingido: false,
          sessionsCount: '3 sessões',
        ),

        const SizedBox(height: 10),
        // Odor info banner
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
          ),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.5,
              ),
              children: const [
                TextSpan(text: 'Objeto de odor atual: '),
                TextSpan(
                  text: 'Artigo pessoal (camiseta/meia/chave)',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMarcoItem({
    required String title,
    required String subtitle,
    required bool isAtingido,
    required String sessionsCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAtingido
            ? AppTheme.success.withAlpha(15)
            : AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAtingido
              ? AppTheme.success.withAlpha(64)
              : AppTheme.textPrimary.withAlpha(20),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isAtingido
                    ? AppTheme.success
                    : AppTheme.textPrimary.withAlpha(51),
                width: 1.5,
              ),
              color: isAtingido ? AppTheme.success : AppTheme.transparent,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              color: isAtingido ? AppTheme.background : AppTheme.transparent,
              size: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sessionsCount,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ABA HISTÓRICO ---
  Widget _buildHistoricoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        _buildSessionCard(
          date: '23 Mai · 10:45',
          marco: 'Indicações Estruturais · Persistência',
          result: 'COMPLETA',
          distance: '150m',
          duration: '4m 12s',
          conductor: 'GCM Ragonha',
          resultClass: 'completa',
        ),
        _buildSessionCard(
          date: '18 Mai · 15:30',
          marco: 'Indicações Estruturais · Distrações',
          result: 'CHECAGEM',
          distance: '120m',
          duration: '5m 45s',
          conductor: 'GCM Ragonha',
          resultClass: 'checagem',
        ),
        _buildSessionCard(
          date: '12 Mai · 09:15',
          marco: 'Pareamento de Odor · Fonte Oculta',
          result: 'COMPLETA',
          distance: '80m',
          duration: '2m 10s',
          conductor: 'GCM Ragonha',
          resultClass: 'completa',
        ),
        _buildSessionCard(
          date: '05 Mai · 14:20',
          marco: 'Pareamento de Odor · Distrações',
          result: 'PERDA',
          distance: '100m',
          duration: '7m 30s',
          conductor: 'GCM Ragonha',
          resultClass: 'perda',
        ),
      ],
    );
  }

  Widget _buildSessionCard({
    required String date,
    required String marco,
    required String result,
    required String distance,
    required String duration,
    required String conductor,
    required String resultClass,
  }) {
    Color resultColor = AppTheme.success;
    Color resultBg = AppTheme.success.withAlpha(31);

    if (resultClass == 'checagem') {
      resultColor = AppTheme.warning;
      resultBg = AppTheme.warning.withAlpha(31);
    } else if (resultClass == 'perda') {
      resultColor = AppTheme.attention;
      resultBg = AppTheme.attention.withAlpha(31);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(20), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      marco,
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: resultBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result,
                  style: GoogleFonts.inter(
                    color: resultColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(13),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                _buildSessionStatItem(Icons.straighten_rounded, distance),
                const SizedBox(width: 16),
                _buildSessionStatItem(Icons.schedule_rounded, duration),
                const SizedBox(width: 16),
                _buildSessionStatItem(Icons.person_outline_rounded, conductor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStatItem(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 12),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  // --- ABA ESTATÍSTICAS ---
  Widget _buildEstatisticasTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // Big numbers cards
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimary.withAlpha(13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '116m',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DISTÂNCIA MÉDIA',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimary.withAlpha(13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '4.8 min',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TEMPO MÉDIO',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Chart block
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISTÂNCIA POR SESSÃO (ÚLTIMAS 7)',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              // Y-axis label
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '150m',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    '0m',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Simulated bars
              SizedBox(
                height: 100,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildChartBar(height: 40),
                    _buildChartBar(height: 60),
                    _buildChartBar(height: 50),
                    _buildChartBar(height: 80),
                    _buildChartBar(height: 70),
                    _buildChartBar(height: 90, highlight: true),
                    _buildChartBar(height: 100, highlight: true),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '05/Mai',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    'Hoje',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Distribution block
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISTRIBUIÇÃO DE RESULTADOS',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _buildDistributionRow('Completa', 0.75, '75%', AppTheme.success),
              const SizedBox(height: 8),
              _buildDistributionRow('Checagem', 0.15, '15%', AppTheme.warning),
              const SizedBox(height: 8),
              _buildDistributionRow('Perda', 0.10, '10%', AppTheme.attention),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartBar({required double height, bool highlight = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: highlight
                  ? [AppTheme.warning, AppTheme.warning.withAlpha(77)]
                  : [AppTheme.primary, AppTheme.primary.withAlpha(77)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionRow(
    String label,
    double percent,
    String percentText,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.textPrimary.withAlpha(13),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            percentText,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
