import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_exam_process_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/exam_process.dart';
import 'package:canil_gcm/features/health/domain/exam_process_command.dart';
import 'package:canil_gcm/features/health/domain/exam_process_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

class ExamProcessFlowScreen extends StatefulWidget {
  const ExamProcessFlowScreen({
    super.key,
    required this.dogId,
    this.caseId,
    this.gateway,
  });

  final String dogId;
  final String? caseId;
  final ExamProcessGateway? gateway;

  @override
  State<ExamProcessFlowScreen> createState() => _ExamProcessFlowScreenState();
}

class _ExamProcessFlowScreenState extends State<ExamProcessFlowScreen> {
  static const _uuid = Uuid();
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  late final ExamProcessGateway _gateway;
  late String _dogId;

  List<ClinicalCaseOption> _cases = const [];
  String? _selectedCaseId;
  bool _loadingCases = true;
  String? _caseLoadError;

  List<ExamProcess> _exams = const [];
  bool _loadingExams = false;
  String? _examLoadError;

  bool _isActionSubmitting = false;

  @override
  void initState() {
    super.initState();
    _dogId = widget.dogId;
    _selectedCaseId = widget.caseId;
    _gateway = widget.gateway ?? FirebaseFunctionsExamProcessGateway();
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loadingCases = true;
      _caseLoadError = null;
    });

    try {
      final cases = await _gateway.loadUsableCases(_dogId);
      if (!mounted) return;

      setState(() {
        _cases = cases;
        _loadingCases = false;
        if (_selectedCaseId == null ||
            !cases.any((c) => c.caseId == _selectedCaseId)) {
          if (cases.isNotEmpty) {
            _selectedCaseId = cases.first.caseId;
          } else {
            _selectedCaseId = null;
          }
        }
      });

      if (_selectedCaseId != null) {
        await _loadExams(_selectedCaseId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCases = false;
        _caseLoadError = 'Erro ao carregar casos clínicos: $e';
      });
    }
  }

  Future<void> _loadExams(String caseId) async {
    setState(() {
      _loadingExams = true;
      _examLoadError = null;
    });

    try {
      final exams = await _gateway.loadCaseExams(
        dogId: _dogId,
        caseId: caseId,
      );
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _loadingExams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingExams = false;
        _examLoadError = 'Erro ao carregar exames: $e';
      });
    }
  }

  void _onCaseChanged(String? newCaseId) {
    if (newCaseId == null || newCaseId == _selectedCaseId) return;
    setState(() {
      _selectedCaseId = newCaseId;
      _exams = const [];
    });
    _loadExams(newCaseId);
  }

  String _formatExamType(ExamType type) {
    return switch (type) {
      ExamType.bloodWork => 'Hemograma / Sangue',
      ExamType.imaging => 'Imagem (Raio-X / Ultrassom)',
      ExamType.biopsy => 'Biópsia / Citologia',
      ExamType.culture => 'Cultura / Antibiograma',
      ExamType.parasitology => 'Parasitológico',
      ExamType.urinalysis => 'Urinálise',
      ExamType.cardiology => 'Cardiologia',
      ExamType.dermatology => 'Dermatologia',
      ExamType.ophthalmology => 'Oftalmologia',
      ExamType.other => 'Outro Exame',
    };
  }

  String _formatUrgency(ExamUrgency urgency) {
    return switch (urgency) {
      ExamUrgency.routine => 'Rotina',
      ExamUrgency.urgent => 'Urgente',
      ExamUrgency.stat => 'Emergência',
    };
  }

  String _formatStage(ExamStage stage) {
    return switch (stage) {
      ExamStage.requested => 'Solicitado',
      ExamStage.collected => 'Coletado',
      ExamStage.resulted => 'Resultado Emitido',
      ExamStage.interpreted => 'Interpretado',
      ExamStage.impactAssessed => 'Impacto Avaliado',
      ExamStage.cancelled => 'Cancelado',
    };
  }

  Color _stageColor(ExamStage stage) {
    return switch (stage) {
      ExamStage.requested => AppTheme.info,
      ExamStage.collected => AppTheme.warning,
      ExamStage.resulted => AppTheme.attention,
      ExamStage.interpreted => AppTheme.healthAccent,
      ExamStage.impactAssessed => AppTheme.success,
      ExamStage.cancelled => AppTheme.error,
    };
  }

  // --- ACTIONS MODALS ---

  Future<void> _openRequestExamDialog() async {
    if (_selectedCaseId == null) {
      AppFeedback.error(context, 'Selecione um caso clínico primeiro.');
      return;
    }

    final titleController = TextEditingController();
    final reasonController = TextEditingController();
    final labController = TextEditingController();
    var selectedType = ExamType.bloodWork;
    var selectedUrgency = ExamUrgency.routine;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.biotech_rounded,
                          color: AppTheme.healthAccent,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Solicitar Exame Clínico',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Título do Exame *',
                        hintText: 'Ex: Hemograma Completo com Plaquetas',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ExamType>(
                      initialValue: selectedType,
                      dropdownColor: AppTheme.surfacePanel,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Exame',
                        border: OutlineInputBorder(),
                      ),
                      items: ExamType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(_formatExamType(t)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ExamUrgency>(
                      initialValue: selectedUrgency,
                      dropdownColor: AppTheme.surfacePanel,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Urgência',
                        border: OutlineInputBorder(),
                      ),
                      items: ExamUrgency.values.map((u) {
                        return DropdownMenuItem(
                          value: u,
                          child: Text(_formatUrgency(u)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedUrgency = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Justificativa Clínica / Motivo',
                        hintText: 'Descreva a indicação clínica do exame',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labController,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Laboratório Previsto (opcional)',
                        hintText: 'Ex: Laboratório Veterinário Central',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.healthAccent,
                          foregroundColor: AppTheme.background,
                        ),
                        onPressed: () {
                          if (titleController.text.trim().isEmpty) {
                            AppFeedback.error(
                              sheetContext,
                              'Informe o título do exame.',
                            );
                            return;
                          }
                          Navigator.pop(sheetContext, true);
                        },
                        child: Text(
                          'Confirmar Solicitação',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final cmd = RequestExamCommand(
        dogId: _dogId,
        caseId: _selectedCaseId!,
        title: titleController.text.trim(),
        examType: selectedType,
        urgency: selectedUrgency,
        requestReason: reasonController.text.trim().isNotEmpty
            ? reasonController.text.trim()
            : null,
        labName: labController.text.trim().isNotEmpty
            ? labController.text.trim()
            : null,
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.requestExam(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Exame solicitado com sucesso!');
        await _loadExams(_selectedCaseId!);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  Future<void> _openRecordCollectionDialog(ExamProcess exam) async {
    final siteController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar Coleta de Material',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.healthAccent,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: siteController,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Local da Coleta / Amostra',
                    hintText: 'Ex: Veia cefálica direita, pavilhão auricular',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Observações da Coleta',
                    hintText: 'Acondicionamento em tubo EDTA, sem intercorrências',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warning,
                      foregroundColor: AppTheme.background,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Confirmar Coleta Realizada',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final cmd = RecordExamCollectionCommand(
        dogId: _dogId,
        caseId: exam.caseId,
        examId: exam.id,
        collectedAt: DateTime.now(),
        collectionSite: siteController.text.trim().isNotEmpty
            ? siteController.text.trim()
            : null,
        collectionNotes: notesController.text.trim().isNotEmpty
            ? notesController.text.trim()
            : null,
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.recordCollection(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Coleta registrada com sucesso!');
        await _loadExams(exam.caseId);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  Future<void> _openRecordResultDialog(ExamProcess exam) async {
    final summaryController = TextEditingController();
    final labController = TextEditingController(text: exam.labName ?? '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar Resultado Técnico',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.healthAccent,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: summaryController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Resumo dos Resultados / Laudo Técnico *',
                    hintText:
                        'Descreva os achados numéricos ou qualitativos do laudo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labController,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Laboratório Executante',
                    hintText: 'Ex: VetLab Diagnósticos',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.attention,
                      foregroundColor: AppTheme.background,
                    ),
                    onPressed: () {
                      if (summaryController.text.trim().isEmpty) {
                        AppFeedback.error(ctx, 'Informe o resumo do resultado.');
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: Text(
                      'Salvar Resultado do Laudo',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final cmd = RecordExamResultCommand(
        dogId: _dogId,
        caseId: exam.caseId,
        examId: exam.id,
        resultedAt: DateTime.now(),
        resultSummary: summaryController.text.trim(),
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.recordResult(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Resultado técnico registrado!');
        await _loadExams(exam.caseId);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  Future<void> _openRecordInterpretationDialog(ExamProcess exam) async {
    final textController = TextEditingController();
    final vetNameController = TextEditingController(text: 'Médico Veterinário');
    final crmvController = TextEditingController();
    final clinicController = TextEditingController(text: 'Canil Setorial GCM');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Interpretação Clínica Veterinária',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.healthAccent,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Parecer Clínico / Diagnóstico Conclusivo *',
                    hintText:
                        'Interprete o resultado no contexto clínico do animal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vetNameController,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Nome do Veterinário *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: crmvController,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Número de Registro (CRMV) *',
                    hintText: 'Ex: 12345-SP',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clinicController,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Clínica / Órgão *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.healthAccent,
                      foregroundColor: AppTheme.background,
                    ),
                    onPressed: () {
                      if (textController.text.trim().isEmpty ||
                          vetNameController.text.trim().isEmpty ||
                          crmvController.text.trim().isEmpty ||
                          clinicController.text.trim().isEmpty) {
                        AppFeedback.error(
                          ctx,
                          'Preencha todos os campos obrigatórios do parecer.',
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: Text(
                      'Homologar Parecer Clínico',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final professional = ProfessionalIdentity(
        name: vetNameController.text.trim(),
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: crmvController.text.trim(),
        clinic: clinicController.text.trim(),
      );

      final cmd = RecordExamInterpretationCommand(
        dogId: _dogId,
        caseId: exam.caseId,
        examId: exam.id,
        interpretedAt: DateTime.now(),
        interpretationText: textController.text.trim(),
        professional: professional,
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.recordInterpretation(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Interpretação veterinária homologada!');
        await _loadExams(exam.caseId);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  Future<void> _openAssessImpactDialog(ExamProcess exam) async {
    var selectedLevel = OperationalImpactLevel.none;
    final descController = TextEditingController();
    final restrictionsController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avaliar Impacto Operacional',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      exam.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.healthAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<OperationalImpactLevel>(
                      initialValue: selectedLevel,
                      dropdownColor: AppTheme.surfacePanel,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Nível de Impacto no Serviço',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: OperationalImpactLevel.none,
                          child: Text('Nenhum (Apto para serviço integral)'),
                        ),
                        DropdownMenuItem(
                          value: OperationalImpactLevel.low,
                          child: Text('Baixo (Observação / Carga leve)'),
                        ),
                        DropdownMenuItem(
                          value: OperationalImpactLevel.medium,
                          child: Text('Médio (Restrição parcial)'),
                        ),
                        DropdownMenuItem(
                          value: OperationalImpactLevel.high,
                          child: Text('Alto (Afastamento temporário)'),
                        ),
                        DropdownMenuItem(
                          value: OperationalImpactLevel.critical,
                          child: Text('Crítico (Baixa médica / Internação)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedLevel = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Descrição do Impacto Operacional *',
                        hintText:
                            'Ex: Cão sem alterações patológicas, liberado para policiamento.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (selectedLevel != OperationalImpactLevel.none) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: restrictionsController,
                        style: GoogleFonts.inter(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Restrições Aplicadas (separadas por vírgula)',
                          hintText: 'Ex: Sem salto de obstáculos, máximo 4h turno',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: AppTheme.background,
                        ),
                        onPressed: () {
                          if (descController.text.trim().isEmpty) {
                            AppFeedback.error(
                              sheetCtx,
                              'Informe a descrição do impacto.',
                            );
                            return;
                          }
                          Navigator.pop(sheetCtx, true);
                        },
                        child: Text(
                          'Concluir Ciclo do Exame',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final restrictions = selectedLevel == OperationalImpactLevel.none
          ? <String>[]
          : restrictionsController.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      final impact = OperationalImpact(
        level: selectedLevel,
        description: descController.text.trim(),
        restrictionsIssued: restrictions,
      );

      final cmd = AssessExamImpactCommand(
        dogId: _dogId,
        caseId: exam.caseId,
        examId: exam.id,
        impactAssessedAt: DateTime.now(),
        operationalImpact: impact,
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.assessImpact(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Impacto operacional registrado! Ciclo concluído.');
        await _loadExams(exam.caseId);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  Future<void> _openCancelDialog(ExamProcess exam) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfacePanel,
          title: Text(
            'Cancelar Solicitação de Exame',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deseja cancelar o exame "${exam.title}"?',
                style: GoogleFonts.inter(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: GoogleFonts.inter(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Motivo do Cancelamento *',
                  hintText: 'Ex: Coleta inviável, cão encaminhado para cirurgia',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  AppFeedback.error(ctx, 'Informe o motivo do cancelamento.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirmar Cancelamento'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final cmd = CancelExamCommand(
        dogId: _dogId,
        caseId: exam.caseId,
        examId: exam.id,
        cancelReason: reasonController.text.trim(),
        operationId: _uuid.v4(),
      );

      setState(() => _isActionSubmitting = true);
      final res = await _gateway.cancelExam(cmd);
      if (!mounted) return;
      setState(() => _isActionSubmitting = false);

      if (res is ExamProcessSuccess) {
        AppFeedback.success(context, 'Exame cancelado.');
        await _loadExams(exam.caseId);
      } else if (res is ExamProcessFailure) {
        AppFeedback.error(context, res.message);
      }
    }
  }

  // --- UI BUILDING ---

  Widget _buildCaseSelector() {
    if (_loadingCases) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_caseLoadError != null) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.error.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _caseLoadError!,
                style: GoogleFonts.inter(color: AppTheme.error),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCases,
            ),
          ],
        ),
      );
    }

    if (_cases.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.warning.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withAlpha(80)),
        ),
        child: Column(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.warning, size: 36),
            const SizedBox(height: 8),
            Text(
              'Nenhum caso clínico ativo encontrado',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Exames laboratoriais e complementares devem ser associados a um caso clínico em andamento. Inicie uma Consulta Veterinária para abrir um caso.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surfacePanel,
        border: Border(
          bottom: BorderSide(color: AppTheme.primaryDivider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Caso Clínico Vinculado:',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedCaseId),
            initialValue: _selectedCaseId,
            dropdownColor: AppTheme.surfacePanel,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: _cases.map((c) {
              return DropdownMenuItem(
                value: c.caseId,
                child: Text(
                  '${c.title} (${c.statusWireName})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _onCaseChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildStageProgress(ExamStage currentStage) {
    final stages = [
      ExamStage.requested,
      ExamStage.collected,
      ExamStage.resulted,
      ExamStage.interpreted,
      ExamStage.impactAssessed,
    ];

    if (currentStage == ExamStage.cancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.error.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'CANCELADO',
          style: GoogleFonts.inter(
            color: AppTheme.error,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    }

    final currentIndex = stages.indexOf(currentStage);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(stages.length, (idx) {
          final isPast = idx < currentIndex;
          final isCurrent = idx == currentIndex;
          final color = isCurrent
              ? AppTheme.healthAccent
              : (isPast ? AppTheme.success : AppTheme.textSecondary.withAlpha(90));

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(isCurrent ? 40 : 20),
                  borderRadius: BorderRadius.circular(6),
                  border: isCurrent ? Border.all(color: color, width: 1.5) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPast)
                      const Icon(Icons.check, size: 14, color: AppTheme.success)
                    else
                      Icon(
                        isCurrent
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 14,
                        color: color,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _formatStage(stages[idx]),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (idx < stages.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: AppTheme.textSecondary.withAlpha(80),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildExamCard(ExamProcess exam) {
    final color = _stageColor(exam.stage);

    return Card(
      color: AppTheme.surfacePanel,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.biotech_rounded, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatExamType(exam.examType)} · ${_formatUrgency(exam.urgency)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
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
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withAlpha(100)),
                  ),
                  child: Text(
                    _formatStage(exam.stage),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildStageProgress(exam.stage),
            const SizedBox(height: 14),
            const Divider(color: AppTheme.primaryDivider),
            const SizedBox(height: 8),
            // Clinical details per completed stages
            if (exam.requestedAt != null)
              _buildDetailRow(
                'Solicitado em:',
                _dateFormat.format(exam.requestedAt!),
              ),
            if (exam.requestReason != null)
              _buildDetailRow('Motivo:', exam.requestReason!),
            if (exam.collectedAt != null)
              _buildDetailRow(
                'Coleta realizada em:',
                _dateFormat.format(exam.collectedAt!),
              ),
            if (exam.collectionSite != null)
              _buildDetailRow('Local da amostra:', exam.collectionSite!),
            if (exam.resultedAt != null)
              _buildDetailRow(
                'Resultado técnico em:',
                _dateFormat.format(exam.resultedAt!),
              ),
            if (exam.resultSummary != null)
              _buildDetailRow('Laudo técnico:', exam.resultSummary!),
            if (exam.interpretedAt != null)
              _buildDetailRow(
                'Interpretação clínica em:',
                _dateFormat.format(exam.interpretedAt!),
              ),
            if (exam.interpretationText != null)
              _buildDetailRow(
                'Parecer veterinário:',
                exam.interpretationText!,
              ),
            if (exam.interpretationProfessional != null)
              _buildDetailRow(
                'Veterinário responsável:',
                '${exam.interpretationProfessional!.name} (${exam.interpretationProfessional!.registrationNumber})',
              ),
            if (exam.impactAssessedAt != null && exam.operationalImpact != null)
              _buildDetailRow(
                'Impacto operacional:',
                exam.operationalImpact!.description,
              ),
            if (exam.cancelledAt != null) ...[
              _buildDetailRow(
                'Cancelado em:',
                _dateFormat.format(exam.cancelledAt!),
              ),
              _buildDetailRow('Motivo do cancelamento:', exam.cancelReason ?? '-'),
            ],
            const SizedBox(height: 12),
            // Stage Action Buttons
            _buildStageActions(exam),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageActions(ExamProcess exam) {
    if (_isActionSubmitting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return switch (exam.stage) {
      ExamStage.requested => Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warning,
                  foregroundColor: AppTheme.background,
                ),
                icon: const Icon(Icons.colorize_rounded, size: 18),
                label: const Text('Registrar Coleta'),
                onPressed: () => _openRecordCollectionDialog(exam),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
              child: const Text('Cancelar'),
              onPressed: () => _openCancelDialog(exam),
            ),
          ],
        ),
      ExamStage.collected => Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.attention,
                  foregroundColor: AppTheme.background,
                ),
                icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
                label: const Text('Registrar Resultado'),
                onPressed: () => _openRecordResultDialog(exam),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
              child: const Text('Cancelar'),
              onPressed: () => _openCancelDialog(exam),
            ),
          ],
        ),
      ExamStage.resulted => SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.healthAccent,
              foregroundColor: AppTheme.background,
            ),
            icon: const Icon(Icons.rate_review_rounded, size: 18),
            label: const Text('Registrar Interpretação Veterinária'),
            onPressed: () => _openRecordInterpretationDialog(exam),
          ),
        ),
      ExamStage.interpreted => SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: AppTheme.background,
            ),
            icon: const Icon(Icons.verified_rounded, size: 18),
            label: const Text('Avaliar Impacto Operacional'),
            onPressed: () => _openAssessImpactDialog(exam),
          ),
        ),
      ExamStage.impactAssessed => Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 18),
              const SizedBox(width: 6),
              Text(
                'Ciclo do exame totalmente concluído',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
        ),
      ExamStage.cancelled => Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.error.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_rounded, color: AppTheme.error, size: 18),
              const SizedBox(width: 6),
              Text(
                'Exame cancelado e encerrado',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
        ),
    };
  }

  Widget _buildExamsList() {
    if (_loadingExams) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_examLoadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 36),
              const SizedBox(height: 8),
              Text(
                _examLoadError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.error),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
                onPressed: () {
                  if (_selectedCaseId != null) {
                    _loadExams(_selectedCaseId!);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (_exams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.biotech_outlined,
                size: 48,
                color: AppTheme.textSecondary.withAlpha(120),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhum exame solicitado para este caso',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Toque no botão abaixo para solicitar um novo exame complementar.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        return _buildExamCard(_exams[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Exames Clínicos',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (_selectedCaseId != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar',
              onPressed: () => _loadExams(_selectedCaseId!),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildCaseSelector(),
          Expanded(child: _buildExamsList()),
        ],
      ),
      floatingActionButton: _selectedCaseId != null
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.healthAccent,
              foregroundColor: AppTheme.background,
              icon: const Icon(Icons.add),
              label: Text(
                'Novo Exame',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              onPressed: _openRequestExamDialog,
            )
          : null,
    );
  }
}
