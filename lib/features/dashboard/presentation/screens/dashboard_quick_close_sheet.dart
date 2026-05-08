part of 'dashboard_screen.dart';

class _QuickCloseIncidentSheet extends StatefulWidget {
  final Incident incident;

  const _QuickCloseIncidentSheet({required this.incident});

  @override
  State<_QuickCloseIncidentSheet> createState() =>
      _QuickCloseIncidentSheetState();
}

class _QuickCloseIncidentSheetState extends State<_QuickCloseIncidentSheet> {
  late final TextEditingController _noteController;
  late final Set<String> _selectedOutcomes;
  late bool _operationalSuccess;

  Incident get _incident => widget.incident;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _selectedOutcomes = _incident.outcomes.isNotEmpty
        ? <String>{..._incident.outcomes}
        : _quickCloseDefaultOutcomesForSubtype(_incident.type);
    _operationalSuccess = _incident.operationalSuccess ?? true;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161618),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _QuickCloseHeader(incident: _incident),
              const SizedBox(height: 18),
              _QuickCloseSectionLabel('DESFECHO OPERACIONAL'),
              const SizedBox(height: 10),
              _buildOperationalSuccessChips(),
              const SizedBox(height: 18),
              _QuickCloseSectionLabel('RESULTADOS FINAIS'),
              const SizedBox(height: 10),
              _buildOutcomeChips(),
              const SizedBox(height: 18),
              _buildNoteField(),
              const SizedBox(height: 18),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

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
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _operationalSuccess = true);
          },
        ),
        _QuickIncidentChip(
          label: 'Sem êxito',
          selected: !_operationalSuccess,
          icon: Icons.cancel_rounded,
          selectedTextColor: const Color(0xFFFCA5A5),
          selectedIconColor: const Color(0xFFF87171),
          selectedBorderColor: const Color(0x33F87171),
          selectedBackgroundColor: const Color(0x14F87171),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _operationalSuccess = false);
          },
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
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (isSelected) {
                _removeOutcome(outcome);
              } else {
                _selectedOutcomes.add(outcome);
              }
            });
          },
        );
      }).toList(),
    );
  }

  void _removeOutcome(String outcome) {
    final normalizedOutcome = _normalizeQuickCloseLabel(outcome);
    _selectedOutcomes.removeWhere(
      (selected) => _normalizeQuickCloseLabel(selected) == normalizedOutcome,
    );
  }

  Widget _buildNoteField() {
    return TextField(
      controller: _noteController,
      maxLines: 3,
      minLines: 2,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Atualização final',
        labelStyle: GoogleFonts.inter(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withAlpha(6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _hudAmber),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _closeIncident,
            style: FilledButton.styleFrom(
              backgroundColor: _hudAmber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Encerrar agora',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _closeIncident() async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final now = DateTime.now();
    final updates = List<IncidentProgressUpdate>.from(
      _incident.progressUpdates,
    );
    final note = _noteController.text.trim();

    if (note.isNotEmpty) {
      updates.add(
        IncidentProgressUpdate(
          title: 'Encerramento da ocorrência',
          description: note,
          timestamp: now,
          location: _incident.location,
        ),
      );
    }

    final closedIncident = _incident.copyWith(
      status: 'Concluída',
      operationalSuccess: _operationalSuccess,
      outcomes: _selectedOutcomes.toList(),
      endedAt: now,
      updatedAt: now,
      result: _buildQuickCloseResultSummary(
        selectedOutcomes: _selectedOutcomes,
        operationalSuccess: _operationalSuccess,
      ),
      progressUpdates: updates,
    );

    await incidentVM.updateIncident(closedIncident);
    if (!mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ocorrência encerrada com sucesso.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _QuickCloseHeader extends StatelessWidget {
  final Incident incident;

  const _QuickCloseHeader({required this.incident});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0x144ADE80),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x334ADE80)),
          ),
          child: const Icon(
            Icons.task_alt_rounded,
            color: Color(0xFF4ADE80),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ENCERRAR OCORRÊNCIA',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${incident.type ?? 'Ocorrência'} - ${incident.location}',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickCloseSectionLabel extends StatelessWidget {
  final String label;

  const _QuickCloseSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        color: Colors.white54,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}
