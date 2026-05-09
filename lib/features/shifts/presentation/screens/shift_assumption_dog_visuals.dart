part of 'shift_assumption_screen.dart';

class _DogBackdrop extends StatelessWidget {
  final Dog dog;

  const _DogBackdrop({required this.dog});

  @override
  Widget build(BuildContext context) {
    if (dog.profileImageUrl == null || dog.profileImageUrl!.isEmpty) {
      return Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 86,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: dog.profileImageUrl!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(color: _hudCyan, strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 72,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      ),
    );
  }
}

class _DogIdentity extends StatelessWidget {
  final Dog dog;

  const _DogIdentity({required this.dog});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hudBackground.withAlpha(185),
            border: Border.all(color: _hudCyan.withAlpha(80)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dog.name.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dog.breed.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.robotoMono(
                  color: _hudCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
