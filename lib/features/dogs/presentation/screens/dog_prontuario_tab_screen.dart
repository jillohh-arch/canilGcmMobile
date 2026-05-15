import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/data/dog_profile_service.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'dog_prontuario_ficha.dart';
part 'dog_prontuario_status_medico.dart';
part 'dog_prontuario_especialidades.dart';
part 'dog_prontuario_peso.dart';
part 'dog_prontuario_vacinas.dart';
part 'dog_prontuario_documentos.dart';
part 'dog_prontuario_eventos.dart';

/// Cores do tema
final _bgColor = AppTheme.background;
const _cyanAccent = Color(0xFF4DD0E1);
const _greenAccent = Color(0xFF2ECC71);
const _yellowAccent = Color(0xFFF1C40F);
const _redAccent = Color(0xFFE74C3C);
const _textPrimary = Colors.white;
const _textSecondary = Color(0xFFB0C4CC);
const _textMuted = Color(0xFF7A8A92);
const _dimMuted = Color(0xFF5A7280);

/// Tela de prontuário do cão — funciona como tab no menu inferior.
class DogProntuarioTabScreen extends StatefulWidget {
  const DogProntuarioTabScreen({super.key});

  @override
  State<DogProntuarioTabScreen> createState() => _DogProntuarioTabScreenState();
}

class _DogProntuarioTabScreenState extends State<DogProntuarioTabScreen> {
  final DogProfileService _service = DogProfileService();

  List<VaccineRecord> _vaccines = [];
  List<DogAptitude> _aptitudes = [];
  List<RecentRecord> _recentRecords = [];
  List<DogDocument> _documents = [];
  String? _handlerName;
  bool _loading = true;
  String? _lastDogId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogId = shiftVM.activeDogId;
    if (dogId == null) return;
    if (_lastDogId == dogId && !_loading) return;
    _lastDogId = dogId;

    // Carrega health logs
    Provider.of<HealthViewModel>(context, listen: false)
        .fetchHealthLogsForDog(dogId);

    _fetchProfileData(dogId, dogVM);
  }

  Future<void> _fetchProfileData(String dogId, DogViewModel dogVM) async {
    setState(() => _loading = true);

    List<VaccineRecord> vaccines = [];
    List<DogAptitude> aptitudes = [];
    List<RecentRecord> recentRecords = [];
    List<DogDocument> documents = [];
    String? handlerName;

    try { vaccines = await _service.getVaccines(dogId); } catch (_) {}
    try { aptitudes = await _service.getAptitudes(dogId); } catch (_) {}
    try { recentRecords = await _service.getRecentRecords(dogId, limit: 5); } catch (_) {}
    try { documents = await _service.getDocuments(dogId); } catch (_) {}
    try { handlerName = _resolveHandlerName(dogId, dogVM); } catch (_) {}

    if (!mounted) return;
    setState(() {
      _vaccines = vaccines;
      _aptitudes = aptitudes;
      _recentRecords = recentRecords;
      _documents = documents;
      _handlerName = handlerName;
      _loading = false;
    });
  }

  String? _resolveHandlerName(String dogId, DogViewModel dogVM) {
    final dog = dogVM.dogs.firstWhere((d) => d.id == dogId, orElse: () => dogVM.dogs.first);
    if (dog.conductorRa == null) return null;
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final name = userVM.displayNameFor(ra: dog.conductorRa);
    return name != 'Condutor' ? name : null;
  }

  Dog? _getActiveDog() {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final dogId = shiftVM.activeDogId;
    if (dogId == null) return null;

    // Recarrega se dogId mudou
    if (_lastDogId != dogId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    }

    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dog = _getActiveDog();

    if (dog == null) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: Text(
            'Nenhum cão ativo.\nInicie um turno para ver o prontuário.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _cyanAccent, strokeWidth: 2),
              )
            : Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Text(
                            'Prontuário do Cão',
                            style: GoogleFonts.inter(
                              color: _cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        // Ficha do cão
                        _buildFicha(dog),
                        // Status médico
                        _buildStatusMedico(dog),
                        // Especialidades
                        _buildEspecialidades(dog),
                        // Evolução do peso
                        _buildPesoSection(dog),
                        // Carteira de vacinação
                        _buildVacinasSection(),
                        // Laudos e documentos
                        _buildDocumentosSection(),
                        // Eventos médicos recentes
                        _buildEventosSection(),
                        // Timeline de saúde
                        _buildHealthTimeline(dog),
                      ],
                    ),
                  ),
                  // Botão fixo no fundo
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildCtaButton(),
                  ),
                ],
              ),
      ),
    );
  }

  /// Botão CTA fixo no fundo
  Widget _buildCtaButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _bgColor.withAlpha(0),
            _bgColor,
            _bgColor,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          // TODO: navegar para tela de registro de evento de saúde
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _cyanAccent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _cyanAccent.withAlpha(51),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline, color: Color(0xFF050D10), size: 18),
              const SizedBox(width: 8),
              Text(
                'INSERIR NOVO REGISTRO',
                style: GoogleFonts.inter(
                  color: const Color(0xFF050D10),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Timeline simples dos últimos 5 eventos de saúde
  Widget _buildHealthTimeline(Dog dog) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs = healthVM.healthLogs
        .where((l) => l.dogId == dog.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final recentLogs = logs.take(5).toList();
    if (recentLogs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ÚLTIMOS EVENTOS DE SAÚDE', action: 'Ver tudo →'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: recentLogs.asMap().entries.map((entry) {
              final index = entry.key;
              final log = entry.value;
              final isLast = index == recentLogs.length - 1;
              return _buildHealthTimelineItem(log, isLast: isLast);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthTimelineItem(HealthLogModel log, {required bool isLast}) {
    final title = _healthEventTitle(log);
    final subtitle = log.healthObservations.isNotEmpty
        ? log.healthObservations
        : (log.vaccines.isNotEmpty ? log.vaccines.join(', ') : '');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coluna da timeline (dot + linha)
        SizedBox(
          width: 24,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cyanAccent.withAlpha(51),
                  border: Border.all(color: _cyanAccent, width: 2),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: _cyanAccent.withAlpha(40),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Conteúdo
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Data
                SizedBox(
                  width: 44,
                  child: Text(
                    DateFormat('dd/MM').format(log.date),
                    style: GoogleFonts.inter(
                      color: _dimMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: _textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _healthEventTitle(HealthLogModel log) {
    final logType = log.logType.trim();
    if (logType.isNotEmpty && logType.toLowerCase() != 'rotina') {
      return logType;
    }
    if (log.vaccines.isNotEmpty) return log.vaccines.first;
    return 'Registro de saúde';
  }

  /// Section label padrão
  Widget _buildSectionLabel(String text, {String? action, int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.inter(
              color: _cyanAccent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: _cyanAccent.withAlpha(38)),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _cyanAccent.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  color: _cyanAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(width: 8),
            Text(
              action,
              style: GoogleFonts.inter(
                color: _cyanAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
