part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateOptions on _DailyTimelineScreenState {
  List<Widget> _buildIncidentUpdateShortcutSection({
    required List<_IncidentQuickProgressShortcut> shortcuts,
    required String? selectedShortcut,
    required void Function(
      _IncidentQuickProgressShortcut shortcut,
      bool isSelected,
    )
    onShortcutSelected,
  }) {
    if (shortcuts.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 18),
      Text(
        'ETAPAS RÁPIDAS',
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: shortcuts.map((shortcut) {
          final isSelected = selectedShortcut == shortcut.title;
          return _buildIncidentUpdateShortcutChip(
            shortcut: shortcut,
            isSelected: isSelected,
            onTap: () => onShortcutSelected(shortcut, isSelected),
          );
        }).toList(),
      ),
    ];
  }

  Widget _buildIncidentUpdateShortcutChip({
    required _IncidentQuickProgressShortcut shortcut,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4ECDE4).withAlpha(25)
              : Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4ECDE4).withAlpha(100)
                : Colors.white10,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          shortcut.title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? const Color(0xFF4ECDE4) : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentUpdateOutcomeSection({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required void Function(String outcome, bool isSelected) onOutcomeSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DESFECHOS PARCIAIS',
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickCloseOutcomeOptionsForSubtype(incident.type).map((
            outcome,
          ) {
            final isSelected = selectedOutcomes.contains(outcome);
            return _buildIncidentSelectionChip(
              label: outcome,
              selected: isSelected,
              style: _resolveIncidentOutcomeBadgeStyle(outcome),
              onTap: () => onOutcomeSelected(outcome, isSelected),
            );
          }).toList(),
        ),
      ],
    );
  }
}
