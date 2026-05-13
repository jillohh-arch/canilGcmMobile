part of 'dashboard_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _QuickCloseIncidentControls on _QuickCloseIncidentSheetState {
  Widget _buildOperationalSuccessChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _QuickIncidentChip(
          label: 'Com êxito',
          selected: _operationalSuccess,
          icon: Icons.task_alt_rounded,
          selectedTextColor: const Color(0xFF86EFAC),
          selectedIconColor: const Color(0xFF4ADE80),
          selectedBorderColor: const Color(0x334ADE80),
          selectedBackgroundColor: const Color(0x144ADE80),
          onTap: () => _setOperationalSuccess(true),
        ),
        _QuickIncidentChip(
          label: 'Sem êxito',
          selected: !_operationalSuccess,
          icon: Icons.cancel_rounded,
          selectedTextColor: const Color(0xFFFCA5A5),
          selectedIconColor: const Color(0xFFF87171),
          selectedBorderColor: const Color(0x33F87171),
          selectedBackgroundColor: const Color(0x14F87171),
          onTap: () => _setOperationalSuccess(false),
        ),
      ],
    );
  }

  Widget _buildOutcomeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _quickCloseOutcomeOptionsForSubtype(_incident.type).map((
        outcome,
      ) {
        final isSelected = _containsOutcome(_selectedOutcomes, outcome);
        return _QuickIncidentChip(
          label: outcome,
          selected: isSelected,
          icon: _iconForOutcome(outcome),
          selectedTextColor: _textColorForOutcome(outcome),
          selectedIconColor: _iconColorForOutcome(outcome),
          selectedBorderColor: _borderColorForOutcome(outcome),
          selectedBackgroundColor: _backgroundColorForOutcome(outcome),
          onTap: () => _toggleOutcome(outcome, isSelected),
        );
      }).toList(),
    );
  }

  void _setOperationalSuccess(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _operationalSuccess = value);
  }

  void _toggleOutcome(String outcome, bool isSelected) {
    HapticFeedback.selectionClick();
    setState(() {
      if (isSelected) {
        _removeOutcome(outcome);
      } else {
        _selectedOutcomes.add(outcome);
      }
    });
  }

  void _removeOutcome(String outcome) {
    final normalizedOutcome = _normalizeQuickCloseLabel(outcome);
    _selectedOutcomes.removeWhere(
      (selected) => _normalizeQuickCloseLabel(selected) == normalizedOutcome,
    );
  }
}
