import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/health_restriction_read_gateway.dart';
import '../../domain/health_v1_enums_ext.dart';
import '../../domain/operational_restriction.dart';
import '../shared/evidence/health_evidence_picker.dart';
import '../shared/states/health_async_body.dart';
import '../shared/states/health_presentation_status.dart';
import '../shared/widgets/health_form_section.dart';
import '../shared/forms/health_form_scaffold.dart';
import 'health_professional_draft.dart';
import 'health_restriction_detail_controller.dart';
import 'health_restriction_convergence_coordinator.dart';
import 'health_restriction_end_controller.dart';
import 'health_restriction_end_form_screen.dart';
import 'health_restriction_labels.dart';

/// Constrói o controller de encerramento sob demanda.
///
/// Injetado pelo entry screen para que o detalhe não conheça gateways de
/// Functions/Storage nem construa Firebase por conta própria.
typedef HealthRestrictionEndControllerFactory =
    HealthRestrictionEndController Function();

/// Detalhe canônico de UMA restrição operacional.
///
/// B4-C.2 (leitura canônica) + B4-C.3 (host do encerramento clínico). Primeiro
/// destino real de uma restrição no Mobile.
///
/// ## Autoridade dos dados
///
/// Tudo que esta tela mostra vem do aggregate canônico lido em
/// `dogs/{dogId}/operational_restrictions/{restrictionId}` pelo reader B4-B2. A
/// projeção de Prontidão levou o operador até aqui, mas deixa de ser autoridade
/// no instante em que a leitura canônica ocorre — nenhum campo é preenchido com
/// dado da projeção, e nenhum campo sobrevive do formulário de encerramento: o
/// que a tela exibe após um END é a releitura canônica, não o que foi digitado.
///
/// ## Host de lifecycle (B4-C.3)
///
/// A tela hospeda o [HealthRestrictionEndController] da sessão. Ele sobrevive ao
/// fechamento do formulário de propósito: quando o END commitou mas a
/// convergência causal falhou, é ele que guarda `mutationCommitted`, o resultado
/// terminal e o `retryConvergence()`. A tela não conhece PREPARE, upload,
/// FINALIZE nem END — só o controller.
///
/// ## O que esta tela deliberadamente NÃO faz
///
/// - não cancela restrição (CANCEL é B4-C.4);
/// - não reexecuta END, PREPARE, upload ou FINALIZE em nenhum retry;
/// - não abre, baixa nem assina URL de HealthDocument (subgate próprio);
/// - não calcula prontidão, severidade nem autorização operacional;
/// - não implementa predicado causal: consome o estado congelado do B4-R.C3;
/// - não toca Firestore diretamente: todo I/O passa pelo controller/gateway.

class HealthRestrictionDetailScreen extends StatefulWidget {
  const HealthRestrictionDetailScreen({
    required this.controller,
    required this.dogName,
    this.endControllerFactory,
    this.evidencePicker,
    super.key,
  });

  final HealthRestrictionDetailController controller;

  /// Nome do K9, apenas para cabeçalho do formulário de encerramento.
  final String dogName;

  /// Ausente desabilita a ação de encerrar (ex.: superfícies read-only).
  final HealthRestrictionEndControllerFactory? endControllerFactory;

  /// Seam de teste do picker de evidência.
  final HealthEvidencePicker? evidencePicker;

  @override
  State<HealthRestrictionDetailScreen> createState() =>
      _HealthRestrictionDetailScreenState();
}

class _HealthRestrictionDetailScreenState
    extends State<HealthRestrictionDetailScreen> {
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateOnly = DateFormat('dd/MM/yyyy');

  /// Controller de encerramento da sessão atual.
  ///
  /// Sobrevive ao fechamento do formulário de propósito: quando o END commitou
  /// mas a convergência falhou, é ele que guarda `mutationCommitted`, o
  /// resultado terminal e o `retryConvergence()` — e repetir o END está fora de
  /// questão.
  HealthRestrictionEndController? _endController;

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
    _endController?.removeListener(_onControllerChanged);
    _endController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Abre o formulário de encerramento clínico.
  ///
  /// O END é orquestrado pelo controller (PREPARE → upload → FINALIZE → END) e,
  /// após o commit, pela barreira causal. Nada disso é refeito por retry.
  Future<void> _openEndForm(OperationalRestriction restriction) async {
    final factory = widget.endControllerFactory;
    if (factory == null) return;

    // Reusa o controller da sessão quando existir: ele carrega o progresso
    // documental e o estado de mutation já commitada.
    final endController = _endController ??= factory()
      ..addListener(_onControllerChanged);

    await Navigator.of(context).push<HealthRestrictionEndOutcome>(
      MaterialPageRoute(
        builder: (_) => HealthRestrictionEndFormScreen(
          controller: endController,
          dogId: widget.controller.dogId,
          dogName: widget.dogName,
          restrictionId: restriction.id,
          evidencePicker: widget.evidencePicker,
        ),
      ),
    );

    if (!mounted) return;

    // Reload canônico sempre que o END commitou, INDEPENDENTEMENTE da
    // convergência: o documento canônico já mudou para `ended`, e é ele — não a
    // projeção — que a tela apresenta.
    //
    // A autoridade é o coordenador do controller, NÃO o resultado da navegação:
    // um pop por gesto de sistema ou back do Android devolve `null` mesmo com o
    // END já commitado, e confiar no resultado perderia a mutation. O controller
    // sobrevive ao fechamento do formulário exatamente para isso.
    if (endController.convergence.mutationCommitted) {
      await widget.controller.load();
    }
  }

  /// Retenta apenas a barreira causal. Nunca reenvia END, PREPARE, upload ou
  /// FINALIZE.
  Future<void> _retryConvergence() async {
    final endController = _endController;
    if (endController == null) return;
    await endController.convergence.retryConvergence();
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
        // Banner causal: só aparece quando existe comando commitado nesta sessão
        // cuja projeção não foi provada. Nunca sugere que o comando falhou.
        if (_showsConvergencePending) _convergencePendingBanner(),
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
        // END só faz sentido enquanto a restrição está ativa. A visibilidade é
        // por status de domínio; a autorização continua sendo do backend, que
        // pode negar mesmo com a ação oferecida.
        if (restriction.status == RestrictionStatus.active &&
            widget.endControllerFactory != null)
          _endAction(restriction),
      ],
    );
  }

  /// Verdadeiro quando um comando desta sessão commitou e a projeção ainda não
  /// foi provada causalmente.
  bool get _showsConvergencePending {
    final convergence = _endController?.convergence;
    return convergence != null && convergence.needsConvergenceRetry;
  }

  Widget _convergencePendingBanner() {
    final converging =
        _endController?.convergence.phase ==
        HealthRestrictionConvergencePhase.converging;

    return Container(
      key: const Key('restriction_convergence_pending'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sync_problem_outlined,
                color: AppTheme.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                // Linguagem obrigatória: o comando FOI aplicado. Só a
                // sincronização da prontidão não pôde ser confirmada.
                child: Text(
                  'Encerramento aplicado. Prontidão ainda não sincronizada.',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('restriction_retry_convergence'),
              // Retry causal apenas: refresh + releitura + prova.
              onPressed: converging ? null : _retryConvergence,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                converging ? 'Sincronizando...' : 'Tentar sincronizar',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.warning,
                side: BorderSide(
                  color: AppTheme.warning.withValues(alpha: 0.7),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _endAction(OperationalRestriction restriction) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: OutlinedButton.icon(
        key: const Key('restriction_open_end_form'),
        onPressed: () => _openEndForm(restriction),
        icon: const Icon(Icons.verified_outlined, size: 18),
        label: const Text('Encerrar restrição'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent.withValues(alpha: 0.7)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
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
        // Rótulo distinto do 'Documento clínico' da seção de registro: aquele é
        // a evidência que FUNDAMENTOU a restrição; este é a evidência da
        // liberação clínica. Um agregado ENDED tem os dois, e confundi-los
        // apagaria a diferença entre "por que foi restringido" e "por que foi
        // liberado". Identidade apenas — abrir/baixar é subgate separado.
        if (restriction.endSourceDocument != null)
          _field('Documento de liberação', 'Vinculado ao encerramento'),
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
