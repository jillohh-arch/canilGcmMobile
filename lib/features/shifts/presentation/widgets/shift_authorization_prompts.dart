import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';

/// HEALTH-V1-OP-AUTH — apresentação das decisões de autorização operacional.
///
/// Compartilhado entre iniciar turno e trocar K9 para que as duas ações críticas
/// tratem a MESMA decisão da mesma forma. Duplicar essa lógica seria como as
/// telas divergirem no que significa "bloqueado".
///
/// A UI apenas apresenta: ela não decide, não recalcula e não oferece bypass.
abstract final class ShiftAuthorizationPrompts {
  /// Resumo seguro de uma restrição (sem PII de profissional/documento).
  static Widget restrictionSummary(ShiftRestrictionInfo restriction) {
    final expectedEnd = restriction.expectedEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (restriction.description.isNotEmpty)
          Text(
            restriction.description,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (expectedEnd != null)
          Text(
            restriction.isOverdue
                // Vencida NÃO é encerrada: vale até encerramento explícito.
                ? 'Previsão de término vencida — aguardando reavaliação.'
                : 'Previsão de término: ${_formatDate(expectedEnd)}',
            style: GoogleFonts.inter(
              color: restriction.isOverdue
                  ? AppTheme.warning
                  : AppTheme.textTertiary,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  /// Bloqueio clínico. Ação única — não existe "continuar mesmo assim".
  static Future<void> showBlocked(
    BuildContext context, {
    required String dogName,
    required ShiftAuthorizationFailure failure,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '$dogName temporariamente inapto',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure.kind == ShiftAuthorizationFailureKind.activityRestricted
                  ? 'A atividade solicitada está restrita para este K9. '
                        'A associação ao turno não foi realizada.'
                  : 'Existe uma restrição operacional ativa. '
                        'A associação ao turno não foi realizada.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            for (final restriction in failure.restrictions)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: restrictionSummary(restriction),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Entendi',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Restrição parcial: mostra limitações e coleta ciência explícita.
  ///
  /// O aceite NÃO libera clinicamente — ele é registrado pelo backend como
  /// ciência operacional do responsável.
  static Future<bool> confirmPartial(
    BuildContext context, {
    required String dogName,
    required ShiftAuthorizationFailure failure,
  }) async {
    final restrictions = failure.partialRestrictions.isNotEmpty
        ? failure.partialRestrictions
        : failure.restrictions;
    final activities = <String>{
      for (final restriction in restrictions)
        ...restriction.activitiesRestricted,
    }.toList(growable: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '$dogName está apto com restrições',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activities.isNotEmpty) ...[
              Text(
                'Atividades restringidas:',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              for (final activity in activities)
                Text(
                  '• $activity',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 10),
            ],
            for (final restriction in restrictions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: restrictionSummary(restriction),
              ),
            Text(
              'Confirme que está ciente das restrições antes de continuar.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Estou ciente',
              style: GoogleFonts.inter(
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Mensagem para negativas que não têm diálogo próprio.
  ///
  /// Separa explicitamente falha de verificação (fail-closed) de queda de
  /// conexão: tratá-las igual foi o defeito que esta vertical corrige.
  static void showFailureMessage(
    BuildContext context, {
    required String dogName,
    required ShiftAuthorizationFailure failure,
  }) {
    switch (failure.kind) {
      case ShiftAuthorizationFailureKind.restrictionsUnavailable:
        AppFeedback.error(
          context,
          'Não foi possível verificar as restrições operacionais de $dogName. '
          'Por segurança, a operação não foi realizada. Tente novamente.',
        );
      case ShiftAuthorizationFailureKind.network:
        AppFeedback.error(
          context,
          'Sem comunicação com o servidor. Confira sua conexão e '
          'tente novamente.',
        );
      default:
        AppFeedback.error(context, failure.message);
    }
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
