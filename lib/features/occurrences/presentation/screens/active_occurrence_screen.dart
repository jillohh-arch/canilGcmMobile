import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_context_card.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_finalize_cta.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_quick_grid.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_timeline.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class ActiveOccurrenceScreen extends StatefulWidget {
  final String occurrenceId;

  const ActiveOccurrenceScreen({super.key, required this.occurrenceId});

  @override
  State<ActiveOccurrenceScreen> createState() => _ActiveOccurrenceScreenState();
}

class _ActiveOccurrenceScreenState extends State<ActiveOccurrenceScreen> {
  final _locationService = const LocationResolutionService();
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    final vm = context.read<OccurrenceViewModel>();
    vm.watchEvents(widget.occurrenceId);

    _startedAt = vm.openOccurrence?.startedAt;
    _updateElapsed();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed();
    });
  }

  void _updateElapsed() {
    if (_startedAt == null) {
      final vm = context.read<OccurrenceViewModel>();
      _startedAt = vm.openOccurrence?.startedAt;
    }
    if (_startedAt != null) {
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  String get _durationLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60);
    final s = _elapsed.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    if (m > 0) return '${m}min ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  Future<void> _addQuickEvent(QuickEventItem item) async {
    final vm = context.read<OccurrenceViewModel>();
    final now = DateTime.now();

    // Show immediate feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registrando: ${item.autoTitle}...'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF1A3A4A),
        ),
      );
    }

    double? lat, lng;
    try {
      final loc = await _locationService.currentHighAccuracy();
      lat = loc.point.latitude;
      lng = loc.point.longitude;
    } catch (_) {
      // GPS indisponível — continua sem coordenadas
    }

    final event = OccurrenceEvent(
      id: const Uuid().v4(),
      occurrenceId: widget.occurrenceId,
      category: item.category,
      timestamp: now,
      title: item.autoTitle,
      gpsLat: lat,
      gpsLng: lng,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await vm.addEvent(event);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${item.autoTitle} registrado'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar evento: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _openOtherEventSheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    OccurrenceEventCategory selectedCat = OccurrenceEventCategory.other;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F2027),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Novo Evento',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _SheetTextField(controller: titleCtrl, hint: 'Título do evento'),
              const SizedBox(height: 12),
              _SheetTextField(
                  controller: descCtrl, hint: 'Descrição (opcional)'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OccurrenceEventCategory.values.map((cat) {
                  final selected = cat == selectedCat;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedCat = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withAlpha(40)
                            : Colors.white.withAlpha(8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.white.withAlpha(20),
                        ),
                      ),
                      child: Text(
                        cat.label,
                        style: GoogleFonts.inter(
                          color: selected ? AppTheme.primary : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    Navigator.of(ctx).pop();
                    await _addCustomEvent(
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim().isNotEmpty
                          ? descCtrl.text.trim()
                          : null,
                      category: selectedCat,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Adicionar',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCustomEvent({
    required String title,
    String? description,
    required OccurrenceEventCategory category,
  }) async {
    final vm = context.read<OccurrenceViewModel>();
    final now = DateTime.now();

    double? lat, lng;
    try {
      final loc = await _locationService.currentHighAccuracy();
      lat = loc.point.latitude;
      lng = loc.point.longitude;
    } catch (_) {}

    final event = OccurrenceEvent(
      id: const Uuid().v4(),
      occurrenceId: widget.occurrenceId,
      category: category,
      timestamp: now,
      title: title,
      description: description,
      gpsLat: lat,
      gpsLng: lng,
      createdAt: now,
      updatedAt: now,
    );

    await vm.addEvent(event);
  }

  void _onEventTap(OccurrenceEvent event) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Evento: ${event.title ?? event.category.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onFinalize() {
    final vm = context.read<OccurrenceViewModel>();
    if (vm.events.isEmpty) {
      _showEmptyFinalizeDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finalização será implementada na Tela 2.4'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _translateError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('permission_denied')) {
      return 'Sem permissão para acessar esses dados.';
    }
    if (lower.contains('failed-precondition') || lower.contains('precondition')) {
      return 'Erro de configuração do servidor.';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Sem conexão com o servidor.';
    }
    if (lower.contains('not-found')) {
      return 'Dados não encontrados.';
    }
    return 'Erro ao carregar dados. Tente novamente.';
  }

  void _showEmptyFinalizeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Nenhum evento registrado',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Deseja finalizar a ocorrência sem nenhum evento?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar',
                style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Finalização será implementada na Tela 2.4'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Text('Finalizar',
                style: GoogleFonts.inter(color: const Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OccurrenceViewModel>();
    final dogVM = context.watch<DogViewModel>();
    final authVM = context.watch<AuthViewModel>();
    final userVM = context.watch<UserViewModel>();
    final occ = vm.openOccurrence;

    // Resolve dog name and photo from dogId
    final dogId = occ?.dogId;
    final dogs = dogVM.dogs.where((d) => d.id == dogId);
    final dog = dogs.isNotEmpty ? dogs.first : null;
    final dogName = dog?.name ?? 'K9';
    final dogImageUrl = dog?.profileImageUrl;

    // Resolve handler name and photo from primaryHandlerId (Firebase UID → RA → UserModel)
    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerUser = userVM.findByRa(handlerRa);
    final handlerName = userVM.displayNameFor(
      ra: handlerRa,
      firebaseUser: authVM.user,
    );
    final handlerImageUrl = handlerUser?.photoUrl ?? authVM.user?.photoURL;

    final typeName = occ?.typeName ?? 'Ocorrência';
    final locationAddress = occ?.locationAddress ?? '';
    final startedAtLabel = _startedAt != null
        ? '${_startedAt!.hour.toString().padLeft(2, '0')}:${_startedAt!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(typeName: typeName, onBack: () => Navigator.of(context).pop()),
                  if (vm.error != null)
                    _SyncErrorBanner(
                      onRetry: () {
                        vm.clearError();
                        vm.watchEvents(widget.occurrenceId);
                      },
                    ),
                  const SizedBox(height: 16),
                  ActiveOccurrenceContextCard(
                    typeName: typeName,
                    dogName: dogName,
                    dogImageUrl: dogImageUrl,
                    handlerName: handlerName,
                    handlerImageUrl: handlerImageUrl,
                    locationAddress: locationAddress,
                    startedAtLabel: startedAtLabel,
                    durationLabel: _durationLabel,
                    eventCount: vm.events.length,
                  ),
                  const SizedBox(height: 24),
                  ActiveOccurrenceQuickGrid(
                    onQuickEvent: _addQuickEvent,
                    onOtherEvent: _openOtherEventSheet,
                  ),
                  const SizedBox(height: 24),
                  ActiveOccurrenceTimeline(
                    events: vm.events,
                    onEventTap: _onEventTap,
                    handlerName: handlerName,
                    locationLabel: locationAddress.isNotEmpty ? locationAddress : null,
                    errorMessage: vm.error != null ? _translateError(vm.error!) : null,
                    onRetry: vm.error != null
                        ? () {
                            vm.clearError();
                            vm.watchEvents(widget.occurrenceId);
                          }
                        : null,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ActiveOccurrenceFinalizeCta(onFinalize: _onFinalize),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String typeName;
  final VoidCallback onBack;

  const _Header({required this.typeName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onBack();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OCORRÊNCIA EM ANDAMENTO',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _SheetTextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withAlpha(8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _SyncErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _SyncErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE53935).withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFE53935),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sincronização com falha. Toque para tentar novamente.',
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF4DD0E1),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
