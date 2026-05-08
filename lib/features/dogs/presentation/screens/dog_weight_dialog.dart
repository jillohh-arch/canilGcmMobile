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
      backgroundColor: const Color(0xFF141A21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      title: Text(
        'ATUALIZAR PESO',
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insira o novo peso do cão em quilogramas (kg).',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.robotoMono(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              suffixText: 'kg',
              suffixStyle: GoogleFonts.poppins(color: Colors.white38),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A2A)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _weightAccent, width: 1.5),
              ),
              filled: true,
              fillColor: Colors.black12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'CANCELAR',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              color: Colors.white38,
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
                  backgroundColor: Color(0xFFE53935),
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
                  backgroundColor: const Color(0xFFE53935),
                ),
              );
              return;
            }

            try {
              final hLog = HealthLogModel(
                dogId: dog.id,
                dogName: dog.name,
                date: DateTime.now(),
                logType: 'Rotina',
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
                  backgroundColor: const Color(0xFFFBBF24),
                ),
              );
            }
          },
          child: Text(
            'SALVAR',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              color: Colors.black,
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
