part of 'main_root_screen.dart';

class _ActiveIncidentBanner extends StatelessWidget {
  final Incident incident;
  final String dogName;
  final VoidCallback onTap;

  const _ActiveIncidentBanner({
    required this.incident,
    required this.dogName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (incident.type ?? 'Ocorrência').trim();
    final location = incident.location.trim().isEmpty
        ? 'Local não informado'
        : incident.location.trim();

    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withAlpha(244),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFFFB84D).withAlpha(190),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB84D).withAlpha(46),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB84D).withAlpha(24),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFFB84D).withAlpha(150),
                    ),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: Color(0xFFFFB84D),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OCORRÊNCIA EM ANDAMENTO',
                        style: GoogleFonts.robotoMono(
                          color: const Color(0xFFFFB84D),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.oxanium(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dogName • $location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB84D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CONTINUAR',
                    style: GoogleFonts.robotoMono(
                      color: const Color(0xFF070B14),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
