part of 'dashboard_screen.dart';

// -----------------------------------------------------------------------------
// Tab K9s - Bento Grid
// -----------------------------------------------------------------------------
class _K9sTab extends StatefulWidget {
  const _K9sTab();

  @override
  State<_K9sTab> createState() => _K9sTabState();
}

class _K9sTabState extends State<_K9sTab> {
  String? _lastFetchedDogId;

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      AuthViewModel,
      UserViewModel,
      ShiftViewModel,
      IncidentViewModel
    >(
      builder: (context, authVM, userVM, shiftVM, incidentVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final userModel = userVM.users.cast<UserModel?>().firstWhere(
          (u) => u?.ra == currentRa,
          orElse: () => null,
        );
        final displayName = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );
        final photoStr = userModel?.photoUrl ?? fbUser?.photoURL;
        final raStr = userModel?.ra ?? currentRa ?? '--';

        final activeDogId = shiftVM.activeDogId;
        if (shiftVM.hasActiveShift &&
            activeDogId != null &&
            activeDogId != _lastFetchedDogId) {
          _lastFetchedDogId = activeDogId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Provider.of<IncidentViewModel>(
              context,
              listen: false,
            ).fetchIncidentsForDog(activeDogId);
          });
        }

        return Consumer<DogViewModel>(
          builder: (context, dogVM, _) {
            final activeDog = shiftVM.hasActiveShift && activeDogId != null
                ? dogVM.dogs.cast<Dog?>().firstWhere(
                    (dog) => dog?.id == activeDogId,
                    orElse: () => null,
                  )
                : null;
            final openIncidents =
                activeDogId == null
                      ? const <Incident>[]
                      : incidentVM.incidents
                            .where(
                              (incident) =>
                                  incident.dogId == activeDogId &&
                                  incident.isInProgress,
                            )
                            .toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

            return CustomScrollView(
              slivers: [
                // AppBar
                SliverAppBar(
                  pinned: true,
                  backgroundColor: _hudBackground,
                  title: Text(
                    'CANIL GCM',
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.6,
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _AvatarButton(
                        photoStr: photoStr,
                        displayName: displayName,
                        raStr: raStr,
                        authVM: authVM,
                      ),
                    ),
                  ],
                ),

                // Alert card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _GreetingCard(
                      displayName: displayName,
                      trainingAlerts: dogVM.dogs
                          .where((d) => dogVM.hasTrainingAlert(d))
                          .length,
                      healthAlerts: dogVM.dogs
                          .where((d) => dogVM.hasHealthAlert(d))
                          .length,
                    ),
                  ),
                ),

                if (shiftVM.hasActiveShift &&
                    activeDog != null &&
                    openIncidents.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _DashboardOpenIncidentCard(
                        incident: openIncidents.first,
                        dogName: activeDog.name,
                        additionalCount: openIncidents.length - 1,
                        onContinue: () => _continueIncident(
                          activeDog.id,
                          activeDog.name,
                          openIncidents.first,
                        ),
                        onQuickClose: () => _showQuickCloseIncidentSheet(
                          openIncidents.first,
                          activeDog.id,
                          activeDog.name,
                        ),
                      ),
                    ),
                  ),

                _K9SelectionHeader(count: dogVM.dogs.length),

                // Bento Grid body
                if (dogVM.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (dogVM.dogs.isEmpty)
                  SliverFillRemaining(
                    child: _EmptyState(
                      icon: FontAwesomeIcons.dog,
                      message: 'Nenhum cão cadastrado',
                      hint: 'Toque em + para adicionar',
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      child: _BentoDogGrid(dogs: dogVM.dogs, dogVM: dogVM),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
