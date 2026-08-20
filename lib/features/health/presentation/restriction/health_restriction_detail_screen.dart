import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/health_restriction_read_gateway.dart';
import '../../domain/health_v1_enums_ext.dart';
import '../../domain/operational_restriction.dart';
import '../shared/states/health_async_body.dart';
import '../shared/states/health_presentation_status.dart';
import '../shared/widgets/health_form_section.dart';
import '../shared/forms/health_form_scaffold.dart';
import 'health_professional_draft.dart';
import 'health_restriction_detail_controller.dart';
import 'health_restriction_labels.dart';

/// Detalhe canônico de UMA restrição operacional. SOMENTE LEITURA.
///
/// B4-C.2. Primeiro destino real de uma restrição no Mobile.
///
/// ## Autoridade dos dados
///
/// Tudo que esta tela mostra vem do aggregate canônico lido em
/// `dogs/{dogId}/operational_restrictions/{restrictionId}` pelo reader B4-B2. A
/// projeção de Prontidão levou o operador até aqui, mas deixa de ser autoridade
/// no instante em que a leitura canônica ocorre — nenhum campo é preenchido com
/// dado da projeção.
///
/// ## O que esta tela deliberadamente NÃO faz
///
/// - não encerra nem cancela restrição (B4-C.3 / B4-C.4);
/// - não abre, baixa nem assina URL de HealthDocument (subgate próprio);
/// - não calcula prontidão, severidade nem autorização operacional;
/// - não toca Firestore diretamente: todo I/O passa pelo controller/gateway.
class HealthRestrictionDetailScreen extends StatefulWidget {
  const HealthRestrictionDetailScreen({
    required this.controller,
    super.key,
  });

  final HealthRestrictionDetailController controller;

  @override
  State<HealthRestrictionDetailScreen> createState() =>
      _HealthRestrictionDetailScreenState();
}

class _HealthRestrictionDetailScreenState
    extends State<HealthRestrictionDetailScreen> {
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateOnly = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // Uma única leitura canônica por abertura.
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Vermelho institucional já usado pelo fluxo de restrição.
  Color get _accent => AppTheme.error;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return HealthFormScaffold(
      title: 'Restrição operacional',
      accentColor: _accent,
      // Read-only: não há rascunho a proteger.
      protectUnsavedChanges: false,
      body: HealthAsyncBody(
        status: _statusFor(controller.status),
        loadingMessage: 'Carregando restrição...',
        emptyMessage: 'Restrição não encontrada.',
        errorTitle: _errorTitle(controller.failure),
        errorMessage: _errorMessage(controller.failure),
        onRetry: controller.status == HealthRestrictionDetailStatus.failed
            ? controller.load
            : null,
        data: _body(controller.restriction),
      ),
    );
  }

  HealthPresentationStatus _statusFor(HealthRestrictionDetailStatus status) {
    return switch (status) {
      HealthRestrictionDetailStatus.idle => HealthPresentationStatus.loading,
      HealthRestrictionDetailStatus.loading => HealthPresentationStatus.loading,
      HealthRestrictionDetailStatus.loaded => HealthPresentationStatus.data,
      HealthRestrictionDetailStatus.failed => HealthPresentationStatus.error,
    };
  }

  /// Cada código tipado recebe título próprio: "não existe" e "não foi possível
  /// carregar" são afirmações diferentes e não podem colapsar numa só.
  String? _errorTitle(HealthRestrictionReadFailure? failure) {
    if (failure == null) return null;
    return switch (failure.code) {
      HealthRestrictionReadErrorCode.notFound => 'Restrição não encontrada',
      HealthRestrictionReadErrorCode.permissionDenied => 'Acesso não autorizado',
      HealthRestrictionReadErrorCode.unavailable => 'Sem conexão',
      HealthRestrictionReadErrorCode.integrity => 'Registro inconsistente',
      HealthRestrictionReadErrorCode.validation => 'Restrição inválida',
      HealthRestrictionReadErrorCode.unexpected => 'Falha ao carregar',
    };
  }

  String _errorMessage(HealthRestrictionReadFailure? failure) {
    // A mensagem do domínio já é operacional e sem vocabulário de Rules.
    return failure?.message ?? 'Não foi possível carregar a restrição.';
  }

  Widget _body(OperationalRestriction? restriction) {
    if (restriction == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusHeader(restriction),
        HealthFormSection(
          title: 'Restrição',
          accentColor: _accent,
          child: _identification(restriction),
        ),
        if (restriction.level == RestrictionLevel.partial ||
            restriction.activitiesRestricted.isNotEmpty)
          HealthFormSection(
            title: 'Impacto operacional',
            accentColor: _accent,
            child: _activities(restriction),
          ),
        HealthFormSection(
          title: 'Registro',
          accentColor: _accent,
          child: _record(restriction),
        ),
        if (restriction.status == RestrictionStatus.ended)
          HealthFormSection(
            title: 'Encerramento clínico',
            accentColor: _accent,
            child: _endedBlock(restriction),
          ),
        if (restriction.status == RestrictionStatus.cancelled)
          HealthFormSection(
            title: 'Cancelamento administrativo',
            accentColor: _accent,
            child: _cancelledBlock(restriction),
          ),
      ],
    );
  }

  /// Cabeçalho com o par status + nível, os dois eixos que o operador lê antes
  /// de qualquer detalhe.
  Widget _statusHeader(OperationalRestriction restriction) {
    final statusColor = switch (restriction.status) {
      RestrictionStatus.active => _accent,
      RestrictionStatus.ended => AppTheme.success,
      RestrictionStatus.cancelled => AppTheme.textSoft,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(restriction.status), color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(restriction.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  healthRestrictionLevelLabel(restriction.level),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(RestrictionStatus status) => switch (status) {
    RestrictionStatus.active => Icons.gpp_maybe_outlined,
    RestrictionStatus.ended => Icons.verified_outlined,
    RestrictionStatus.cancelled => Icons.block_outlined,
  };

  /// Rótulos operacionais. `cancelled` é invalidação administrativa e NUNCA
  /// pode ser lido como liberação clínica.
  String _statusLabel(RestrictionStatus status) => switch (status) {
    RestrictionStatus.active => 'ATIVA',
    RestrictionStatus.ended => 'ENCERRADA',
    RestrictionStatus.cancelled => 'CANCELADA (REGISTRO INVALIDADO)',
  };

  Widget _identification(OperationalRestriction restriction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('Descrição', restriction.description),
        _field(
          'Categoria',
          healthRestrictionCategoryLabel(restriction.category),
        ),
        _field('Emitida em', _dateTime.format(restriction.issuedAt)),
        // `expectedEnd` é PREVISÃO: nada aqui sugere liberação automática. O
        // lifecycle só muda por END/CANCEL server-side.
        _field(
          'Previsão de término',
          restriction.expectedEnd == null
              ? 'Não informada'
              : '${_dateOnly.format(restriction.expectedEnd!)} (previsão)',
        ),
      ],
    );
  }

  Widget _activities(OperationalRestriction restriction) {
    final activities = restriction.activitiesRestricted;
    if (activities.isEmpty) {
      // Nunca fabricar "todas as atividades": ausência de lista não é
      // equivalente a restrição total.
      return const Text(
        'Sem atividades específicas registradas.',
        style: TextStyle(color: AppTheme.textSoft, fontSize: 12.5),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final activity in activities)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              activity,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _record(OperationalRestriction restriction) {
    final professional = restriction.professional;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('Registrado por', restriction.recordedBy.name),
        _field('Profissional', professional.name),
        _field(
          'Registro profissional',
          // O tipo armazenado é exibido como está — nunca inferimos CRMV.
          '${healthRegistrationTypeLabel(professional.registrationType)}'
          ' ${professional.registrationNumber}',
        ),
        _field('Clínica', professional.clinic),
        if (professional.specialty != null &&
            professional.specialty!.isNotEmpty)
          _field('Especialidade', professional.specialty!),
        // Identidade documental apenas. Abrir/baixar é subgate separado.
        _field('Documento clínico', 'Vinculado ao registro'),
      ],
    );
  }

  Widget _endedBlock(OperationalRestriction restriction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (restriction.actualEnd != null)
          _field('Encerrada em', _dateTime.format(restriction.actualEnd!)),
        if (restriction.endReason != null)
          _field('Motivo', restriction.endReason!),
        if (restriction.endedBy != null)
          _field('Encerrada por', restriction.endedBy!.name),
        if (restriction.endProfessional != null)
          _field('Profissional', restriction.endProfessional!.name),
      ],
    );
  }

  Widget _cancelledBlock(OperationalRestriction restriction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (restriction.cancelledAt != null)
          _field('Cancelada em', _dateTime.format(restriction.cancelledAt!)),
        if (restriction.cancelReason != null)
          _field('Motivo', restriction.cancelReason!),
        if (restriction.cancelledBy != null)
          _field('Cancelada por', restriction.cancelledBy!.name),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Cancelamento invalida o registro. Não representa liberação '
            'clínica.',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textSoft,
              fontSize: 10.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
