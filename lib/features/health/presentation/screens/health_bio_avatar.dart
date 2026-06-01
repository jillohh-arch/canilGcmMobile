part of 'health_dashboard_screen.dart';

class _PulsingDogAvatar extends StatelessWidget {
  final Dog dog;
  final Animation<double> animation;

  const _PulsingDogAvatar({required this.dog, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(
                alpha: 0.3 + (animation.value * 0.7),
              ),
              width: 2 + (animation.value * 1),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(
                  alpha: 0.4 * animation.value,
                ),
                blurRadius: 15 + (15 * animation.value),
                spreadRadius: 2 + (5 * animation.value),
              ),
            ],
          ),
          child: child,
        );
      },
      child: CircleAvatar(
        radius: 55,
        backgroundColor: AppTheme.surfacePanelSoft,
        backgroundImage: dog.profileImageUrl != null
            ? CachedNetworkImageProvider(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? Icon(
                Icons.pets,
                size: 40,
                color: AppTheme.textPrimary.withAlpha(61),
              )
            : null,
      ),
    );
  }
}
