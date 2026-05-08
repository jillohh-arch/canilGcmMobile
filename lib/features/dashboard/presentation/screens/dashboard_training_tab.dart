part of 'dashboard_screen.dart';

class _TreinosTab extends StatelessWidget {
  const _TreinosTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DogViewModel>(
      builder: (context, dogVM, _) {
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: _hudBackground,
              title: Text(
                'TREINOS',
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            if (dogVM.isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: _hudCyan),
                ),
              )
            else if (dogVM.dogs.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(
                  icon: FontAwesomeIcons.dog,
                  message: 'Nenhum cão cadastrado',
                  hint: 'Cadastre um cão para registrar treinos',
                ),
              )
            else ...[
              const SliverToBoxAdapter(child: _TrainingIntroCard()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.separated(
                  itemCount: dogVM.dogs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = dogVM.dogs[i];
                    return _TrainingDogLaunchCard(
                      dog: d,
                      dogVM: dogVM,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrainingLogScreen(dogId: d.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TrainingIntroCard extends StatelessWidget {
  const _TrainingIntroCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(210),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hudAmber.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _hudAmber.withAlpha(130)),
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: _hudAmber,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECIONE O CÃO PARA TREINO',
                    style: GoogleFonts.oxanium(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Acesse o diário operacional e registre uma sessão.',
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
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

class _TrainingDogLaunchCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  final VoidCallback onTap;

  const _TrainingDogLaunchCard({
    required this.dog,
    required this.dogVM,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrainingAlert = dogVM.hasTrainingAlert(dog);
    final lastTraining = dog.lastTrainingDate == null
        ? 'Sem registro recente'
        : _formatTrainingAge(dog.lastTrainingDate!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasTrainingAlert
                ? _hudAmber.withAlpha(140)
                : _hudCyan.withAlpha(65),
          ),
          boxShadow: [
            BoxShadow(
              color: (hasTrainingAlert ? _hudAmber : _hudCyan).withAlpha(18),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            _DogAvatar(dog: dog, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dog.breed,
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _TrainingInfoChip(
                        icon: Icons.schedule_rounded,
                        label: lastTraining,
                        color: hasTrainingAlert ? _hudAmber : _hudCyan,
                      ),
                      _TrainingInfoChip(
                        icon: Icons.monitor_weight_outlined,
                        label: dog.weight != null
                            ? '${dog.weight!.toStringAsFixed(1)} kg'
                            : 'Peso pendente',
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hudCyan.withAlpha(18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _hudCyan.withAlpha(100)),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: _hudCyan,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTrainingAge(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff <= 0) return 'Treino hoje';
    if (diff == 1) return 'Treino há 1 dia';
    return 'Treino há $diff dias';
  }
}

class _TrainingInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TrainingInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
