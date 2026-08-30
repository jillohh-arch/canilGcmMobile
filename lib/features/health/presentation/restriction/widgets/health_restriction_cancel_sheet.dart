import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../shared/widgets/health_field_label.dart';

/// Coleta o motivo da invalidação administrativa de uma restrição (B4-C.4).
///
/// ## Por que só coleta texto
///
/// A sheet NÃO executa a mutation e NÃO hospeda estado causal. Ela devolve o
/// motivo trimado e nada mais; quem executa o CANCEL é o
/// `HealthRestrictionCancelController`, hospedado na tela de detalhe.
///
/// Se a mutation acontecesse aqui, o `mutationCommitted` morreria junto com a
/// sheet ao ser descartada — e um CANCEL commitado cuja convergência falhou
/// perderia o `retryConvergence()`. Mesmo raciocínio do B4-C.3.
///
/// ## Vocabulário
///
/// "Invalidar registro", nunca "liberar" nem "encerrar": CANCEL é invalidação
/// administrativa de um lançamento indevido, não liberação clínica. A distinção
/// é explicitada na própria sheet, apontando END como o caminho clínico.
Future<String?> showHealthRestrictionCancelSheet(
  BuildContext context, {
  required String dogName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfacePanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _CancelReasonSheet(dogName: dogName),
  );
}

/// Limite alinhado ao motivo de encerramento do fluxo de restrição.
const int kHealthRestrictionCancelReasonMaxLength = 500;

class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet({required this.dogName});

  final String dogName;

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Motivo é obrigatório e nunca tem default: a justificativa administrativa é
  /// afirmação do operador, e um texto pré-preenchido seria auditoria falsa.
  void _confirm() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Informe o motivo da invalidação.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Invalidar registro',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.dogName,
            style: const TextStyle(
              color: AppTheme.textSoft,
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          // Distinção obrigatória entre os dois terminais. Sem isto, um operador
          // pode invalidar um registro válido acreditando estar liberando o K9.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfacePanelStrong,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.outline.withValues(alpha: 0.6)),
            ),
            child: const Text(
              'Use quando o registro de restrição tiver sido lançado '
              'indevidamente. Não é liberação clínica: para alta clínica, '
              'utilize Encerrar restrição.',
              style: TextStyle(
                color: AppTheme.textSoft,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const HealthFieldLabel(
            'Motivo da invalidação',
            required: true,
            accentColor: AppTheme.error,
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('restriction_cancel_reason'),
            controller: _controller,
            maxLines: 3,
            maxLength: kHealthRestrictionCancelReasonMaxLength,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ex.: Registro lançado no K9 errado.',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('restriction_cancel_dismiss'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSoft,
                    side: const BorderSide(color: AppTheme.outline),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('restriction_cancel_confirm'),
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('INVALIDAR REGISTRO'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
