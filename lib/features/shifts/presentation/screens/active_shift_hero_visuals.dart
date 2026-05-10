part of 'active_shift_dashboard_screen.dart';

class _HeroDogBackdrop extends StatelessWidget {
  final Dog dog;

  const _HeroDogBackdrop({required this.dog});

  @override
  Widget build(BuildContext context) {
    if (dog.profileImageUrl != null) {
      return Hero(
        tag: 'dog_profile_${dog.id}',
        child: CachedNetworkImage(
          imageUrl: dog.profileImageUrl!,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      );
    }

    return Container(
      color: _hudPanel,
      child: const Center(
        child: FaIcon(FontAwesomeIcons.dog, size: 64, color: Colors.white24),
      ),
    );
  }
}

class _HeroDogScrim extends StatelessWidget {
  const _HeroDogScrim();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.black.withAlpha(50),
                _hudBackground.withAlpha(170),
                _hudBackground,
              ],
              stops: const [0, 0.3, 0.6, 1],
            ),
          ),
        ),
      ),
    );
  }
}
