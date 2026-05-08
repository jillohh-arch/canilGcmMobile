part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidents on _DailyTimelineScreenState {
  // Conteúdo da aba de ocorrências
  Widget _buildOccurrencesTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildOpenIncidentsSection(dogId),
          _buildTimelineList(dogId, filterType: 'Ocorrência'),
        ],
      ),
    );
  }

  // Mostra ocorrências abertas para retomada rápida.
  Widget _buildOpenIncidentsSection(String dogId) {
    final iVM = Provider.of<IncidentViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    final openIncidents =
        iVM.incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withAlpha(28),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withAlpha(90),
                  ),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: Color(0xFFFBBF24),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OCORRÊNCIAS EM ANDAMENTO',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${openIncidents.length} caso(s) aberto(s) para continuidade',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...openIncidents.map(
            (incident) => _buildOpenIncidentCard(
              dogId: dogId,
              dogName: dogName,
              incident: incident,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenIncidentCard({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) {
    final accent = const Color(0xFFFBBF24);
    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last
        : null;
    final statusStyle = _resolveIncidentStatusBadgeStyle(incident.status);
    final resultLabel = incident.displayResult.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (incident.type ?? 'Ocorrência').toUpperCase(),
                      style: GoogleFonts.inter(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      incident.location,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildIncidentBadge(
                          label: incident.status.toUpperCase(),
                          style: statusStyle,
                        ),
                        if (resultLabel.isNotEmpty &&
                            resultLabel.toLowerCase() !=
                                incident.status.toLowerCase())
                          _buildIncidentBadge(
                            label: resultLabel,
                            style: _resolveIncidentOutcomeBadgeStyle(
                              resultLabel,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(70)),
                ),
                child: Icon(Icons.radar_rounded, color: accent, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildOpenIncidentStat(
                icon: Icons.schedule_rounded,
                label: 'Aberta',
                value: _formatIncidentRelative(incident.startedAt),
              ),
              _buildOpenIncidentStat(
                icon: Icons.update_rounded,
                label: 'Atualizada',
                value: _formatIncidentTimestamp(incident.updatedAt),
              ),
              if (incident.outcomes.isNotEmpty)
                _buildOpenIncidentStat(
                  icon: Icons.fact_check_rounded,
                  label: 'Resultados',
                  value: '${incident.outcomes.length} marcados',
                ),
            ],
          ),
          if (incident.outcomes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: incident.outcomes
                  .map(
                    (outcome) => _buildIncidentBadge(
                      label: outcome,
                      style: _resolveIncidentOutcomeBadgeStyle(outcome),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (latestUpdate != null) ...[
            const SizedBox(height: 12),
            _buildIncidentLatestUpdateCard(
              incident: incident,
              latestUpdate: latestUpdate,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showUnifiedUpdateSheet(
                    incident: incident,
                    dogId: dogId,
                    dogName: dogName,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(
                    'Atualizar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showQuickCloseIncidentSheet(
                    dogId: dogId,
                    dogName: dogName,
                    incident: incident,
                  ),
                  icon: const Icon(Icons.task_alt_rounded, size: 16),
                  label: Text(
                    'Encerrar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpenIncidentStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentLatestUpdateCard({
    required Incident incident,
    required IncidentProgressUpdate latestUpdate,
  }) {
    final progressStyle = _resolveIncidentProgressStyle(
      latestUpdate.title,
      latestUpdate.description,
    );
    final location = (latestUpdate.location ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progressStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: progressStyle.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: progressStyle.iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              progressStyle.icon,
              size: 16,
              color: progressStyle.iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestUpdate.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: progressStyle.titleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestUpdate.description.isNotEmpty
                      ? latestUpdate.description
                      : incident.description,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildIncidentMetaPill(
                      icon: Icons.schedule_rounded,
                      label: _formatIncidentTimestamp(latestUpdate.timestamp),
                    ),
                    if (location.isNotEmpty)
                      _buildIncidentMetaPill(
                        icon: Icons.place_rounded,
                        label: location,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentBadge({
    required String label,
    required _IncidentBadgeStyle style,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: style.textColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentMetaPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentQuickSheetHeader({
    required String title,
    required Incident incident,
    required _IncidentBadgeStyle badgeStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeStyle.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeStyle.borderColor),
              ),
              child: Icon(
                badgeStyle.icon,
                color: badgeStyle.iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildIncidentBadge(
              label: incident.status.toUpperCase(),
              style: _resolveIncidentStatusBadgeStyle(incident.status),
            ),
            _buildIncidentMetaPill(
              icon: Icons.schedule_rounded,
              label: _formatIncidentTimestamp(incident.updatedAt),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIncidentSelectionChip({
    required String label,
    required bool selected,
    required _IncidentBadgeStyle style,
    required VoidCallback onTap,
  }) {
    final effectiveStyle = selected
        ? style
        : _IncidentBadgeStyle(
            icon: style.icon,
            iconColor: Colors.white54,
            textColor: Colors.white70,
            backgroundColor: Colors.white.withAlpha(6),
            borderColor: Colors.white12,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effectiveStyle.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: effectiveStyle.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              effectiveStyle.icon,
              size: 13,
              color: effectiveStyle.iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: effectiveStyle.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
