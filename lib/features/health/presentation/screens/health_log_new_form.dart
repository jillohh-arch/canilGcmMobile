part of 'health_log_screen.dart';

class _NewHealthLogForm extends StatelessWidget {
  final String dogId;
  final VoidCallback onSaved;

  const _NewHealthLogForm({required this.dogId, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withAlpha(40),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.medical_services_rounded,
                size: 64,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Prontuário de Saúde K9',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Garante a integridade do histórico do cão registrando vacinas, exames, consultas, cirurgias, medicamentos, sintomas e pesagens de forma organizada e auditável.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: Text(
                  'Iniciar Registro Médico',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HealthTypeSelectorScreen(dogId: dogId),
                    ),
                  ).then((saved) {
                    if (saved == true) {
                      onSaved();
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Todos os registros geram trilha de auditoria para o condutor.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
