import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import '../widgets/occurrence_nature_search.dart';

class IncidentFormScreen extends StatefulWidget {
  final String dogId;
  const IncidentFormScreen({super.key, required this.dogId});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchIncidentsForDog(widget.dogId);
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
          'Ocorrências',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4ECDE4),
          labelColor: const Color(0xFF4ECDE4),
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
            Tab(icon: Icon(Icons.feed_rounded), text: 'Feed'),
            Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Nova'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _IncidentFeed(dogId: widget.dogId),
          _NewIncidentForm(
            dogId: widget.dogId,
            onSaved: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }
}

// Incident Feed (estilo feed/logística) --------------------------------------
class _IncidentFeed extends StatelessWidget {
  final String dogId;
  const _IncidentFeed({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final iVM = Provider.of<IncidentViewModel>(context);

    if (iVM.isLoading) return const Center(child: CircularProgressIndicator());

    final incidents = [...iVM.incidents]
      ..sort((a, b) => b.date.compareTo(a.date));

    if (incidents.isEmpty) {
      return Center(
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
            const SizedBox(height: 4),
            Text(
              'Toque em "Nova" para registrar',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withAlpha(40),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: incidents.length,
      itemBuilder: (context, i) => _IncidentFeedCard(incident: incidents[i]),
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

  Color _resultColor(String result) {
    final r = result.toLowerCase();
    if (r.contains('êxito') ||
        r.contains('exito') ||
        r.contains('sucesso') ||
        r.contains('localiz')) {
      return AppTheme.statusActive;
    }
    if (r.contains('falso') || r.contains('negativo')) {
      return AppTheme.statusLeave;
    }
    if (r.contains('cancel')) {
      return AppTheme.statusAlert;
    }
    return const Color(0xFF4ECDE4);
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'Busca de Entorpecentes':
        return Icons.track_changes_rounded;
      case 'Apoio à Viatura':
        return Icons.local_police_rounded;
      case 'Varredura de Local':
        return Icons.radar_rounded;
      case 'Busca de Pessoa':
        return Icons.person_search_rounded;
      case 'Outros':
        return Icons.report_gmailerrorred_rounded;
      default:
        return Icons.report_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final cs = Theme.of(context).colorScheme;
    final rColor = _resultColor(inc.displayResult);
    final now = DateTime.now();
    final diff = now.difference(inc.date);
    final timeAgo = diff.inDays > 0
        ? '${diff.inDays}d atrás'
        : diff.inHours > 0
        ? '${diff.inHours}h atrás'
        : 'Agora';
    final dateStr =
        '${inc.date.day.toString().padLeft(2, '0')}/${inc.date.month.toString().padLeft(2, '0')}/${inc.date.year} · $timeAgo';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: rColor, width: 3),
            top: BorderSide(color: cs.outlineVariant, width: 0.5),
            right: BorderSide(color: cs.outlineVariant, width: 0.5),
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
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
                    child: Icon(_typeIcon(inc.type), size: 18, color: rColor),
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
                          inc.displayResult,
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

              // Location tag
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.outlineVariant, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 11,
                          color: const Color(0xFF4ECDE4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          inc.location,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Handler tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.outlineVariant, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 11,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'RA ${inc.handlerId}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Timestamp
              Text(
                dateStr,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.white30,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Expanded: Description
              if (_expanded && inc.description.isNotEmpty) ...[
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
                      Row(
                        children: [
                          Icon(
                            Icons.description_rounded,
                            size: 12,
                            color: const Color(0xFF4ECDE4),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'RELATÓRIO',
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF4ECDE4),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
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

// Novo formulário de ocorrência ----------------------------------------------
class _NewIncidentForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewIncidentForm({required this.dogId, required this.onSaved});

  @override
  State<_NewIncidentForm> createState() => _NewIncidentFormState();
}

class _NewIncidentFormState extends State<_NewIncidentForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _natureController = TextEditingController();
  final FocusNode _natureFocus = FocusNode();
  String? _selectedNatureCode;
  String _selectedNatureName = '';

  @override
  void dispose() {
    _natureController.dispose();
    _natureFocus.dispose();
    super.dispose();
  }

  void _startIncident() async {
    if (!_formKey.currentState!.validate()) return;

    // Inicia com os dados minimos da triagem rapida
    final nature = _selectedNatureName.isNotEmpty
        ? _selectedNatureName
        : 'Ocorrência Geral';

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final currentRa =
        HandlerIdentityService.raFromUser(authVM.user) ?? '000000';
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final userModel = userVM.users.cast<dynamic>().firstWhere(
      (u) => u?.ra == currentRa,
      orElse: () => null,
    );
    final authorName =
        userModel?.callsign?.toString() ??
        authVM.user?.displayName ??
        currentRa;

    final viewModel = Provider.of<IncidentViewModel>(context, listen: false);
    final openIncident = await viewModel.findOpenIncident(dogId: widget.dogId);
    if (openIncident != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Já existe uma ocorrência em andamento para este K9. Conclua ou cancele-a primeiro.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final incident = Incident(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dogId: widget.dogId,
      handlerId: currentRa,
      date: DateTime.now(),
      location: 'Local atual (GPS Automático)', // Será enriquecido no console
      description: 'Ocorrência iniciada rapidamente.',
      result: 'Pendente',
      type: nature,
      extraFields:
          _selectedNatureCode != null && _selectedNatureCode!.isNotEmpty
          ? {'naturezaCodigo': _selectedNatureCode}
          : null,
      status: 'Em andamento',
      progressUpdates: [
        IncidentProgressUpdate(
          title: 'Ocorrência Iniciada',
          description: 'Natureza: $nature',
          timestamp: DateTime.now(),
          location: 'Local atual',
          authorId: currentRa,
          authorName: authorName,
        ),
      ],
    );

    try {
      await viewModel.saveIncident(incident);
      if (mounted) {
        HapticFeedback.heavyImpact();
        _natureController.clear();
        setState(() {
          _selectedNatureCode = null;
          _selectedNatureName = '';
        });
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

  @override
  Widget build(BuildContext context) {
    final dogVM = Provider.of<DogViewModel>(context);
    final dog = dogVM.dogs.cast<dynamic>().firstWhere(
      (d) => d.id == widget.dogId,
      orElse: () => null,
    );
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _TacticalGridPainter())),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Dog Avatar
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00E5FF),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                    image: dog?.profileImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(dog!.profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: const Color(0xFF1A2328),
                  ),
                  child: dog?.profileImageUrl == null
                      ? const Icon(Icons.pets, size: 60, color: Colors.white30)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  (dog?.name ?? 'K9').toUpperCase(),
                  style: GoogleFonts.oxanium(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00F5A0),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0xFF00F5A0), blurRadius: 8),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TURNO ATIVO',
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF00F5A0),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Location & Time Cards
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1220),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 14,
                                  color: Color(0xFF4ECDE4),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'LOCAL ATUAL',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4ECDE4),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Obtendo localização GPS...',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1220),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: Color(0xFF4ECDE4),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'HORA ATUAL',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4ECDE4),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              timeStr,
                              style: GoogleFonts.oxanium(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateStr,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Natureza
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'NATUREZA DA OCORRÊNCIA',
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OccurrenceNatureSearch(
                  controller: _natureController,
                  focusNode: _natureFocus,
                  natures: OccurrenceNatureSeed
                      .items, // Uses global static seed for now
                  panelColor: const Color(0xFF0B1220),
                  accent: const Color(0xFF00E5FF),
                  onSelected: (nature) {
                    setState(() {
                      _selectedNatureCode = nature.code;
                      _selectedNatureName = nature.name;
                    });
                  },
                  onChanged: (val) {
                    _selectedNatureName = val;
                  },
                  fieldBuilder: (context, controller, focusNode, onChanged) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ex: Busca de Entorpecentes',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.white24,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.radar_rounded,
                          color: Color(0xFF00E5FF),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B1220),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Start Button
                Consumer<IncidentViewModel>(
                  builder: (context, vm, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: vm.isLoading ? null : _startIncident,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: const Color(0xFF070B14),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF00E5FF,
                                ).withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: vm.isLoading
                                ? const CircularProgressIndicator(
                                    color: Color(0xFF070B14),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'INICIAR OCORRÊNCIA',
                                        style: GoogleFonts.oxanium(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TacticalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4ECDE4).withValues(alpha: 0.025)
      ..strokeWidth = 0.5;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
