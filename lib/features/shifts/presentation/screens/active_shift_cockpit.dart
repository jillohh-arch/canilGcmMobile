part of 'active_shift_dashboard_screen.dart';

extension _ActiveShiftCockpit on _ActiveShiftDashboardScreenState {
  Widget _buildCockpit(
    BuildContext context,
    Dog dog,
    String callsign,
  ) {
    // Foto do condutor logado (Firebase Auth ou UserModel)
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final conductorPhoto = _resolveConductorPhoto(authVM, userVM);

    return CustomScrollView(
      slivers: [
        // 1. Cabeçalho do turno
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: _ShiftHeader(
              dog: dog,
              callsign: callsign,
              conductorPhotoUrl: conductorPhoto,
              onSwitchDog: () => _showDogSwitcher(context, dog),
            ),
          ),
        ),
        // 2. Card de resumo superior (indicadores)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ShiftIndicatorsCard(
              dog: dog,
              totalAlerts: _totalAlerts,
              weatherData: _weatherData,
            ),
          ),
        ),
        // 3. Registros Rápidos
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _QuickActionsSection(
              dog: dog,
              actions: _quickActions,
            ),
          ),
        ),
        // 4. Alertas
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _AlertsSection(
              alerts: _alerts,
              totalAlerts: _totalAlerts,
            ),
          ),
        ),
        // 5. Atividades de Hoje
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _TodayActivitiesSection(dogId: dog.id),
          ),
        ),
        // 6. Card do Cão
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _DogProfileCard(dog: dog),
          ),
        ),
        // 7. Condições climáticas
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            child: _ConditionsCard(weatherData: _weatherData),
          ),
        ),
      ],
    );
  }

  String? _resolveConductorPhoto(AuthViewModel authVM, UserViewModel userVM) {
    // Tenta foto do Firebase Auth
    final fbPhoto = authVM.user?.photoURL;
    if (fbPhoto != null && fbPhoto.isNotEmpty) return fbPhoto;

    // Tenta foto do UserModel pelo RA
    final ra = HandlerIdentityService.raFromUser(authVM.user);
    if (ra != null) {
      final userModel = userVM.findByRa(ra);
      if (userModel?.photoUrl != null) return userModel!.photoUrl;
    }

    return null;
  }
}
