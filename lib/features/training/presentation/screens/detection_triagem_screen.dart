import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/dogs/data/dog_specialty_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog_specialty.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';

class DetectionTriagemScreen extends StatefulWidget {
  final Dog dog;

  const DetectionTriagemScreen({super.key, required this.dog});

  @override
  State<DetectionTriagemScreen> createState() => _DetectionTriagemScreenState();
}

class _DetectionTriagemScreenState extends State<DetectionTriagemScreen> {
  final _obsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final Map<String, double> _scores = {
    'drive': 5.0,
    'foco': 5.0,
    'persistencia': 5.0,
    'independencia': 5.0,
    'nervo': 5.0,
  };

  String _selectedDecision = 'Continuar Formação (F1)';
  bool _isSaving = false;

  final List<Map<String, dynamic>> _criteria = [
    {
      'key': 'drive',
      'label': 'Drive para bola',
      'description': 'Impulso de caça e obsessão pelo brinquedo/objeto de busca.',
    },
    {
      'key': 'foco',
      'label': 'Foco',
      'description': 'Capacidade de ignorar distrações externas e manter a atenção na tarefa.',
    },
    {
      'key': 'persistencia',
      'label': 'Persistência',
      'description': 'Insistência na busca do odor ou do brinquedo mesmo em situações difíceis.',
    },
    {
      'key': 'independencia',
      'label': 'Independência',
      'description': 'Autonomia e proatividade para investigar sem depender do condutor.',
    },
    {
      'key': 'nervo',
      'label': 'Nervo',
      'description': 'Estabilidade emocional frente a sons, superfícies estranhas e alturas.',
    },
  ];

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  int get _totalScore => _scores.values.fold(0, (total, val) => total + val.round());

  String get _recommendation {
    final total = _totalScore;
    if (total >= 35) return 'Apto';
    if (total >= 25) return 'Reavaliar';
    return 'Reprovado';
  }

  Color get _recommendationColor {
    final recomm = _recommendation;
    if (recomm == 'Apto') return AppTheme.success;
    if (recomm == 'Reavaliar') return AppTheme.warning;
    return AppTheme.error;
  }

  String get _recommendationDetails {
    final recomm = _recommendation;
    if (recomm == 'Apto') return 'Recomendado iniciar formação F1';
    if (recomm == 'Reavaliar') return 'Recomendada nova triagem em 30 dias';
    return 'Recomendado redirecionamento ou doação';
  }

  bool get _hasDivergence {
    final recomm = _recommendation;
    final decision = _selectedDecision;
    if (recomm == 'Apto' && decision != 'Continuar Formação (F1)') return true;
    if (recomm == 'Reavaliar' && decision != 'Reavaliar em 30 dias') return true;
    if (recomm == 'Reprovado' && decision != 'Sugerir redirecionamento/doação') return true;
    return false;
  }

  String _getScoreLevelLabel(double score) {
    if (score <= 2) return 'Baixo';
    if (score <= 5) return 'Regular';
    if (score <= 8) return 'Bom';
    return 'Excelente';
  }

  Color _getScoreLevelColor(double score) {
    if (score <= 2) return AppTheme.error;
    if (score <= 5) return AppTheme.warning;
    if (score <= 8) return AppTheme.primary;
    return AppTheme.success;
  }

  Future<void> _saveEvaluation() async {
    if (_isSaving) return;

    if (_hasDivergence && _obsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Observações/Justificativa obrigatória devido à divergência entre a recomendação automática e a decisão manual.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final authVM = Provider.of<AuthViewModel>(context, listen: false);
      final userVM = Provider.of<UserViewModel>(context, listen: false);
      final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);

      final currentRa = shiftVM.handlerId ?? HandlerIdentityService.raFromUser(authVM.user) ?? '';
      final handlerName = userVM.displayNameFor(
        ra: currentRa,
        firebaseUser: authVM.user,
        fallback: 'Condutor',
      );

      final evaluationData = {
        'date': Timestamp.now(),
        'dogId': widget.dog.id,
        'dogName': widget.dog.name,
        'scores': _scores.map((key, value) => MapEntry(key, value.round())),
        'totalScore': _totalScore,
        'calculatedRecommendation': _recommendation,
        'manualDecision': _selectedDecision,
        'divergence': _hasDivergence,
        'observations': _obsController.text.trim(),
        'handlerId': currentRa,
        'handlerName': handlerName,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 1. Write evaluation to /dogs/{dogId}/triagem_evaluations
      final evalRef = await FirebaseFirestore.instance
          .collection('dogs')
          .doc(widget.dog.id)
          .collection('triagem_evaluations')
          .add(evaluationData);

      // 2. Map manual decision to specialty status & phase
      String newStatus = 'not_started';
      String newPhase = 'Triagem';
      if (_selectedDecision == 'Continuar Formação (F1)') {
        newStatus = 'in_formation';
        newPhase = 'F1';
      } else if (_selectedDecision == 'Reavaliar em 30 dias') {
        newStatus = 'not_started';
        newPhase = 'Triagem (Reavaliação)';
      } else if (_selectedDecision == 'Sugerir redirecionamento/doação') {
        newStatus = 'inactive';
        newPhase = 'Redirecionado/Doação';
      }

      // 3. Update specialty in /dogs/{dogId}/specialties/deteccao
      final specialtyService = DogSpecialtyService();
      final existing = await specialtyService.getByType(widget.dog.id, 'deteccao');
      final updatedSpecialty = DogSpecialty(
        id: existing?.id,
        type: 'deteccao',
        status: newStatus,
        currentPhase: newPhase,
        startedAt: newStatus == 'in_formation' ? DateTime.now() : existing?.startedAt,
        operationalSince: existing?.operationalSince,
        notes: 'Triagem realizada em ${DateFormat('dd/MM/yyyy').format(DateTime.now())}. Decisão: $_selectedDecision. Pontuação: $_totalScore/50.',
      );

      if (existing != null) {
        await specialtyService.updateSpecialty(widget.dog.id, updatedSpecialty);
      } else {
        await specialtyService.addSpecialty(widget.dog.id, updatedSpecialty);
      }

      // 4. Log audit trails
      await AuditService.log(
        action: 'created',
        entityType: 'triagem_evaluation',
        entityId: evalRef.id,
        summary: 'Avaliação de triagem de detecção registrada para ${widget.dog.name}: $_totalScore/50 ($_selectedDecision)',
        after: evaluationData,
      );

      await AuditService.log(
        action: existing != null ? 'updated' : 'created',
        entityType: 'specialty',
        entityId: existing?.id ?? 'deteccao',
        summary: 'Especialidade Detecção para ${widget.dog.name} definida como $newStatus (Fase: $newPhase)',
        before: existing != null ? {'status': existing.status, 'currentPhase': existing.currentPhase} : null,
        after: {'status': newStatus, 'currentPhase': newPhase},
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Avaliação de triagem salva com sucesso!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao salvar avaliação: $e',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'TRIAGEM DE DETECÇÃO',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BinomioHeader(
                  dog: widget.dog,
                  subtitle: 'FASE 0 - AVALIAÇÃO DE APTIDÃO',
                  subtitleColor: AppTheme.primary,
                ),
                const SizedBox(height: 16),
                _buildWarningBanner(),
                const SizedBox(height: 20),
                Text(
                  'CRITÉRIOS DE AVALIAÇÃO (0 a 10)',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                ..._criteria.map((c) => _buildCriterionCard(c)),
                const SizedBox(height: 20),
                _buildResultPanel(),
                const SizedBox(height: 20),
                _buildDecisionPanel(),
                const SizedBox(height: 20),
                _buildObservationsField(),
                const SizedBox(height: 32),
                _buildSubmitButton(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instrução de Progressão (Fase 0)',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A triagem avalia os instintos basais do K9 antes do início do treinamento prático em substâncias. Cães reprovados serão redirecionados.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
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

  Widget _buildCriterionCard(Map<String, dynamic> c) {
    final key = c['key'] as String;
    final value = _scores[key]!;
    final level = _getScoreLevelLabel(value);
    final levelColor = _getScoreLevelColor(value);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                c['label'] as String,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${value.round()}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    '/10',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: levelColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: levelColor.withAlpha(60)),
                    ),
                    child: Text(
                      level.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: levelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c['description'] as String,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: AppTheme.outline,
              thumbColor: AppTheme.primary,
              overlayColor: AppTheme.primary.withAlpha(40),
              valueIndicatorColor: AppTheme.primary,
              valueIndicatorTextStyle: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 10,
              divisions: 10,
              label: '${value.round()}',
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() {
                  _scores[key] = val;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    final total = _totalScore;
    final recomm = _recommendation;
    final recommColor = _recommendationColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: recommColor.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: recommColor.withAlpha(40), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DESEMPENHO DO CÃO',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: recommColor,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: recommColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  recomm.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$total',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                ' /50 pontos',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _recommendationDetails,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionPanel() {
    final options = [
      {
        'value': 'Continuar Formação (F1)',
        'icon': Icons.trending_up_rounded,
        'color': AppTheme.success,
      },
      {
        'value': 'Reavaliar em 30 dias',
        'icon': Icons.timer_outlined,
        'color': AppTheme.warning,
      },
      {
        'value': 'Sugerir redirecionamento/doação',
        'icon': Icons.close_rounded,
        'color': AppTheme.error,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DECISÃO DA EQUIPE AVALIADORA',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: AppTheme.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...options.map((opt) {
          final isSelected = _selectedDecision == opt['value'];
          final color = opt['color'] as Color;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() {
                  _selectedDecision = opt['value'] as String;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? color.withAlpha(15) : Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : AppTheme.outline,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(opt['icon'] as IconData, color: color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        opt['value'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: color, size: 22)
                    else
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.outline, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildObservationsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'OBSERVAÇÕES',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: AppTheme.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            if (_hasDivergence) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.error.withAlpha(60)),
                ),
                child: Text(
                  'OBRIGATÓRIO (DIVERGÊNCIA)',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _obsController,
          maxLines: 4,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: _hasDivergence
                ? 'Justifique obrigatoriamente a escolha de decisão manual diferente da recomendação automática baseada na pontuação...'
                : 'Descreva observações adicionais sobre o K9 (comportamento sob pressão, reatividade a barulho, etc.)...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withAlpha(6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveEvaluation,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppTheme.outline,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 4,
        ),
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
            : Text(
                'REGISTRAR AVALIAÇÃO',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.6,
                ),
              ),
      ),
    );
  }
}
