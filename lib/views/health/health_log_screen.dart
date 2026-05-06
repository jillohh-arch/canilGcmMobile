import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/theme/app_theme.dart';
import 'package:canil_gcm/models/health_log_model.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';

class HealthLogScreen extends StatefulWidget {
  final String dogId;
  const HealthLogScreen({super.key, required this.dogId});

  @override
  State<HealthLogScreen> createState() => _HealthLogScreenState();
}

class _HealthLogScreenState extends State<HealthLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HealthViewModel>(
        context,
        listen: false,
      ).fetchHealthLogsForDog(widget.dogId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Prontuário Médico',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.amber,
          labelColor: AppTheme.amber,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.timeline_rounded), text: 'Histórico'),
            Tab(
              icon: Icon(Icons.add_circle_outline_rounded),
              text: 'Novo Registro',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _HealthTimeline(dogId: widget.dogId),
          _NewHealthLogForm(
            dogId: widget.dogId,
            onSaved: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }
}

// ── Health Timeline (Apple Health style) ──────────────────────────────────────
class _HealthTimeline extends StatefulWidget {
  final String dogId;
  const _HealthTimeline({required this.dogId});

  @override
  State<_HealthTimeline> createState() => _HealthTimelineState();
}

class _HealthTimelineState extends State<_HealthTimeline> {
  String _filter = 'Todos';
  final _filters = ['Todos', 'Vacina', 'Consulta', 'Exame', 'Medicação'];

  @override
  Widget build(BuildContext context) {
    final hVM = Provider.of<HealthViewModel>(context);
    final logs =
        hVM.healthLogs
            .where((l) => _filter == 'Todos' || l.logType == _filter)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: [
        // Filter chips
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _filters.map((f) {
              final isSelected = _filter == f;
              final (_, color) = _iconAndColor(f == 'Todos' ? 'Consulta' : f);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (f != 'Todos') ...[
                        Icon(
                          _logIcon(f),
                          size: 13,
                          color: isSelected ? color : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(f),
                    ],
                  ),
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : Colors.white70,
                  ),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  selectedColor: color.withAlpha(40),
                  side: BorderSide(color: isSelected ? color : Colors.white12),
                  checkmarkColor: color,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              );
            }).toList(),
          ),
        ),

        // Timeline list
        Expanded(
          child: hVM.isLoading
              ? const Center(child: CircularProgressIndicator())
              : logs.isEmpty
              ? _EmptyHealth(filter: _filter)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final isLast = i == logs.length - 1;
                    return _HealthTimelineItem(log: log, isLast: isLast);
                  },
                ),
        ),
      ],
    );
  }
}

class _HealthTimelineItem extends StatefulWidget {
  final HealthLogModel log;
  final bool isLast;
  const _HealthTimelineItem({required this.log, required this.isLast});

  @override
  State<_HealthTimelineItem> createState() => _HealthTimelineItemState();
}

class _HealthTimelineItemState extends State<_HealthTimelineItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final (icon, color) = _iconAndColor(log.logType);
    final dateStr =
        '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line + Dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(30),
                    border: Border.all(color: color.withAlpha(150), width: 1.5),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Card
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: EdgeInsets.only(bottom: widget.isLast ? 0 : 14),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(_expanded ? 15 : 8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _expanded ? color.withAlpha(80) : Colors.white10,
                    width: _expanded ? 1 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Log type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            log.logType.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                    if (log.vaccines.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        log.vaccines.join(' · '),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                    // Expanded details
                    if (_expanded) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 6),
                      if (log.weight != null)
                        _DetailRow(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Peso',
                          value: '${log.weight!.toStringAsFixed(1)} kg',
                          color: color,
                        ),
                      if (log.healthObservations.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _DetailRow(
                          icon: Icons.notes_rounded,
                          label: 'Observações',
                          value: log.healthObservations,
                          color: color,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color.withAlpha(180)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHealth extends StatelessWidget {
  final String filter;
  const _EmptyHealth({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 56,
            color: Colors.white12,
          ),
          const SizedBox(height: 12),
          Text(
            filter == 'Todos'
                ? 'Nenhum registro médico'
                : 'Sem registros de $filter',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque em "Novo Registro" para adicionar',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ── New Log Form ──────────────────────────────────────────────────────────────
class _NewHealthLogForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewHealthLogForm({required this.dogId, required this.onSaved});

  @override
  State<_NewHealthLogForm> createState() => _NewHealthLogFormState();
}

class _NewHealthLogFormState extends State<_NewHealthLogForm> {
  final _formKey = GlobalKey<FormState>();
  String _selectedLogType = 'Consulta';
  final List<String> _logTypes = ['Consulta', 'Vacina', 'Exame', 'Medicação'];
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _observationsController = TextEditingController();
  final TextEditingController _vaccineNameController = TextEditingController();

  @override
  void dispose() {
    _weightController.dispose();
    _observationsController.dispose();
    _vaccineNameController.dispose();
    super.dispose();
  }

  void _saveHealthLog() async {
    if (_formKey.currentState!.validate()) {
      final log = HealthLogModel(
        dogId: widget.dogId,
        date: DateTime.now(),
        logType: _selectedLogType,
        weight: double.tryParse(
          _weightController.text.trim().replaceAll(',', '.'),
        ),
        vaccines:
            _selectedLogType == 'Vacina' &&
                _vaccineNameController.text.trim().isNotEmpty
            ? [_vaccineNameController.text.trim()]
            : [],
        healthObservations: _observationsController.text.trim(),
      );
      final viewModel = Provider.of<HealthViewModel>(context, listen: false);
      try {
        await viewModel.addHealthLog(log);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registro médico salvo!'),
              backgroundColor: Colors.green,
            ),
          );
          _weightController.clear();
          _observationsController.clear();
          _vaccineNameController.clear();
          widget.onSaved();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (_, selectedColor) = _iconAndColor(_selectedLogType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type selector
            _SectionLabel(label: 'Tipo de Registro'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _logTypes.map((type) {
                final isSelected = _selectedLogType == type;
                final (icon, color) = _iconAndColor(type);
                return GestureDetector(
                  onTap: () => setState(() => _selectedLogType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withAlpha(40)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? color : Colors.white12,
                        width: isSelected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: isSelected ? color : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? color : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            if (_selectedLogType == 'Vacina') ...[
              _SectionLabel(label: 'Nome da Vacina'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vaccineNameController,
                decoration: const InputDecoration(
                  labelText: 'Ex: V10, Antirrábica, Giardíase...',
                  prefixIcon: Icon(Icons.vaccines_rounded),
                ),
                validator: (val) => val == null || val.isEmpty
                    ? 'Informe o nome da vacina'
                    : null,
              ),
              const SizedBox(height: 20),
            ],

            _SectionLabel(label: 'Peso Atual'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ex: 28.5 kg',
                prefixIcon: Icon(Icons.monitor_weight_outlined),
              ),
            ),
            const SizedBox(height: 20),

            _SectionLabel(label: 'Observações Clínicas'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _observationsController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Sintomas, dosagem, histórico...',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Adicione ao menos uma observação'
                  : null,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: Consumer<HealthViewModel>(
                builder: (context, viewModel, child) {
                  return ElevatedButton.icon(
                    icon: viewModel.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(_logIcon(_selectedLogType), size: 22),
                    label: Text(
                      viewModel.isLoading ? 'SALVANDO...' : 'SALVAR PRONTUÁRIO',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: viewModel.isLoading ? null : _saveHealthLog,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Colors.white70,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────
(IconData, Color) _iconAndColor(String logType) {
  switch (logType) {
    case 'Vacina':
      return (Icons.vaccines_rounded, const Color(0xFFEF5350));
    case 'Consulta':
      return (Icons.local_hospital_rounded, const Color(0xFF66BB6A));
    case 'Exame':
      return (Icons.biotech_rounded, const Color(0xFF7E57C2));
    case 'Medicação':
      return (Icons.medication_rounded, const Color(0xFFFF7043));
    case 'Banho':
      return (Icons.water_drop_rounded, const Color(0xFF29B6F6));
    default:
      return (Icons.medical_services_rounded, const Color(0xFFEF5350));
  }
}

IconData _logIcon(String logType) => _iconAndColor(logType).$1;
