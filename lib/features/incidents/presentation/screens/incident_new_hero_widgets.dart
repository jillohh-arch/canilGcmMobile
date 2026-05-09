part of 'incident_form_screen.dart';

class _NewIncidentHero extends StatelessWidget {
  final dynamic dog;

  const _NewIncidentHero({required this.dog});

  @override
  Widget build(BuildContext context) {
    final profileImageUrl = dog?.profileImageUrl?.toString();

    return Column(
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00E5FF), width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
            image: profileImageUrl != null && profileImageUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(profileImageUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            color: const Color(0xFF1A2328),
          ),
          child: profileImageUrl == null || profileImageUrl.isEmpty
              ? const Icon(Icons.pets, size: 60, color: Colors.white30)
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          (dog?.name?.toString() ?? 'K9').toUpperCase(),
          style: GoogleFonts.oxanium(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 6),
        const _IncidentActiveShiftBadge(),
      ],
    );
  }
}

class _IncidentActiveShiftBadge extends StatelessWidget {
  const _IncidentActiveShiftBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF00F5A0),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0xFF00F5A0), blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'TURNO ATIVO',
          style: GoogleFonts.robotoMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF00F5A0),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
