part of 'active_shift_dashboard_screen.dart';

class _HeroDogIdentity extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final VoidCallback onTap;

  const _HeroDogIdentity({
    required this.dog,
    required this.callsign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _HeroDogAvatar(dog: dog),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '$callsign & ${dog.name}'.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.6,
                      height: 1.1,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.swap_horiz_rounded, color: _hudCyan, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const _ActiveShiftPill(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _HeroDogAvatar extends StatelessWidget {
  final Dog dog;

  const _HeroDogAvatar({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _hudCyan, width: 3),
        boxShadow: [
          BoxShadow(
            color: _hudCyan.withAlpha(60),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 48,
        backgroundColor: _hudPanelAlt,
        backgroundImage: dog.profileImageUrl != null
            ? CachedNetworkImageProvider(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? const FaIcon(
                FontAwesomeIcons.dog,
                size: 36,
                color: Colors.white54,
              )
            : null,
      ),
    );
  }
}
