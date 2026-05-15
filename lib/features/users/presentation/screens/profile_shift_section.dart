part of 'profile_screen.dart';

extension _ProfileShiftSection on _ProfileScreenState {
  Widget _buildShiftActionsSliver({
    required AuthViewModel authVM,
    required ShiftViewModel shiftVM,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TURNO',
              style: GoogleFonts.inter(
                color: _hudCyan.withAlpha(210),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (shiftVM.hasActiveShift) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isEndingShift
                      ? null
                      : () async {
                          HapticFeedback.lightImpact();
                          _setEndingShift(true);
                          await shiftVM.endShift();
                          if (!mounted) return;
                          _setEndingShift(false);
                          if (shiftVM.error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(shiftVM.error!)),
                            );
                          }
                        },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    'Trocar K9 do Turno',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _hudCyan,
                    side: BorderSide(color: _hudCyan.withAlpha(130)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isEndingShift
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: _hudPanel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            title: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: _hudAmber,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Encerrar Expediente',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            content: const Text(
                              'Tem certeza que deseja encerrar o expediente e fazer logout? Todas as suas atividades do dia foram salvas?',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _hudDanger,
                                ),
                                child: const Text(
                                  'Sim, Encerrar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!mounted) return;
                          _setEndingShift(true);
                          await shiftVM.endShift();
                          if (shiftVM.error != null) {
                            if (!mounted) return;
                            _setEndingShift(false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(shiftVM.error!)),
                            );
                            return;
                          }
                          await authVM.signOut();
                        }
                      },
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  'Encerrar Expediente',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hudDanger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
