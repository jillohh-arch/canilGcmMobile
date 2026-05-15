import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

/// Tela B — Treino de Obediência (Treino Contínuo)
/// Biblioteca de comandos com estágios, foco, ambiente, avaliação
class ObedienceTrainingScreen extends StatefulWidget {
  final Dog dog;

  const ObedienceTrainingScreen({super.key, required this.dog});

  @override
  State<ObedienceTrainingScreen> createState() =>
      _ObedienceTrainingScreenState();
}

class _ObedienceTrainingScreenState extends State<ObedienceTrainingScreen> {
  final _focusController = TextEditingController();
  final _obsController = TextEditingController();

  // Command library organized by category
  static const _commandCategories = <_CommandCategory>[
    _CommandCategory(name: 'OPERACIONAIS', commands: [
      _Command(name: 'Senta', stage: CommandStage.full),
      _Command(name: 'Deita', stage: CommandStage.full),
      _Command(name: 'Fica', stage: CommandStage.full),
      _Command(name: 'Junto', stage: CommandStage.full),
      _Command(name: 'Junto à direita', stage: CommandStage.full),
      _Command(name: 'Vem', stage: CommandStage.full),
      _Command(name: 'Solta', stage: CommandStage.full),
    ]),
    _CommandCategory(name: 'POSTURAIS', commands: [
      _Command(name: 'Levanta', stage: CommandStage.full),
      _Command(name: 'Cumprimenta', stage: CommandStage.dev),
      _Command(name: 'Abraço', stage: CommandStage.intro),
    ]),
    _CommandCategory(name: 'HABILIDADES', commands: [
      _Command(name: 'Jump', stage: CommandStage.partial),
      _Command(name: 'Hop', stage: CommandStage.dev),
      _Command(name: 'Parkour', stage: CommandStage.intro),
    ]),
  ];

  // Environments
  static const _environments = ['Canil', 'Praça', 'Rua', 'Local com distração'];

  // Focus suggestions
  static const _focusSuggestions = [
    'Comandos consolidados',
    'Novos comandos',
    'Com distrações',
    'Rotina',
  ];

  // Ratings
  static const _ratings = ['Ruim', 'Regular', 'Bom', 'Ótimo'];

  final Set<String> _selectedCommands = {};
  String? _selectedEnvironment;
  int? _selectedRating;

  @override
  void dispose() {
    _focusController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _saveSession() async {
    if (_selectedCommands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um comando trabalhado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o desempenho geral'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      date: DateTime.now(),
      trainingType: 'Obediência',
      location: _selectedEnvironment ?? '',
      weather: '',
      handlerNotes: _obsController.text.trim(),
      metadata: {
        'specialty': 'obediencia',
        'mode': 'treino_continuo',
        'commands': _selectedCommands.toList(),
        'commandCount': _selectedCommands.length,
        'environment': _selectedEnvironment,
        'focus': _focusController.text.trim(),
        'rating': _ratings[_selectedRating!],
      },
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addTrainingSession(session);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sessão de obediência salva!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  int get _totalCommands {
    int count = 0;
    for (final cat in _commandCategories) {
      count += cat.commands.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFocusCard(),
                    const SizedBox(height: 16),
                    _buildCommandLibrary(),
                    const SizedBox(height: 16),
                    _buildEnvironmentChips(),
                    const SizedBox(height: 16),
                    _buildRatingRow(),
                    const SizedBox(height: 16),
                    _buildObservations(),
                    const SizedBox(height: 20),
                    _buildRecentSessions(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildCTA(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: Column(
        children: [
          // Top row
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppTheme.textPrimary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TREINO CONTÍNUO',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Obediência',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('🐾', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Dog status card (cyan theme)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withAlpha(50)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A2A30),
                    border: Border.all(color: AppTheme.primary, width: 1.5),
                  ),
                  child: ClipOval(
                    child: widget.dog.profileImageUrl != null && widget.dog.profileImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.dog.profileImageUrl!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Center(
                              child: Text(
                                widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                                style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                                style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                              style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.dog.name,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$_totalCommands COMANDOS NA BIBLIOTECA',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'ATIVO',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(20),
            AppTheme.success.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 FOCO DESTA SESSÃO',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _focusController,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'O que quer trabalhar?',
              hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
              filled: true,
              fillColor: Colors.black.withAlpha(65),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _focusSuggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  _focusController.text = s;
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withAlpha(65)),
                  ),
                  child: Text(
                    s,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandLibrary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('COMANDOS TRABALHADOS'),
            const Spacer(),
            Text(
              'tap pra selecionar',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._commandCategories.map((cat) => _buildCategorySection(cat)),
      ],
    );
  }

  Widget _buildCategorySection(_CommandCategory category) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(
            category.name,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 3.2,
          children: category.commands.map((cmd) {
            final selected = _selectedCommands.contains(cmd.name);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (selected) {
                    _selectedCommands.remove(cmd.name);
                  } else {
                    _selectedCommands.add(cmd.name);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withAlpha(25)
                      : Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary.withAlpha(100)
                        : Colors.white.withAlpha(20),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      cmd.stageIcon,
                      style: TextStyle(
                        fontSize: 14,
                        color: cmd.stageColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cmd.name,
                        style: GoogleFonts.inter(
                          color: selected ? AppTheme.primary : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildEnvironmentChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('AMBIENTE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _environments.map((e) {
            final selected = _selectedEnvironment == e;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedEnvironment = selected ? null : e);
              },
              child: _chip(e, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRatingRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('DESEMPENHO GERAL'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_ratings.length, (i) {
            final selected = _selectedRating == i;
            final isBad = i == 0;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedRating = i);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? (isBad
                            ? AppTheme.error.withAlpha(25)
                            : AppTheme.success.withAlpha(25))
                        : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? (isBad ? AppTheme.error : AppTheme.success)
                          : Colors.white.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _ratings[i],
                      style: GoogleFonts.inter(
                        color: selected
                            ? (isBad ? AppTheme.error : AppTheme.success)
                            : AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildObservations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('OBSERVAÇÕES'),
            const Spacer(),
            Text(
              'opcional · ajustes de estágio?',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _obsController,
          maxLines: 3,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Algum comando precisa subir/baixar de estágio? Notas da sessão...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
            filled: true,
            fillColor: AppTheme.primary.withAlpha(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSessions() {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, __) {
        final recent = vm.trainings
            .where((t) => t.trainingType.toLowerCase().contains('obediência') ||
                t.trainingType.toLowerCase().contains('obediencia'))
            .take(3)
            .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SESSÕES RECENTES',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...recent.map((s) => _recentCard(s)),
          ],
        );
      },
    );
  }

  Widget _recentCard(TrainingSessionModel session) {
    final day = '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}';
    final rating = session.metadata?['rating'] ?? '';
    final cmdCount = session.metadata?['commandCount'] ?? '';
    final env = session.metadata?['environment'] ?? session.location;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              day,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cmdCount comandos · $env',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Obediência',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (rating.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rating.toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppTheme.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCTA() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.2, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '💾 SALVAR SESSÃO',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helpers ---

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _chip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withAlpha(30) : Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.primary : Colors.white.withAlpha(25),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// --- Data models ---

enum CommandStage { full, partial, dev, intro, none }

class _Command {
  final String name;
  final CommandStage stage;

  const _Command({required this.name, required this.stage});

  String get stageIcon {
    switch (stage) {
      case CommandStage.full:
        return '●';
      case CommandStage.partial:
        return '◕';
      case CommandStage.dev:
        return '◑';
      case CommandStage.intro:
        return '◔';
      case CommandStage.none:
        return '○';
    }
  }

  Color get stageColor {
    switch (stage) {
      case CommandStage.full:
        return AppTheme.success;
      case CommandStage.partial:
        return AppTheme.primary;
      case CommandStage.dev:
        return AppTheme.attention;
      case CommandStage.intro:
        return AppTheme.warning;
      case CommandStage.none:
        return AppTheme.textTertiary;
    }
  }
}

class _CommandCategory {
  final String name;
  final List<_Command> commands;

  const _CommandCategory({required this.name, required this.commands});
}
