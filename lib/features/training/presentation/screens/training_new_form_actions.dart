part of 'training_log_screen.dart';

class _SaveTrainingButton extends StatelessWidget {
  final String selectedTrainingType;
  final VoidCallback onPressed;

  const _SaveTrainingButton({
    required this.selectedTrainingType,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Consumer<TrainingViewModel>(
        builder: (context, viewModel, child) {
          return ElevatedButton.icon(
            icon: viewModel.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 22),
            label: Text(
              viewModel.isLoading ? 'SALVANDO...' : 'SALVAR TREINO',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: viewModel.isLoading ? null : onPressed,
          );
        },
      ),
    );
  }
}
