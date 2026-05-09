import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

part 'global_incidents_components.dart';

class GlobalIncidentsScreen extends StatefulWidget {
  const GlobalIncidentsScreen({super.key});

  @override
  State<GlobalIncidentsScreen> createState() => _GlobalIncidentsScreenState();
}

class _GlobalIncidentsScreenState extends State<GlobalIncidentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchAllIncidents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final iVM = Provider.of<IncidentViewModel>(context);

    // Ideally, the IncidentViewModel should fetch all incidents in the K9 Unit.
    // For this prototype, we display what's in memory.
    final incidents = [...iVM.incidents]
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Feed de Ocorrências',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: iVM.isLoading
          ? const Center(child: CircularProgressIndicator())
          : incidents.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.report_off_rounded,
                    size: 56,
                    color: Colors.white.withAlpha(30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhuma ocorrência registrada',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withAlpha(60),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: incidents.length,
              itemBuilder: (context, i) =>
                  _IncidentFeedCard(incident: incidents[i]),
            ),
    );
  }
}

class _IncidentFeedCard extends StatefulWidget {
  final Incident incident;
  const _IncidentFeedCard({required this.incident});

  @override
  State<_IncidentFeedCard> createState() => _IncidentFeedCardState();
}

class _IncidentFeedCardState extends State<_IncidentFeedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final cs = Theme.of(context).colorScheme;
    final rColor = _globalIncidentResultColor(inc.result);
    final now = DateTime.now();
    final diff = now.difference(inc.date);
    final timeAgo = diff.inDays > 0
        ? '${diff.inDays}d atrás'
        : diff.inHours > 0
        ? '${diff.inHours}h atrás'
        : 'Agora';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outlineVariant, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rColor.withAlpha(30),
                      border: Border.all(
                        color: rColor.withAlpha(100),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _globalIncidentTypeIcon(inc.type),
                      size: 18,
                      color: rColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inc.type != null)
                          Text(
                            inc.type!.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: rColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        Text(
                          inc.result,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.white30,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _TagIcon(
                    icon: Icons.location_on_rounded,
                    text: inc.location,
                    color: const Color(0xFF4ECDE4),
                  ),
                  const SizedBox(width: 8),
                  _TagIcon(
                    icon: Icons.badge_outlined,
                    text: 'RA ${inc.handlerId}',
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                timeAgo,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.white30,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (inc.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RELATÓRIO',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF4ECDE4),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        inc.description,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
