import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_treatment_protocol_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_command.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_gateway.dart';

class TreatmentExecutionScreen extends StatefulWidget {
  const TreatmentExecutionScreen({
    super.key,
    required this.dogId,
    this.caseId,
    this.gateway,
  });

  final String dogId;
  final String? caseId;
  final TreatmentProtocolGateway? gateway;

  @override
  State<TreatmentExecutionScreen> createState() =>
      _TreatmentExecutionScreenState();
}

class _TreatmentExecutionScreenState extends State<TreatmentExecutionScreen> {
  static const _uuid = Uuid();
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _dateOnlyFormat = DateFormat('dd/MM/yyyy');

  late final TreatmentProtocolGateway _gateway;
  late String _dogId;

  List<ClinicalCaseOption> _cases = const [];
  String? _selectedCaseId;
  bool _loadingCases = true;
  String? _caseLoadError;

  List<TreatmentProtocol> _protocols = const [];
  bool _loadingProtocols = false;
  String? _protocolLoadError;
  StreamSubscription<List<TreatmentProtocol>>? _protocolsSubscription;

  final Map<String, List<Map<String, dynamic>>> _protocolSchedules = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _scheduleSubscriptions = {};

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _dogId = widget.dogId;
    _selectedCaseId = widget.caseId;
    _gateway = widget.gateway ?? FirebaseFunctionsTreatmentProtocolGateway();
    _loadCases();
  }

  @override
  void dispose() {
    _protocolsSubscription?.cancel();
    for (final sub in _scheduleSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
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

      _subscribeProtocols();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCases = false;
        _caseLoadError = 'Erro ao carregar casos clínicos: $e';
      });
    }
  }

  void _subscribeProtocols() {
    _protocolsSubscription?.cancel();
    for (final sub in _scheduleSubscriptions.values) {
      sub.cancel();
    }
    _scheduleSubscriptions.clear();
    _protocolSchedules.clear();

    setState(() {
      _loadingProtocols = true;
      _protocolLoadError = null;
    });

    _protocolsSubscription = _gateway
        .watchProtocols(dogId: _dogId, caseId: _selectedCaseId)
        .listen(
      (protocols) {
        if (!mounted) return;
        setState(() {
          _protocols = protocols;
          _loadingProtocols = false;
        });

        for (final p in protocols) {
          if (!_scheduleSubscriptions.containsKey(p.id)) {
            _scheduleSubscriptions[p.id] = _gateway
                .watchProtocolSchedules(dogId: _dogId, protocolId: p.id)
                .listen((scheds) {
              if (!mounted) return;
              setState(() {
                _protocolSchedules[p.id] = scheds;
              });
            });
          }
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _loadingProtocols = false;
          _protocolLoadError = 'Erro ao carregar tratamentos: $err';
        });
      },
    );
  }

  Map<String, dynamic>? _findNextPlannedDose(TreatmentProtocol protocol) {
    final schedules = _protocolSchedules[protocol.id];
    if (schedules == null || schedules.isEmpty) return null;

    final openSchedules = schedules
        .where((s) =>
            s['lifecycle_status'] == 'open' || s['status'] == 'open')
        .toList();

    if (openSchedules.isEmpty) return null;

    openSchedules.sort((a, b) {
      final aDate = _parseScheduleDate(a['scheduled_for']);
      final bDate = _parseScheduleDate(b['scheduled_for']);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    return openSchedules.first;
  }

  DateTime? _parseScheduleDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    try {
      final dynamic dyn = raw;
      final toDate = dyn.toDate;
      if (toDate is Function) return toDate() as DateTime;
    } catch (_) {}
    return null;
  }

  String _formatRoute(DoseRoute route) {
    switch (route) {
      case DoseRoute.oral:
        return 'Via Oral';
      case DoseRoute.topical:
        return 'Tópica';
      case DoseRoute.injectableSubcutaneous:
        return 'Injetável (SC)';
      case DoseRoute.injectableIntramuscular:
        return 'Injetável (IM)';
      case DoseRoute.injectableIntravenous:
        return 'Injetável (IV)';
      case DoseRoute.inhalation:
        return 'Inalação';
      case DoseRoute.ophthalmic:
        return 'Oftálmica';
      case DoseRoute.otic:
        return 'Otológica';
      case DoseRoute.nasal:
        return 'Nasal';
    }
  }

  String _formatStatus(TreatmentStatus status) {
    switch (status) {
      case TreatmentStatus.active:
        return 'Ativo';
      case TreatmentStatus.paused:
        return 'Pausado';
      case TreatmentStatus.completed:
        return 'Concluído';
      case TreatmentStatus.cancelled:
        return 'Cancelado';
    }
  }

  Color _statusColor(TreatmentStatus status) {
    switch (status) {
      case TreatmentStatus.active:
        return AppTheme.success;
      case TreatmentStatus.paused:
        return AppTheme.warning;
      case TreatmentStatus.completed:
        return AppTheme.info;
      case TreatmentStatus.cancelled:
        return AppTheme.error;
    }
  }

  Future<void> _handleAdministerDose(
    TreatmentProtocol protocol,
    Map<String, dynamic> scheduleItem,
  ) async {
    final plannedDoseId =
        scheduleItem['planned_dose_id'] as String? ?? 'dose_1';
    final scheduleItemId = scheduleItem['schedule_id'] as String?;
    final obsController = TextEditingController();
    final sideEffectsController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirmar Administração de Dose',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfacePanelSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      protocol.medicationName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dose: ${protocol.dose.value} ${protocol.dose.unit.wireName} (${_formatRoute(protocol.dose.route)})',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: obsController,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sideEffectsController,
                decoration: const InputDecoration(
                  labelText: 'Efeitos colaterais observados (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Confirmar Administração',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final command = AdministerDoseCommand(
        dogId: _dogId,
        protocolId: protocol.id,
        plannedDoseId: plannedDoseId,
        scheduleItemId: scheduleItemId,
        administeredAt: DateTime.now(),
        observations: obsController.text.trim().isNotEmpty
            ? obsController.text.trim()
            : null,
        sideEffects: sideEffectsController.text.trim().isNotEmpty
            ? sideEffectsController.text.trim()
            : null,
        operationId: _uuid.v4(),
      );

      final result = await _gateway.administerDose(command);
      if (!mounted) return;

      if (result is DoseAdministrationSuccess) {
        AppFeedback.success(context, 'Dose administrada com sucesso!');
      } else if (result is TreatmentProtocolFailure) {
        AppFeedback.error(
            context, 'Falha ao registrar dose: ${result.message}');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Erro inesperado: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleSkipDose(
    TreatmentProtocol protocol,
    Map<String, dynamic> scheduleItem,
  ) async {
    final plannedDoseId =
        scheduleItem['planned_dose_id'] as String? ?? 'dose_1';
    final scheduleItemId = scheduleItem['schedule_id'] as String?;
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pular Dose de Tratamento',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Informe a justificativa clínica/operacional para pular a dose de ${protocol.medicationName}.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo obrigatório *',
                    hintText: 'Ex: Cão apresentou êmese, orientação veterinária',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'O motivo é obrigatório para registrar dose pulada.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: Text(
                    'Confirmar Dose Pulada',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final command = SkipDoseCommand(
        dogId: _dogId,
        protocolId: protocol.id,
        plannedDoseId: plannedDoseId,
        scheduleItemId: scheduleItemId,
        skipReason: reasonController.text.trim(),
        operationId: _uuid.v4(),
      );

      final result = await _gateway.skipDose(command);
      if (!mounted) return;

      if (result is DoseAdministrationSuccess) {
        AppFeedback.success(context, 'Registro de dose pulada concluído.');
      } else if (result is TreatmentProtocolFailure) {
        AppFeedback.error(context, 'Falha ao pular dose: ${result.message}');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Erro inesperado: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tratamentos e Medicamentos',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.outline, height: 1),
        ),
      ),
      backgroundColor: AppTheme.background,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingCases) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_caseLoadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.error, size: 48),
              const SizedBox(height: 12),
              Text(
                _caseLoadError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadCases,
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_cases.isNotEmpty) _buildCaseSelector(),
        Expanded(
          child: _loadingProtocols
              ? const Center(child: CircularProgressIndicator())
              : _protocolLoadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _protocolLoadError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: AppTheme.error),
                        ),
                      ),
                    )
                  : _protocols.isEmpty
                      ? _buildEmptyState()
                      : _buildProtocolsList(),
        ),
      ],
    );
  }

  Widget _buildCaseSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: DropdownButtonFormField<String?>(
        initialValue: _selectedCaseId,
        decoration: InputDecoration(
          labelText: 'Caso Clínico Vinculado',
          labelStyle: GoogleFonts.inter(fontSize: 13),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Todos os casos clínicos'),
          ),
          ..._cases.map((c) {
            return DropdownMenuItem<String?>(
              value: c.caseId,
              child: Text(
                '${c.title} (${c.statusWireName})',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
        onChanged: (val) {
          setState(() {
            _selectedCaseId = val;
          });
          _subscribeProtocols();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medication_outlined,
                size: 64, color: AppTheme.textSoft),
            const SizedBox(height: 16),
            Text(
              'Nenhum tratamento em andamento',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Novos protocolos de tratamento são prescritos e registrados via Web (Front 30). Quando disponíveis, as doses planejadas serão exibidas aqui para administração operacional.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProtocolsList() {
    final active =
        _protocols.where((p) => p.status == TreatmentStatus.active).toList();
    final paused =
        _protocols.where((p) => p.status == TreatmentStatus.paused).toList();
    final history = _protocols
        .where((p) =>
            p.status == TreatmentStatus.completed ||
            p.status == TreatmentStatus.cancelled)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (active.isNotEmpty) ...[
          _buildSectionHeader('Tratamentos Ativos', active.length),
          ...active.map(_buildProtocolCard),
          const SizedBox(height: 16),
        ],
        if (paused.isNotEmpty) ...[
          _buildSectionHeader('Tratamentos Pausados', paused.length),
          ...paused.map(_buildProtocolCard),
          const SizedBox(height: 16),
        ],
        if (history.isNotEmpty) ...[
          _buildSectionHeader('Histórico de Tratamentos', history.length),
          ...history.map(_buildProtocolCard),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.outline,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolCard(TreatmentProtocol protocol) {
    final nextDose = _findNextPlannedDose(protocol);
    final statusColor = _statusColor(protocol.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.outline),
      ),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    protocol.medicationName,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatStatus(protocol.status),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildInfoChip(
                  Icons.medication_rounded,
                  '${protocol.dose.value} ${protocol.dose.unit.wireName} (${_formatRoute(protocol.dose.route)})',
                ),
                _buildInfoChip(
                  Icons.schedule_rounded,
                  protocol.schedule.type == ScheduleTypeBlock.interval
                      ? 'A cada ${protocol.schedule.intervalMinutes} min'
                      : protocol.schedule.type == ScheduleTypeBlock.fixedTimes
                          ? 'Horários: ${protocol.schedule.timesOfDay.join(', ')}'
                          : 'Uso conforme necessidade (PRN)',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Início: ${_dateOnlyFormat.format(protocol.startDate)} • Prescrito por: ${protocol.professional.name}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            if (protocol.instructions != null &&
                protocol.instructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfacePanelSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        protocol.instructions!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (protocol.status == TreatmentStatus.active) ...[
              const Divider(height: 24),
              if (nextDose != null) ...[
                Row(
                  children: [
                    const Icon(Icons.alarm_rounded,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Próxima Dose:',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDoseTime(nextDose['scheduled_for']),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        key: ValueKey('administer_btn_${protocol.id}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : () => _handleAdministerDose(protocol, nextDose),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(
                          'Administrar Dose',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: ValueKey('skip_btn_${protocol.id}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.warning,
                        side: const BorderSide(color: AppTheme.warning),
                        minimumSize: const Size(120, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () => _handleSkipDose(protocol, nextDose),
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: Text(
                        'Pular Dose',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 18, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Text(
                      'Todas as doses da agenda cumpridas.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDoseTime(Object? rawDate) {
    final dt = _parseScheduleDate(rawDate);
    if (dt == null) return 'Horário pendente';
    return _dateFormat.format(dt);
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanelSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
