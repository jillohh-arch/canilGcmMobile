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
                    final dog = dogVM.dogs[i];
                    return _TrainingDogLaunchCard(
                      dog: dog,
                      dogVM: dogVM,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrainingLogScreen(dogId: dog.id),
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
