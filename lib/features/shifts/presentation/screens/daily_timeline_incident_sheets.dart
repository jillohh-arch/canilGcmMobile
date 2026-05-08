part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentSheets on _DailyTimelineScreenState {
  Future<void> _showUnifiedUpdateSheet({
    required Incident incident,
    required String dogId,
    required String dogName,
  }) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = <String>{...incident.outcomes};
    final shortcuts = _quickProgressShortcutsForSubtype(incident.type);
    String? selectedShortcut;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
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
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF4ECDE4).withAlpha(60),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4ECDE4).withAlpha(15),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ECDE4).withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF4ECDE4).withAlpha(80),
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color: Color(0xFF4ECDE4),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ATUALIZAR OCORRÊNCIA',
                                    style: GoogleFonts.oxanium(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    incident.location,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.white38,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (shortcuts.isNotEmpty) ...[
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
                            children: shortcuts.map((s) {
                              final isSelected = selectedShortcut == s.title;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() {
                                    if (isSelected) {
                                      selectedShortcut = null;
                                      noteController.clear();
                                    } else {
                                      selectedShortcut = s.title;
                                      noteController.text = s.template;
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF4ECDE4).withAlpha(25)
                                        : Colors.white.withAlpha(6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(
                                              0xFF4ECDE4,
                                            ).withAlpha(100)
                                          : Colors.white10,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    s.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF4ECDE4)
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 18),
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
                          children:
                              _quickCloseOutcomeOptionsForSubtype(
                                incident.type,
                              ).map((outcome) {
                                final isSelected = selectedOutcomes.contains(
                                  outcome,
                                );
                                return _buildIncidentSelectionChip(
                                  label: outcome,
                                  selected: isSelected,
                                  style: _resolveIncidentOutcomeBadgeStyle(
                                    outcome,
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setModalState(() {
                                      if (isSelected) {
                                        selectedOutcomes.remove(outcome);
                                      } else {
                                        selectedOutcomes.add(outcome);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                        ),

                        const SizedBox(height: 18),
                        TextField(
                          controller: noteController,
                          maxLines: 3,
                          minLines: 2,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Descreva o andamento da ocorrência...',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141C20),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF1D2C33),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF4ECDE4),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white54,
                                  side: const BorderSide(color: Colors.white10),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Cancelar',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final note = noteController.text.trim();
                                  if (selectedShortcut == null &&
                                      note.isEmpty &&
                                      selectedOutcomes.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Selecione uma etapa, desfecho ou descreva o andamento.',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  final now = DateTime.now();
                                  final title =
                                      selectedShortcut ??
                                      (selectedOutcomes.isNotEmpty
                                          ? selectedOutcomes.first
                                          : 'Atualização operacional');
                                  final description = note.isNotEmpty
                                      ? note
                                      : selectedOutcomes.isNotEmpty
                                      ? 'Desfechos: ${selectedOutcomes.join(', ')}.'
                                      : 'Andamento registrado.';

                                  final updates =
                                      List<IncidentProgressUpdate>.from(
                                        incident.progressUpdates,
                                      )..add(
                                        _authoredIncidentUpdate(
                                          title: title,
                                          description: description,
                                          timestamp: now,
                                          location: incident.location,
                                        ),
                                      );

                                  final updated = incident.copyWith(
                                    status: 'Em andamento',
                                    outcomes: selectedOutcomes.toList(),
                                    updatedAt: now,
                                    result: selectedOutcomes.isNotEmpty
                                        ? selectedOutcomes.first
                                        : incident.result,
                                    progressUpdates: updates,
                                  );

                                  await incidentVM.updateIncident(updated);
                                  if (!mounted) return;
                                  Navigator.of(this.context).pop();
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text('Ocorrência atualizada.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF004E5B),
                                  foregroundColor: const Color(0xFF4ECDE4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    side: const BorderSide(
                                      color: Color(0xFF4ECDE4),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Salvar atualização',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _showQuickCloseIncidentSheet({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = incident.outcomes.isNotEmpty
        ? <String>{...incident.outcomes}
        : _quickCloseDefaultOutcomesForSubtype(incident.type);
    var operationalSuccess = incident.operationalSuccess ?? true;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
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
                        _buildIncidentQuickSheetHeader(
                          title: 'ENCERRAR OCORRÊNCIA',
                          incident: incident,
                          badgeStyle: const _IncidentBadgeStyle(
                            icon: Icons.task_alt_rounded,
                            iconColor: Color(0xFF4ADE80),
                            textColor: Color(0xFF86EFAC),
                            backgroundColor: Color(0x144ADE80),
                            borderColor: Color(0x334ADE80),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'DESFECHO OPERACIONAL',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['Com êxito', 'Sem êxito'].map((option) {
                            final isSelected =
                                operationalSuccess == (option == 'Com êxito');
                            return _buildIncidentSelectionChip(
                              label: option,
                              selected: isSelected,
                              style: option == 'Com êxito'
                                  ? const _IncidentBadgeStyle(
                                      icon: Icons.task_alt_rounded,
                                      iconColor: Color(0xFF4ADE80),
                                      textColor: Color(0xFF86EFAC),
                                      backgroundColor: Color(0x144ADE80),
                                      borderColor: Color(0x334ADE80),
                                    )
                                  : const _IncidentBadgeStyle(
                                      icon: Icons.cancel_rounded,
                                      iconColor: Color(0xFFF87171),
                                      textColor: Color(0xFFFCA5A5),
                                      backgroundColor: Color(0x14F87171),
                                      borderColor: Color(0x33F87171),
                                    ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() {
                                  operationalSuccess = option == 'Com êxito';
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'RESULTADOS FINAIS',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _quickCloseOutcomeOptionsForSubtype(
                                incident.type,
                              ).map((outcome) {
                                final isSelected = selectedOutcomes.contains(
                                  outcome,
                                );
                                return _buildIncidentSelectionChip(
                                  label: outcome,
                                  selected: isSelected,
                                  style: _resolveIncidentOutcomeBadgeStyle(
                                    outcome,
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setModalState(() {
                                      if (isSelected) {
                                        selectedOutcomes.remove(outcome);
                                      } else {
                                        selectedOutcomes.add(outcome);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: noteController,
                          maxLines: 3,
                          minLines: 2,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Atualização final',
                            labelStyle: GoogleFonts.inter(
                              color: Colors.white54,
                            ),
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
                              borderSide: const BorderSide(
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white12),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Cancelar',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final updates =
                                      List<IncidentProgressUpdate>.from(
                                        incident.progressUpdates,
                                      );
                                  final note = noteController.text.trim();

                                  updates.add(
                                    _authoredIncidentUpdate(
                                      title: 'Encerramento da ocorrência',
                                      description: note.isNotEmpty
                                          ? note
                                          : 'Ocorrência encerrada pela equipe.',
                                      timestamp: now,
                                      location: incident.location,
                                    ),
                                  );

                                  final closedIncident = incident.copyWith(
                                    status: 'Concluída',
                                    operationalSuccess: operationalSuccess,
                                    outcomes: selectedOutcomes.toList(),
                                    endedAt: now,
                                    updatedAt: now,
                                    result: _buildQuickCloseResultSummary(
                                      incident: incident,
                                      selectedOutcomes: selectedOutcomes,
                                      operationalSuccess: operationalSuccess,
                                    ),
                                    progressUpdates: updates,
                                  );

                                  await incidentVM.updateIncident(
                                    closedIncident,
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  Navigator.of(this.context).pop();
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Ocorrência encerrada com sucesso.',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFBBF24),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Encerrar',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }
}
