part of 'dashboard_screen.dart';

class _SmallDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;

  const _SmallDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final statusColor = AppTheme.statusColor(opStatus);
    final statusLabel = AppTheme.statusLabel(opStatus);
    final statusIcon = AppTheme.statusIcon(opStatus);

    return GestureDetector(
      onTap: () => _openDogDetails(context, dog),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65), width: 1),
          boxShadow: [BoxShadow(color: _hudCyan.withAlpha(16), blurRadius: 14)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: _SmallDogHeader(
                dog: dog,
                statusLabel: statusLabel,
                statusColor: statusColor,
                statusIcon: statusIcon,
              ),
            ),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _DogCardImage(
                  imageUrl: dog.profileImageUrl,
                  iconSize: 32,
                  iconAlpha: 145,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallDogHeader extends StatelessWidget {
  final Dog dog;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;

  const _SmallDogHeader({
    required this.dog,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dog.name.toUpperCase(),
          style: GoogleFonts.oxanium(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.7,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                dog.breed,
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  color: Colors.white54,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _InlineStatusPill(
              label: statusLabel,
              color: statusColor,
              icon: statusIcon,
            ),
          ],
        ),
      ],
    );
  }
}
