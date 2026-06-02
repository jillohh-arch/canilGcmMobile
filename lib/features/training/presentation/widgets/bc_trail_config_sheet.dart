import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';

class BcTrailConfigSheet extends StatefulWidget {
  final String phase;
  final String dogId;
  final String dogName;
  final String conductor;
  final TrainingModule? module;
  final List<TrainingMilestone> milestones;
  final String initialFigurante;
  final String initialOdorObject;
  final String initialAmbiente;

  const BcTrailConfigSheet({
    super.key,
    required this.phase,
    required this.dogId,
    required this.dogName,
    required this.conductor,
    this.module,
    this.milestones = const [],
    this.initialFigurante = '',
    this.initialOdorObject = '',
    this.initialAmbiente = '',
  });

  @override
  State<BcTrailConfigSheet> createState() => _BcTrailConfigSheetState();
}

class _BcTrailConfigSheetState extends State<BcTrailConfigSheet> {
  late final TextEditingController _figuranteController;
  late final TextEditingController _odorController;
  late final TextEditingController _ambienteController;
  TrainingMilestone? _selectedMilestone;
  bool _batteryChecked = false;
  bool? _gpsOk;
  bool? _connectionOk;

  @override
  void initState() {
    super.initState();
    _figuranteController = TextEditingController(text: widget.initialFigurante);
    _odorController = TextEditingController(text: widget.initialOdorObject);
    _ambienteController = TextEditingController(text: widget.initialAmbiente);
    if (widget.milestones.isNotEmpty) {
      _selectedMilestone = widget.milestones.first;
    }
    _runChecks();
  }

  @override
  void dispose() {
    _figuranteController.dispose();
    _odorController.dispose();
    _ambienteController.dispose();
    super.dispose();
  }

  Future<void> _runChecks() async {
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final gpsAllowed =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    final connectionOk = await _checkConnection();
    if (!mounted) return;
    setState(() {
      _gpsOk = gpsEnabled && gpsAllowed;
      _connectionOk = connectionOk;
    });
  }

  Future<bool> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'firestore.googleapis.com',
      ).timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _canStart {
    final needsMilestone = widget.phase == 'formation';
    return _batteryChecked &&
        _figuranteController.text.trim().isNotEmpty &&
        _odorController.text.trim().isNotEmpty &&
        _ambienteController.text.trim().isNotEmpty &&
        (!needsMilestone || _selectedMilestone != null);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary.withAlpha(45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Configurar trilha B&C',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.phase == 'formation'
                  ? 'Formacao vinculada ao modulo atual'
                  : 'Manutencao operacional sem modulo',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CheckTile(
                    label: 'GPS',
                    ok: _gpsOk,
                    detail: _gpsOk == false
                        ? 'Ative/permissao'
                        : 'Servico pronto',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CheckTile(
                    label: 'Conexao',
                    ok: _connectionOk,
                    detail: _connectionOk == false ? 'Salva offline' : 'Online',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _batteryChecked,
              onChanged: (value) =>
                  setState(() => _batteryChecked = value == true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.primary,
              title: Text(
                'Bateria/carga conferida para campo',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            if (widget.phase == 'formation') ...[
              const SizedBox(height: 8),
              _buildMilestoneSelector(),
            ],
            const SizedBox(height: 10),
            _buildTextField(_figuranteController, 'Figurante'),
            const SizedBox(height: 10),
            _buildTextField(_odorController, 'Objeto de odor'),
            const SizedBox(height: 10),
            _buildTextField(_ambienteController, 'Ambiente'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canStart ? _confirm : null,
                icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                label: const Text('INICIAR TRILHA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.background,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneSelector() {
    return DropdownButtonFormField<TrainingMilestone>(
      initialValue: _selectedMilestone,
      dropdownColor: AppTheme.surfacePanel,
      decoration: _inputDecoration('Marco trabalhado'),
      items: widget.milestones
          .map(
            (milestone) => DropdownMenuItem(
              value: milestone,
              child: Text(
                milestone.label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _selectedMilestone = value),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
      decoration: _inputDecoration(label),
      onChanged: (_) => setState(() {}),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
      filled: true,
      fillColor: AppTheme.background.withAlpha(145),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
    );
  }

  void _confirm() {
    final milestone = _selectedMilestone;
    final module = widget.module;
    Navigator.of(context).pop(
      GpsTrackingSessionConfig(
        modality: 'busca_captura',
        phase: widget.phase,
        dogId: widget.dogId,
        dogName: widget.dogName,
        moduleId: module?.id,
        moduleName: module?.name,
        milestoneId: milestone?.id,
        milestoneLabel: milestone?.label,
        conductor: widget.conductor,
        figurante: _figuranteController.text.trim(),
        odorObject: _odorController.text.trim(),
        ambiente: _ambienteController.text.trim(),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final String label;
  final bool? ok;
  final String detail;

  const _CheckTile({
    required this.label,
    required this.ok,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok == null
        ? AppTheme.textMuted
        : ok == true
        ? AppTheme.success
        : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(65)),
      ),
      child: Row(
        children: [
          Icon(
            ok == null
                ? Icons.sync_rounded
                : ok == true
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  ok == null ? 'Verificando' : detail,
                  style: GoogleFonts.inter(color: color, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
