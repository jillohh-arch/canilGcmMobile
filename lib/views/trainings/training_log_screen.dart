import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:canil_gcm/theme/app_theme.dart';
import '../../models/training_session_model.dart';
import 'package:canil_gcm/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/views/shifts/dynamic_activity_sheet.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudCyan = Color(0xFF00E5FF);

class TrainingLogScreen extends StatefulWidget {
  final String dogId;
  final String dogName;
  const TrainingLogScreen({super.key, required this.dogId, this.dogName = ''});

  @override
  State<TrainingLogScreen> createState() => _TrainingLogScreenState();
}

class _TrainingLogScreenState extends State<TrainingLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(
        context,
        listen: false,
      ).fetchTrainingsForDog(widget.dogId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hudBackground,
      appBar: AppBar(
        backgroundColor: _hudBackground,
        elevation: 0,
        title: Text(
          'EVOLUÇÃO',
          style: GoogleFonts.oxanium(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _TrainingEvolutionTab(dogId: widget.dogId),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DynamicActivitySheet(
              category: 'Treino',
              dogId: widget.dogId,
              dogName: widget.dogName,
            ),
          );
        },
        backgroundColor: _hudCyan,
        child: const Icon(Icons.add_rounded, color: _hudBackground, size: 28),
      ),
    );
  }
}

class _TrainingHudHeader extends StatelessWidget {
  final List<TrainingSessionModel> sessions;

  const _TrainingHudHeader({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final lastSession = sessions.isNotEmpty ? sessions.last : null;
    final lastLabel = lastSession == null
        ? 'Sem sessões registradas'
        : '${lastSession.trainingType} • ${_formatDate(lastSession.date)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18)],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: const Icon(Icons.timeline_rounded, color: _hudCyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAINEL DE EVOLUÇÃO',
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lastLabel,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Text(
              '${sessions.length}',
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

// Training Evolution Tab (Garmin/Apple Fitness style)
class _TrainingEvolutionTab extends StatelessWidget {
  final String dogId;
  const _TrainingEvolutionTab({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);

    if (tVM.isLoading) {
      return const Center(child: CircularProgressIndicator(color: _hudCyan));
    }

    final sessions = tVM.trainings..sort((a, b) => a.date.compareTo(b.date));
    final scentSessions = sessions
        .where((s) => s.trainingType == 'Faro' && s.searchDuration != null)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Performance summary cards
          _TrainingHudHeader(sessions: sessions),
          const SizedBox(height: 14),
          if (sessions.isNotEmpty) _SummaryCards(sessions: sessions),
          const SizedBox(height: 24),

          // Scent search duration chart
          if (scentSessions.length >= 2) ...[
            _ChartSection(
              title: 'TEMPO DE BUSCA — FARO',
              subtitle: 'Duração em segundos por sessão (↓ é melhor)',
              child: _SearchDurationChart(sessions: scentSessions),
            ),
            const SizedBox(height: 24),
          ],

          // Sessions history
          _SectionHeader(label: 'SESSÕES REGISTRADAS', count: sessions.length),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            _EmptyTraining()
          else
            ...sessions.reversed.map((s) => _SessionCard(session: s)),
        ],
      ),
    );
  }
}

// Summary stat cards row
class _SummaryCards extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SummaryCards({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final total = sessions.length;
    final scentCount = sessions.where((s) => s.trainingType == 'Faro').length;
    final durations = sessions
        .where((s) => s.searchDuration != null)
        .map((s) => s.searchDuration!)
        .toList();
    final avgDuration = durations.isEmpty
        ? '--'
        : '${(durations.reduce((a, b) => a + b) / durations.length).round()}s';
    final bestDuration = durations.isEmpty
        ? '--'
        : '${durations.reduce((a, b) => a < b ? a : b)}s';

    return Row(
      children: [
        _MiniStat(
          label: 'Sessões',
          value: '$total',
          icon: Icons.fitness_center_rounded,
          color: AppTheme.amber,
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Faro',
          value: '$scentCount',
          icon: Icons.track_changes_rounded,
          color: const Color(0xFF29B6F6),
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Melhor',
          value: bestDuration,
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF66BB6A),
        ),
        const SizedBox(width: 10),
        _MiniStat(
          label: 'Média',
          value: avgDuration,
          icon: Icons.timer_rounded,
          color: const Color(0xFF7E57C2),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(80), width: 0.8),
          boxShadow: [BoxShadow(color: color.withAlpha(12), blurRadius: 12)],
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.oxanium(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.robotoMono(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Chart section container
class _ChartSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ChartSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(60), width: 0.8),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(14), blurRadius: 14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _hudCyan,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.white30,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// Search Duration Line Chart (fl_chart)
class _SearchDurationChart extends StatelessWidget {
  final List<TrainingSessionModel> sessions;
  const _SearchDurationChart({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final spots = sessions.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.searchDuration!.toDouble());
    }).toList();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) * 0.25;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: (minY - yPad).clamp(0, double.infinity),
          maxY: maxY + yPad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.white10,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (val, meta) => Text(
                  '${val.round()}s',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= sessions.length) {
                    return const SizedBox();
                  }
                  final d = sessions[idx].date;
                  return Text(
                    '${d.day}/${d.month}',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: Colors.white38,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                return LineTooltipItem(
                  '${s.y.round()}s',
                  GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppTheme.amber,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 4,
                      color: AppTheme.amber,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.amber.withAlpha(60),
                    AppTheme.amber.withAlpha(0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Section header
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _hudCyan.withAlpha(210),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.amber.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _hudCyan,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: _hudCyan.withAlpha(55))),
      ],
    );
  }
}

// Session Card
class _SessionCard extends StatefulWidget {
  final TrainingSessionModel session;
  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;

  (IconData, Color) _typeStyle(String type) {
    switch (type) {
      case 'Faro':
        return (Icons.track_changes_rounded, const Color(0xFFFFB300));
      case 'Proteção':
        return (Icons.shield_rounded, const Color(0xFFEF5350));
      case 'Obediência':
        return (Icons.school_rounded, const Color(0xFF42A5F5));
      default:
        return (Icons.fitness_center_rounded, AppTheme.amber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final (icon, color) = _typeStyle(s.trainingType);
    final dateStr =
        '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year}';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1726),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _expanded ? color.withAlpha(210) : color.withAlpha(90),
            width: _expanded ? 1 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(_expanded ? 55 : 22),
              blurRadius: _expanded ? 22 : 12,
              offset: const Offset(0, 8),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withAlpha(_expanded ? 36 : 22),
              const Color(0xFF0B1020),
              const Color(0xFF070B14),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
              decoration: BoxDecoration(
                color: color.withAlpha(38),
                border: Border(bottom: BorderSide(color: color.withAlpha(120))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(210), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: color.withAlpha(65),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withAlpha(35),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: color.withAlpha(140)),
                              ),
                              child: Text(
                                s.trainingType.toUpperCase(),
                                style: GoogleFonts.oxanium(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                            if (s.substanceUsed != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  s.substanceUsed!.toUpperCase(),
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white60,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.location,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateStr,
                        style: GoogleFonts.robotoMono(
                          fontSize: 10,
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (s.searchDuration != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${s.searchDuration}s',
                          style: GoogleFonts.oxanium(
                            fontSize: 16,
                            color: color,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: color.withAlpha(180),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  Container(width: 26, height: 2, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withAlpha(18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _expanded ? 'REGISTRO ABERTO' : 'TOQUE PARA DETALHES',
                    style: GoogleFonts.robotoMono(
                      fontSize: 9,
                      color: _expanded ? color : Colors.white38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s.weather.isNotEmpty)
                      _DetailChip(
                        icon: Icons.cloud_outlined,
                        label: s.weather,
                        color: color,
                      ),
                    if (s.humidity != null)
                      _DetailChip(
                        icon: Icons.water_drop_outlined,
                        label: '${s.humidity!.round()}% umidade',
                        color: color,
                      ),
                    if (s.windDirection != null)
                      _DetailChip(
                        icon: Icons.air,
                        label: 'Vento: ${s.windDirection}',
                        color: color,
                      ),
                    if (s.hidingTime != null)
                      _DetailChip(
                        icon: Icons.timer_outlined,
                        label: 'Ocultação: ${s.hidingTime}',
                        color: color,
                      ),
                  ],
                ),
              ),
              if (s.handlerNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B14).withAlpha(210),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(90)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.notes_rounded,
                          size: 15,
                          color: color.withAlpha(210),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.handlerNotes,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withAlpha(220)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTraining extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(220),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(55)),
          ),
          child: Column(
            children: [
              Icon(Icons.track_changes_rounded, size: 56, color: _hudCyan),
              const SizedBox(height: 12),
              Text(
                'Nenhum treino registrado',
                style: GoogleFonts.oxanium(
                  fontSize: 15,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toque em + para adicionar uma sessão.',
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// New Training Form
class _NewTrainingForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewTrainingForm({required this.dogId, required this.onSaved});

  @override
  State<_NewTrainingForm> createState() => _NewTrainingFormState();
}

class _NewTrainingFormState extends State<_NewTrainingForm> {
  final _formKey = GlobalKey<FormState>();
  String _selectedTrainingType = 'Faro';
  String? _selectedSubstance;

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _weatherController = TextEditingController();
  final TextEditingController _handlerNotesController = TextEditingController();
  final TextEditingController _hidingTimeController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  final TextEditingController _windDirectionController =
      TextEditingController();
  final TextEditingController _searchDurationController =
      TextEditingController();

  final List<String> _trainingTypes = ['Faro', 'Proteção', 'Obediência'];
  final List<String> _substances = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Armas/Munições',
    'Pessoas',
  ];

  @override
  void dispose() {
    _locationController.dispose();
    _weatherController.dispose();
    _handlerNotesController.dispose();
    _hidingTimeController.dispose();
    _humidityController.dispose();
    _windDirectionController.dispose();
    _searchDurationController.dispose();
    super.dispose();
  }

  void _saveTraining() async {
    if (_formKey.currentState!.validate()) {
      final session = TrainingSessionModel(
        dogId: widget.dogId,
        date: DateTime.now(),
        trainingType: _selectedTrainingType,
        substanceUsed: _selectedSubstance,
        location: _locationController.text.trim(),
        weather: _weatherController.text.trim(),
        handlerNotes: _handlerNotesController.text.trim(),
        hidingTime: _hidingTimeController.text.trim().isNotEmpty
            ? _hidingTimeController.text.trim()
            : null,
        humidity: double.tryParse(_humidityController.text.trim()),
        windDirection: _windDirectionController.text.trim().isNotEmpty
            ? _windDirectionController.text.trim()
            : null,
        searchDuration: int.tryParse(_searchDurationController.text.trim()),
      );
      final viewModel = Provider.of<TrainingViewModel>(context, listen: false);
      try {
        await viewModel.addTrainingSession(session);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Treino registrado!'),
              backgroundColor: Colors.green,
            ),
          );
          _locationController.clear();
          _weatherController.clear();
          _handlerNotesController.clear();
          _hidingTimeController.clear();
          _humidityController.clear();
          _windDirectionController.clear();
          _searchDurationController.clear();
          setState(() => _selectedSubstance = null);
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

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white38,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Training type selector
            _sectionLabel('Tipo de Treino'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _trainingTypes.map((type) {
                final isSelected = _selectedTrainingType == type;
                final (icon, color) = _sessionStyle(type);
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedTrainingType = type;
                    if (type != 'Faro') _selectedSubstance = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
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
                          size: 18,
                          color: isSelected ? color : Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
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

            // Substance (Faro only)
            if (_selectedTrainingType == 'Faro') ...[
              _sectionLabel('Substância Procurada'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _substances.map((substance) {
                  final isSelected = _selectedSubstance == substance;
                  return FilterChip(
                    label: Text(substance),
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    backgroundColor: cs.surfaceContainerHighest,
                    selectedColor: AppTheme.amber,
                    selected: isSelected,
                    onSelected: (v) => setState(
                      () => _selectedSubstance = v ? substance : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // Scent fields
            if (_selectedTrainingType == 'Faro') ...[
              _sectionLabel('Métricas de Desempenho'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _searchDurationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duração (segundos)',
                        prefixIcon: Icon(Icons.timer_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hidingTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Ocultação (ex: 15min)',
                        prefixIcon: Icon(Icons.timelapse_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            _sectionLabel('Condições Ambientais'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weatherController,
                    decoration: const InputDecoration(
                      labelText: 'Clima',
                      prefixIcon: Icon(Icons.cloud_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _humidityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Umidade (%)',
                      prefixIcon: Icon(Icons.water_drop_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _windDirectionController,
                    decoration: const InputDecoration(
                      labelText: 'Dir. Vento',
                      prefixIcon: Icon(Icons.air),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel('Notas do Condutor'),
            TextFormField(
              controller: _handlerNotesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comportamento, detalhes, evolução...',
                alignLabelWithHint: true,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Adicione ao menos uma nota' : null,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: Consumer<TrainingViewModel>(
                builder: (context, viewModel, child) {
                  final (_, color) = _sessionStyle(_selectedTrainingType);
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
                        : const Icon(Icons.save_rounded, size: 22),
                    label: Text(
                      viewModel.isLoading ? 'SALVANDO...' : 'SALVAR TREINO',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: viewModel.isLoading ? null : _saveTraining,
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

  (IconData, Color) _sessionStyle(String type) {
    switch (type) {
      case 'Faro':
        return (Icons.track_changes_rounded, const Color(0xFFFFB300));
      case 'Proteção':
        return (Icons.shield_rounded, const Color(0xFFEF5350));
      case 'Obediência':
        return (Icons.school_rounded, const Color(0xFF42A5F5));
      default:
        return (Icons.fitness_center_rounded, AppTheme.amber);
    }
  }
}
