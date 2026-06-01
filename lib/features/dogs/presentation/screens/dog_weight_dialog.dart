part of 'dog_details_screen.dart';

void _showDogWeightDialog(
  BuildContext context,
  Dog dog,
  double? currentWeight,
) {
  final controller = TextEditingController(
    text: currentWeight != null ? currentWeight.toStringAsFixed(1) : '',
  );

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfacePanelAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppTheme.outline),
      ),
      title: Text(
        'ATUALIZAR PESO',
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
          letterSpacing: 1,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insira o novo peso do cão em quilogramas (kg).',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textPrimary.withAlpha(179),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              suffixText: 'kg',
              suffixStyle: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(97),
              ),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.outline),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _weightAccent, width: 1.5),
              ),
              filled: true,
              fillColor: AppTheme.background.withAlpha(31),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'CANCELAR',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary.withAlpha(97),
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _weightAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () async {
            final weight = double.tryParse(
              controller.text.replaceAll(',', '.'),
            );
            if (weight == null || weight <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Informe um peso válido.'),
                  backgroundColor: AppTheme.errorStrong,
                ),
              );
              return;
            }

            final messenger = ScaffoldMessenger.of(context);
            final dogVM = Provider.of<DogViewModel>(context, listen: false);
            final healthVM = Provider.of<HealthViewModel>(
              context,
              listen: false,
            );

            Navigator.pop(ctx);

            try {
              await dogVM.updateDogWeight(dog.id, weight);
            } catch (e) {
              if (!context.mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Erro ao atualizar peso: $e'),
                  backgroundColor: AppTheme.errorStrong,
                ),
              );
              return;
            }

            try {
              final hLog = HealthLogModel(
                dogId: dog.id,
                dogName: dog.name,
                date: DateTime.now(),
                type: 'other',
                subtype: 'Pesagem',
                healthObservations: 'Pesagem de rotina registrada no dossiê.',
                weight: weight,
              );
              await healthVM.addHealthLog(hLog);

              if (!context.mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Peso atualizado e histórico registrado.'),
                  backgroundColor: _weightAccent,
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Peso atualizado. Histórico médico pendente: ${_cleanHealthError(e)}',
                  ),
                  backgroundColor: AppTheme.warningAccent,
                ),
              );
            }
          },
          child: Text(
            'SALVAR',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AppTheme.background,
            ),
          ),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

String _cleanHealthError(Object error) {
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Falha ao salvar registro médico: ', '')
      .trim();
}
