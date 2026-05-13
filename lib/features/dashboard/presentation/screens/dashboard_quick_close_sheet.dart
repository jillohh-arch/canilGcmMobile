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
    return _QuickCloseSheetFrame(
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
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
    );
  }
}
