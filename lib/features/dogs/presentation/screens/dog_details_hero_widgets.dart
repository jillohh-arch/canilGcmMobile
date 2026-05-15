part of 'dog_details_screen.dart';

class _DogHeroAvatar extends StatelessWidget {
  final Dog dog;

  const _DogHeroAvatar({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 56,
        backgroundColor: Colors.white24,
        backgroundImage: dog.profileImageUrl != null
            ? NetworkImage(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? const FaIcon(FontAwesomeIcons.dog, size: 40, color: Colors.white)
            : null,
      ),
    );
  }
}

class _DogHeroIdentity extends StatelessWidget {
  final Dog dog;
  final Color statusColor;

  const _DogHeroIdentity({required this.dog, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AgentStatusPill(status: dog.operationalStatus, color: statusColor),
        const SizedBox(height: 8),
        Text(
          dog.name.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
        Row(
          children: [
            Text(
              dog.breed,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              dog.sex == 'F' ? Icons.female_rounded : Icons.male_rounded,
              size: 16,
              color: dog.sex == 'F'
                  ? const Color(0xFFFF80AB)
                  : const Color(0xFF82B1FF),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${dog.age} anos Â· ID: ${dog.id.substring(0, 8).toUpperCase()}',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
