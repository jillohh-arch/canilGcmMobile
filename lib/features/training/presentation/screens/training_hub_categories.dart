part of 'training_hub_screen.dart';

class _TrainingHubCategories extends StatelessWidget {
  final Dog dog;
  final void Function(String category) onCategoryTap;

  const _TrainingHubCategories({
    required this.dog,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);

    // Especialidades do cão (com status real)
    final specialties = _buildSpecialtyCards(trainingVM);
    // Treinos gerais (sem status de especialidade)
    final generalTrainings = _buildGeneralCards(trainingVM);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Especialidades
        if (specialties.isNotEmpty) ...[
          _sectionLabel('ESPECIALIDADES', count: specialties.length),
          const SizedBox(height: 10),
          ...specialties,
          const SizedBox(height: 12),
          // Botão iniciar nova especialidade
          _buildAddSpecialtyButton(),
          const SizedBox(height: 24),
        ],

        // Treinos gerais
        _sectionLabel('TREINOS GERAIS'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < generalTrainings.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: generalTrainings[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, {int? count}) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: 1, color: AppTheme.primary.withAlpha(30)),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count ativas',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildSpecialtyCards(TrainingViewModel trainingVM) {
    final specs = <_SpecialtyData>[];

    // Detecção
    final detLast = _lastSessionDaysAgo(trainingVM, 'Detecção');
    specs.add(_SpecialtyData(
      name: 'Detecção',
      emoji: '👃',
      color: AppTheme.primary,
      status: _getSpecialtyStatus('deteccao'),
      subtitle: 'Drogas: operacional',
      lastDaysAgo: detLast,
    ));

    // Guarda & Proteção
    final gpLast = _lastSessionDaysAgo(trainingVM, 'Guarda');
    specs.add(_SpecialtyData(
      name: 'Guarda & Proteção',
      emoji: '🛡',
      color: AppTheme.warning,
      status: _getSpecialtyStatus('guarda_protecao'),
      subtitle: 'Defesa e contenção',
      lastDaysAgo: gpLast,
    ));

    // Faro / Rastro
    final faroLast = _lastSessionDaysAgo(trainingVM, 'Faro');
    specs.add(_SpecialtyData(
      name: 'Faro / Rastro',
      emoji: '🎯',
      color: AppTheme.success,
      status: _getSpecialtyStatus('faro_rastro'),
      subtitle: 'Busca e captura',
      lastDaysAgo: faroLast,
    ));

    // Filtra apenas as que têm status (ativas ou em formação)
    final active = specs.where((s) => s.status != 'inativa').toList();
    if (active.isEmpty) return specs.take(2).toList().map((s) => _SpecialtyCard(data: s, onTap: () => onCategoryTap(s.name))).toList();
    return active.map((s) => _SpecialtyCard(data: s, onTap: () => onCategoryTap(s.name))).toList();
  }

  String _getSpecialtyStatus(String key) {
    // Verifica nas especialidades do cão (List<String>)
    final specialties = dog.specialties;
    if (specialties == null || specialties.isEmpty) return 'inativa';
    for (final s in specialties) {
      final name = s.toLowerCase();
      if (name.contains(key) || key.contains(name)) {
        return 'operacional';
      }
    }
    return 'inativa';
  }

  List<Widget> _buildGeneralCards(TrainingViewModel trainingVM) {
    final obedLast = _lastSessionDaysAgo(trainingVM, 'Obediência');
    final condLast = _lastSessionDaysAgo(trainingVM, 'Condicionamento');

    return [
      _GeneralTrainingCard(
        emoji: '🐾',
        label: 'Obediência',
        color: AppTheme.primary,
        lastDaysAgo: obedLast,
        onTap: () => onCategoryTap('Obediência'),
      ),
      _GeneralTrainingCard(
        emoji: '💪',
        label: 'Condicionamento',
        color: AppTheme.primary,
        lastDaysAgo: condLast,
        onTap: () => onCategoryTap('Condicionamento'),
      ),
    ];
  }

  int? _lastSessionDaysAgo(TrainingViewModel vm, String typePrefix) {
    final now = DateTime.now();
    DateTime? last;
    for (final t in vm.trainings) {
      if (t.trainingType.toLowerCase().contains(typePrefix.toLowerCase())) {
        if (last == null || t.date.isAfter(last)) {
          last = t.date;
        }
      }
    }
    if (last == null) return null;
    return now.difference(last).inDays;
  }

  Widget _buildAddSpecialtyButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded, color: AppTheme.primary, size: 16),
          const SizedBox(width: 6),
          Text(
            'Iniciar nova especialidade',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyData {
  final String name;
  final String emoji;
  final Color color;
  final String status;
  final String subtitle;
  final int? lastDaysAgo;

  _SpecialtyData({
    required this.name,
    required this.emoji,
    required this.color,
    required this.status,
    required this.subtitle,
    this.lastDaysAgo,
  });

  bool get isOperational => status == 'operacional';
  String get statusLabel => isOperational ? '● OPERACIONAL' : '◔ EM FORMAÇÃO';
  Color get statusColor => isOperational ? AppTheme.success : AppTheme.warning;

  String get lastLabel {
    if (lastDaysAgo == null) return 'sem sessões';
    if (lastDaysAgo == 0) return 'última hoje';
    if (lastDaysAgo == 1) return 'última há 1 dia';
    return 'última há $lastDaysAgo dias';
  }
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyData data;
  final VoidCallback onTap;

  const _SpecialtyCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Row(
          children: [
            // Borda lateral colorida
            Container(
              width: 3,
              height: 72,
              decoration: BoxDecoration(
                color: data.statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Ícone emoji
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: data.statusColor.withAlpha(30),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(data.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          data.statusLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: data.statusColor,
                          ),
                        ),
                        Text(
                          ' · ${data.lastLabel}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 18),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _GeneralTrainingCard extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final int? lastDaysAgo;
  final VoidCallback onTap;

  const _GeneralTrainingCard({
    required this.emoji,
    required this.label,
    required this.color,
    this.lastDaysAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lastStr = lastDaysAgo == null
        ? 'sem sessões'
        : lastDaysAgo == 0
            ? 'hoje'
            : 'há $lastDaysAgo dias';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    lastStr,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
