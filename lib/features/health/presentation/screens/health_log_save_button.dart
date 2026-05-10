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
    final (_, selectedColor) = _iconAndColor(selectedLogType);

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
              backgroundColor: selectedColor,
              foregroundColor: Colors.white,
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
