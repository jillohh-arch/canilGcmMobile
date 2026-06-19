import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/media_processing_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/edit_event_location_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

class EditEventScreen extends StatefulWidget {
  final String occurrenceId;
  final OccurrenceEvent? existingEvent;

  const EditEventScreen({
    super.key,
    required this.occurrenceId,
    this.existingEvent,
  });

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final _mediaService = const MediaProcessingService();
  final _storageService = StorageService();
  final _locationService = const LocationResolutionService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late OccurrenceEventCategory _selectedCategory;
  late DateTime _timestamp;
  int _selectedTimeChip = 0;

  List<String> _existingPhotoUrls = [];
  final Map<String, String> _photoHashMap = {}; // url → sha256
  final List<File> _newPhotos = [];
  final List<String> _removedPhotoUrls = [];

  bool _isSaving = false;
  String? _saveStatus;
  bool _auditExpanded = false;
  double? _gpsLat;
  double? _gpsLng;
  String? _gpsAddress;
  String? _locationSource;
  bool _isUpdatingGps = false;

  bool get _isEditing => widget.existingEvent != null;

  bool get _hasChanges {
    if (!_isEditing) {
      return _titleController.text.isNotEmpty ||
          _descriptionController.text.isNotEmpty ||
          _newPhotos.isNotEmpty ||
          _selectedCategory != OccurrenceEventCategory.other;
    }
    final e = widget.existingEvent!;
    return _titleController.text.trim() != (e.title ?? '') ||
        _descriptionController.text.trim() != (e.description ?? '') ||
        _selectedCategory != e.category ||
        _newPhotos.isNotEmpty ||
        _removedPhotoUrls.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.existingEvent!;
      _selectedCategory = e.category;
      _timestamp = e.timestamp;
      _titleController.text = e.title ?? '';
      _descriptionController.text = e.description ?? '';
      _existingPhotoUrls = List.from(e.photoUrls);
      // Extrair hashes existentes do photoMetadata
      for (final meta in e.photoMetadata) {
        final url = meta['url'] as String?;
        final hash = meta['sha256'] as String?;
        if (url != null && hash != null) {
          _photoHashMap[url] = hash;
        }
      }
      _gpsLat = e.gpsLat;
      _gpsLng = e.gpsLng;
      _gpsAddress = e.placeLabel;
      _locationSource = e.locationSource;
      _selectedTimeChip = -1;
      _resolveExistingGpsAddress();
    } else {
      _selectedCategory = OccurrenceEventCategory.other;
      _timestamp = DateTime.now();
      _selectedTimeChip = 0;
    }
  }

  Future<void> _resolveExistingGpsAddress() async {
    if (_gpsLat == null || _gpsLng == null) return;
    if (_gpsAddress?.trim().isNotEmpty == true) return;
    try {
      final address = await _locationService.addressForPoint(
        LatLng(_gpsLat!, _gpsLng!),
      );
      if (mounted) setState(() => _gpsAddress = address);
    } catch (_) {}
  }

  Future<void> _openLocationEditor() async {
    final vm = context.read<OccurrenceViewModel>();

    if (_isEditing) {
      // Modo persistente: salva direto no Firestore
      final e = widget.existingEvent!;
      final totalEvents = vm.events.length;
      final eventIndex = vm.events.indexOf(e) + 1;

      final result = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute(
          builder: (_) => EditEventLocationScreen(
            event: e.copyWith(gpsLat: _gpsLat, gpsLng: _gpsLng),
            eventIndex: eventIndex > 0 ? eventIndex : 1,
            totalEvents: totalEvents > 0 ? totalEvents : 1,
          ),
        ),
      );

      if (result == true && mounted) {
        final updated = await vm.getEvents(widget.occurrenceId);
        final refreshed = updated.where((ev) => ev.id == e.id).firstOrNull;
        if (refreshed != null) {
          setState(() {
            _gpsLat = refreshed.gpsLat;
            _gpsLng = refreshed.gpsLng;
            _gpsAddress = refreshed.placeLabel;
            _locationSource = refreshed.locationSource;
          });
          _resolveExistingGpsAddress();
        }
      }
    } else {
      // Modo pick-only: retorna coordenadas sem persistir
      final tempEvent = OccurrenceEvent(
        id: '',
        occurrenceId: widget.occurrenceId,
        category: _selectedCategory,
        timestamp: _timestamp,
        title: _titleController.text,
        gpsLat: _gpsLat,
        gpsLng: _gpsLng,
        placeLabel: _gpsAddress,
        locationSource: _locationSource,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final result = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute(
          builder: (_) => EditEventLocationScreen(
            event: tempEvent,
            eventIndex: vm.events.length + 1,
            totalEvents: vm.events.length + 1,
            pickOnly: true,
          ),
        ),
      );

      if (result is LocationPickResult && mounted) {
        setState(() {
          _gpsLat = result.lat;
          _gpsLng = result.lng;
          _gpsAddress = result.label;
          _locationSource = result.source;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onTimeChipSelected(int index) {
    setState(() {
      _selectedTimeChip = index;
      _timestamp = switch (index) {
        1 => DateTime.now().subtract(const Duration(minutes: 5)),
        _ => DateTime.now(),
      };
    });
  }

  Future<void> _onTimeEdit() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (picked == null || !mounted) return;

    final today = DateTime.now();
    final candidate = DateTime(
      today.year,
      today.month,
      today.day,
      picked.hour,
      picked.minute,
    );

    if (candidate.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horário não pode ser no futuro',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _selectedTimeChip = 2;
      _timestamp = candidate;
    });
  }

  Future<void> _updateGps() async {
    setState(() => _isUpdatingGps = true);
    try {
      final loc = await _locationService.currentHighAccuracy();
      setState(() {
        _gpsLat = loc.point.latitude;
        _gpsLng = loc.point.longitude;
        _gpsAddress = loc.address;
        _locationSource = 'gps_atual';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS atualizado', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS indisponível', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingGps = false);
    }
  }

  Future<void> _pickPhotos() async {
    final files = await _mediaService.pickAndCompressImages();
    if (files.isEmpty) return;
    setState(() => _newPhotos.addAll(files));
  }

  void _removeExistingPhoto(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Remover foto?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _removedPhotoUrls.add(_existingPhotoUrls[index]);
                _existingPhotoUrls.removeAt(index);
              });
            },
            child: Text(
              'REMOVER',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _removeNewPhoto(int index) {
    setState(() => _newPhotos.removeAt(index));
  }

  void _showDeleteDialog() {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Excluir evento?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Esta ação é registrada na auditoria.',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(180),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Motivo da exclusão',
                hintStyle: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(100),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: AppTheme.primary.withAlpha(100),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              await _deleteEvent(reason);
            },
            child: Text(
              'EXCLUIR',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(String reason) async {
    final vm = context.read<OccurrenceViewModel>();
    final authVM = context.read<AuthViewModel>();
    final userId = authVM.user?.uid ?? '';
    await vm.deleteEvent(
      widget.occurrenceId,
      widget.existingEvent!.id,
      userId,
      reason,
    );
    if (mounted) Navigator.of(context).pop('deleted');
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppFeedback.warning(
        context,
        'Informe um título para registrar o evento.',
        title: 'Campo obrigatório',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _saveStatus = _newPhotos.isNotEmpty
          ? 'Preparando fotos...'
          : 'Salvando evento...';
    });
    HapticFeedback.mediumImpact();

    try {
      final uploadResults = await _uploadNewPhotos();
      final newUrls = uploadResults.map((r) => r.url).toList();
      for (final r in uploadResults) {
        _photoHashMap[r.url] = r.sha256Hash;
      }
      final allPhotoUrls = [..._existingPhotoUrls, ...newUrls];

      if (mounted) {
        setState(() => _saveStatus = 'Salvando evento...');
      }
      if (_isEditing) {
        await _updateEvent(allPhotoUrls);
      } else {
        await _createEvent(allPhotoUrls);
      }

      if (mounted) Navigator.of(context).pop('saved');
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          e,
          fallback:
              'Não foi possível salvar o evento. Verifique a conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveStatus = null;
        });
      }
    }
  }

  Future<List<UploadResult>> _uploadNewPhotos() async {
    final results = <UploadResult>[];
    for (var i = 0; i < _newPhotos.length; i++) {
      if (mounted) {
        setState(
          () => _saveStatus = 'Enviando foto ${i + 1}/${_newPhotos.length}...',
        );
      }
      final result = await _storageService
          .uploadImageWithHash(
            _newPhotos[i],
            'occurrences/${widget.occurrenceId}/events',
          )
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () => throw TimeoutException(
              'Tempo excedido ao enviar a foto. Verifique o sinal e tente novamente.',
            ),
          );
      if (result == null) {
        throw StateError('A foto ${i + 1} não foi enviada. Tente novamente.');
      }
      results.add(result);
    }
    return results;
  }

  Future<void> _createEvent(List<String> photoUrls) async {
    final vm = context.read<OccurrenceViewModel>();
    final authVM = context.read<AuthViewModel>();
    final now = DateTime.now();
    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);

    // Se não tem GPS ainda, tenta capturar agora
    if (_gpsLat == null) {
      try {
        final loc = await _locationService.currentHighAccuracy();
        _gpsLat = loc.point.latitude;
        _gpsLng = loc.point.longitude;
        _gpsAddress = loc.address;
        _locationSource = 'gps_atual';
      } catch (_) {}
    }

    final event = OccurrenceEvent(
      id: const Uuid().v4(),
      occurrenceId: widget.occurrenceId,
      category: _selectedCategory,
      timestamp: _timestamp,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      photoUrls: photoUrls,
      photoMetadata: _buildPhotoMetadata(photoUrls),
      mediaItems: _buildMediaItems(photoUrls),
      dogHandlerId: _selectedCategory == OccurrenceEventCategory.dogWork
          ? handlerRa
          : null,
      gpsLat: _gpsLat,
      gpsLng: _gpsLng,
      placeLabel: _gpsAddress,
      locationSource: _locationSource,
      createdAt: now,
      updatedAt: now,
    );
    await vm.addEvent(event);
  }

  Future<void> _updateEvent(List<String> photoUrls) async {
    final vm = context.read<OccurrenceViewModel>();
    final updates = <String, dynamic>{};
    final e = widget.existingEvent!;

    if (_selectedCategory != e.category) {
      updates['category'] = _selectedCategory.toMap();
      updates['dog_handler_id'] =
          _selectedCategory == OccurrenceEventCategory.dogWork
          ? HandlerIdentityService.raFromUser(
              context.read<AuthViewModel>().user,
            )
          : null;
    }
    if (_timestamp != e.timestamp) {
      updates['timestamp'] = _timestamp;
    }
    if (_titleController.text.trim() != (e.title ?? '')) {
      updates['title'] = _titleController.text.trim();
    }
    final desc = _descriptionController.text.trim();
    if (desc != (e.description ?? '')) {
      updates['description'] = desc.isNotEmpty ? desc : null;
    }
    if (photoUrls.join(',') != e.photoUrls.join(',')) {
      updates['photo_urls'] = photoUrls;
      updates['photo_metadata'] = _buildPhotoMetadata(photoUrls);
      updates['media_items'] = _buildMediaItems(photoUrls);
    }
    if (_gpsLat != e.gpsLat || _gpsLng != e.gpsLng) {
      updates['gps_lat'] = _gpsLat;
      updates['gps_lng'] = _gpsLng;
    }
    if ((_gpsAddress ?? '').trim() != (e.placeLabel ?? '').trim()) {
      updates['place_label'] = _gpsAddress?.trim().isNotEmpty == true
          ? _gpsAddress!.trim()
          : null;
    }
    if ((_locationSource ?? '').trim() != (e.locationSource ?? '').trim()) {
      updates['location_source'] = _locationSource?.trim().isNotEmpty == true
          ? _locationSource!.trim()
          : null;
    }

    if (updates.isNotEmpty) {
      await vm.updateEvent(widget.occurrenceId, e.id, updates);
    }
  }

  List<Map<String, dynamic>> _buildPhotoMetadata(List<String> photoUrls) {
    return photoUrls.map((url) {
      final hash = _photoHashMap[url];
      return {
        'url': url,
        'type': 'image',
        if (hash != null && hash.isNotEmpty) 'sha256': hash,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _buildMediaItems(List<String> photoUrls) {
    return photoUrls
        .map(
          (url) => {
            'type': 'image',
            'url': url,
            'original_url': url,
            'source': 'occurrence_event',
            'preserved_original': true,
          },
        )
        .toList();
  }

  Future<bool> _onPopAttempt() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Descartar alterações?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Você tem dados não salvos que serão perdidos.',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary.withAlpha(200),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'DESCARTAR',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${_timestamp.hour.toString().padLeft(2, '0')}:${_timestamp.minute.toString().padLeft(2, '0')}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onPopAttempt();
        if (shouldPop && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildTimeChips(timeStr),
                    const SizedBox(height: 24),
                    _buildCategorySelector(),
                    const SizedBox(height: 24),
                    _buildTitleField(),
                    const SizedBox(height: 16),
                    _buildDescriptionField(),
                    const SizedBox(height: 16),
                    _buildGpsButton(),
                    const SizedBox(height: 24),
                    _buildPhotoSection(),
                    if (_isEditing &&
                        widget.existingEvent!.auditTrail.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildAuditTrail(),
                    ],
                  ],
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: _buildCta()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: AppTheme.textPrimary,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? 'Editar evento' : 'Novo evento',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_isEditing)
            GestureDetector(
              onTap: _showDeleteDialog,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: AppTheme.error,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeChips(String timeStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HORÁRIO DO EVENTO',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _TimeChip(
              label: 'Agora',
              selected: _selectedTimeChip == 0,
              onTap: () => _onTimeChipSelected(0),
            ),
            const SizedBox(width: 8),
            _TimeChip(
              label: 'Há 5min',
              selected: _selectedTimeChip == 1,
              onTap: () => _onTimeChipSelected(1),
            ),
            const SizedBox(width: 8),
            _TimeChip(
              label: timeStr,
              selected: _selectedTimeChip == 2 || _selectedTimeChip == -1,
              onTap: _onTimeEdit,
              icon: Icons.edit_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIPO DE EVENTO',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ...OccurrenceEventCategory.values.map((cat) {
          final selected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withAlpha(20)
                    : AppTheme.textPrimary.withAlpha(5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textPrimary.withAlpha(15),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textPrimary.withAlpha(80),
                        width: 2,
                      ),
                      color: selected ? AppTheme.primary : AppTheme.transparent,
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check,
                            size: 12,
                            color: AppTheme.textPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    cat.label,
                    style: GoogleFonts.inter(
                      color: selected
                          ? AppTheme.textPrimary
                          : AppTheme.textPrimary.withAlpha(180),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TÍTULO',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _fieldDecoration('Ex: Abordagem no veículo'),
        ),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DESCRIÇÃO',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          minLines: 2,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _fieldDecoration('Descreva o que aconteceu...'),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppTheme.textPrimary.withAlpha(80)),
      filled: true,
      fillColor: AppTheme.textPrimary.withAlpha(8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildGpsButton() {
    final hasGps = _gpsLat != null && _gpsLng != null;
    return GestureDetector(
      onTap: _isUpdatingGps ? null : _updateGps,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasGps
              ? AppTheme.success.withAlpha(12)
              : AppTheme.textPrimary.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasGps
                ? AppTheme.success.withAlpha(60)
                : AppTheme.textPrimary.withAlpha(20),
          ),
        ),
        child: Row(
          children: [
            if (_isUpdatingGps)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.success,
                ),
              )
            else
              Icon(
                hasGps ? Icons.location_on : Icons.location_off_outlined,
                size: 16,
                color: hasGps
                    ? AppTheme.success
                    : AppTheme.textPrimary.withAlpha(120),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: hasGps
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _gpsAddress ??
                              '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary.withAlpha(200),
                            fontSize: 12,
                          ),
                        ),
                        if (_gpsAddress != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_gpsLat!.toStringAsFixed(5)}, ${_gpsLng!.toStringAsFixed(5)}',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary.withAlpha(80),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      'Sem localização',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary.withAlpha(100),
                        fontSize: 12,
                      ),
                    ),
            ),
            Text(
              _isUpdatingGps ? 'Atualizando...' : 'ATUALIZAR',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!_isUpdatingGps) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _openLocationEditor,
                child: Text(
                  'MAPA',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final totalPhotos = _existingPhotoUrls.length + _newPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FOTOS${totalPhotos > 0 ? ' · $totalPhotos anexada${totalPhotos != 1 ? 's' : ''}' : ''}',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._existingPhotoUrls.asMap().entries.map(
                (entry) => _PhotoThumb(
                  child: Image.network(entry.value, fit: BoxFit.cover),
                  onLongPress: () => _removeExistingPhoto(entry.key),
                ),
              ),
              ..._newPhotos.asMap().entries.map(
                (entry) => _PhotoThumb(
                  child: Image.file(entry.value, fit: BoxFit.cover),
                  onLongPress: () => _removeNewPhoto(entry.key),
                ),
              ),
              _AddPhotoButton(onTap: _pickPhotos),
            ],
          ),
        ),
        if (totalPhotos == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Adicione fotos como evidência',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(80),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAuditTrail() {
    final trail = widget.existingEvent!.auditTrail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _auditExpanded = !_auditExpanded),
          child: Row(
            children: [
              Text(
                'TRILHA DE AUDITORIA',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _auditExpanded ? Icons.expand_less : Icons.expand_more,
                color: AppTheme.primary,
                size: 18,
              ),
            ],
          ),
        ),
        if (_auditExpanded) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.textPrimary.withAlpha(5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: trail.map((entry) {
                final action = entry['action'] ?? '';
                final at = entry['at'] ?? '';
                final field = entry['field_name'] as String?;
                final label = switch (action) {
                  'created' => 'Criado · $at',
                  'updated' =>
                    'Editado${field != null ? ' ($field)' : ''} · $at',
                  'deleted' => 'Excluído · $at',
                  _ => '$action · $at',
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary.withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCta() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.textPrimary.withAlpha(10)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            disabledBackgroundColor: AppTheme.primary.withAlpha(80),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isSaving
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _saveStatus ?? 'Salvando evento...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  'SALVAR EVENTO',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Private Widgets ──────────────────────────────────────────────────────

class _TimeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _TimeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(30)
              : AppTheme.textPrimary.withAlpha(8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.textPrimary.withAlpha(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: selected
                    ? AppTheme.primary
                    : AppTheme.textPrimary.withAlpha(150),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected
                    ? AppTheme.primary
                    : AppTheme.textPrimary.withAlpha(150),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onLongPress;

  const _PhotoThumb({required this.child, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: 80,
        height: 80,
        margin: const EdgeInsets.only(right: 8),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPhotoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withAlpha(60)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppTheme.primary, size: 22),
            const SizedBox(height: 4),
            Text(
              'Adicionar',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
