part of 'dashboard_screen.dart';

class _GuardasTab extends StatelessWidget {
  const _GuardasTab();

  @override
  Widget build(BuildContext context) => const UserManagementScreen();
}

class _DogAvatar extends StatelessWidget {
  final Dog dog;
  final double radius;
  const _DogAvatar({required this.dog, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _hudCyan.withAlpha(125), width: 1.5),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(28), blurRadius: 12)],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _hudPanelAlt,
        backgroundImage: dog.profileImageUrl != null
            ? NetworkImage(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? FaIcon(
                FontAwesomeIcons.dog,
                size: radius * 0.8,
                color: _hudCyan.withAlpha(180),
              )
            : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final dynamic icon;
  final String message;
  final String hint;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon is IconData
              ? Icon(icon as IconData, size: 64, color: cs.outlineVariant)
              : FaIcon(icon as dynamic, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Kept for backward compat if any screen still uses DogCard
class DogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const DogCard({super.key, required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) =>
      _FeaturedDogCard(dog: dog, dogVM: dogVM);
}
