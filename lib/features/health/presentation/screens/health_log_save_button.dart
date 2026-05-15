part of 'health_log_screen.dart';

class _SaveHealthLogButton extends StatelessWidget {
  final String selectedLogType;
  final VoidCallback onPressed;

  const _SaveHealthLogButton({
    required this.selectedLogType,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Consumer<HealthViewModel>(
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
                : Icon(_logIcon(selectedLogType), size: 22),
            label: Text(
              viewModel.isLoading ? 'SALVANDO...' : 'SALVAR PRONTUÁRIO',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF030712),
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
