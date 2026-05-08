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

class _IncidentStartContextRow extends StatelessWidget {
  final DateTime timestamp;

  const _IncidentStartContextRow({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}';

    return Row(
      children: [
        Expanded(
          child: _IncidentInfoCard(
            icon: Icons.location_on_rounded,
            label: 'LOCAL ATUAL',
            body: Text(
              'Obtendo localização GPS...',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _IncidentInfoCard(
            icon: Icons.access_time_rounded,
            label: 'HORA ATUAL',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.oxanium(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IncidentInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget body;

  const _IncidentInfoCard({
    required this.icon,
    required this.label,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF4ECDE4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF4ECDE4),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

class _IncidentNatureField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<OccurrenceNature> onSelected;
  final ValueChanged<String> onChanged;

  const _IncidentNatureField({
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NATUREZA DA OCORRÊNCIA',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        OccurrenceNatureSearch(
          controller: controller,
          focusNode: focusNode,
          natures: OccurrenceNatureSeed.items,
          panelColor: const Color(0xFF0B1220),
          accent: const Color(0xFF00E5FF),
          onSelected: onSelected,
          onChanged: onChanged,
          fieldBuilder: (context, controller, focusNode, onChanged) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex: Busca de Entorpecentes',
                hintStyle: GoogleFonts.inter(
                  color: Colors.white24,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.radar_rounded,
                  color: Color(0xFF00E5FF),
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFF0B1220),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _IncidentStartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _IncidentStartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidentViewModel>(
      builder: (context, vm, _) {
        return SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: vm.isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF070B14),
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: vm.isLoading
                    ? const CircularProgressIndicator(color: Color(0xFF070B14))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'INICIAR OCORRÊNCIA',
                            style: GoogleFonts.oxanium(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
