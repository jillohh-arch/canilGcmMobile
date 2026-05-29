import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';

/// Tela de registro de alimentação.
/// Acessada via prontuário ou CTA de nutrição.
class FeedingRegistrationScreen extends StatefulWidget {
  final String dogId;
  final String dogName;
  final String? initialPeriod;

  const FeedingRegistrationScreen({
    super.key,
    required this.dogId,
    required this.dogName,
    this.initialPeriod,
  });

  @override
  State<FeedingRegistrationScreen> createState() =>
      _FeedingRegistrationScreenState();
}

class _FeedingRegistrationScreenState extends State<FeedingRegistrationScreen> {
  static final _nutritionColor = AppTheme.attention;

  String _selectedPeriod = 'manha';
  final _amountController = TextEditingController();
  final _observationsController = TextEditingController();
  final _divergenceReasonController = TextEditingController();
  bool _saving = false;
  File? _photoFile;
  DateTime _selectedTime = DateTime.now();
  String _timeOption = 'agora'; // 'agora' | '5min' | '15min' | 'custom'
  bool _isCompliant = true;

  @override
  void initState() {
    super.initState();
    // Usa período inicial se fornecido, senão seleciona baseado na hora
    if (widget.initialPeriod != null) {
      _selectedPeriod = widget.initialPeriod!;
    } else {
      final hour = DateTime.now().hour;
      if (hour >= 11 && hour < 15) {
        _selectedPeriod = 'almoco';
      } else if (hour >= 15) {
        _selectedPeriod = 'noite';
      }
    }
    // Listener para atualizar campo de divergência quando quantidade muda
    _amountController.addListener(() => setState(() {}));

    // Pre-fill amount based on prescription
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = Provider.of<NutritionViewModel>(context, listen: false);
      if (vm.prescription != null) {
        setState(() {
          _amountController.text = vm.prescription!.amountPerMeal.toString();
        });
      } else {
        // Sem prescrição, a conformidade não faz sentido
        setState(() {
          _isCompliant = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _observationsController.dispose();
    _divergenceReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nutritionVM = Provider.of<NutritionViewModel>(context);
    final prescription = nutritionVM.prescription;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Registrar Alimentação',
          style: GoogleFonts.inter(
            color: _nutritionColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dog name badge
                    _buildDogBadge(),
                    const SizedBox(height: 20),
                    // Período selector
                    _buildPeriodSelector(),
                    const SizedBox(height: 20),
                    // Compliance toggle
                    if (prescription != null) _buildComplianceCheckbox(prescription),
                    // Quantidade
                    _buildAmountField(prescription),
                    const SizedBox(height: 20),
                    // Divergência condicional
                    if (!_isCompliant) _buildDivergenceField(prescription),
                    // Horário
                    _buildTimeSelector(),
                    const SizedBox(height: 20),
                    // Foto
                    _buildPhotoField(),
                    const SizedBox(height: 20),
                    // Observações
                    _buildObservationsField(),
                    const SizedBox(height: 16),
                    // Info de prescrição
                    if (prescription != null) _buildPrescriptionInfo(prescription),
                  ],
                ),
              ),
            ),
            // Botão salvar
            _buildSaveButton(nutritionVM),
          ],
        ),
      ),
    );
  }

  Widget _buildDogBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pets, color: _nutritionColor, size: 16),
          const SizedBox(width: 8),
          Text(
            widget.dogName,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('dd/MM • HH:mm').format(DateTime.now()),
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERÍODO',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildPeriodChip('manha', 'Manhã', Icons.wb_sunny_outlined),
            const SizedBox(width: 8),
            _buildPeriodChip('almoco', 'Almoço', Icons.wb_cloudy_outlined),
            const SizedBox(width: 8),
            _buildPeriodChip('noite', 'Noite', Icons.nightlight_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildPeriodChip(String value, String label, IconData icon) {
    final selected = _selectedPeriod == value;
    final color = selected ? _nutritionColor : AppTheme.textTertiary;
    final bgAlpha = selected ? 30 : 8;
    final borderAlpha = selected ? 80 : 30;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedPeriod = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: bgAlpha / 255.0),
            border: Border.all(color: color.withValues(alpha: borderAlpha / 255.0)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComplianceCheckbox(dynamic prescription) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _isCompliant = !_isCompliant;
              if (_isCompliant) {
                _amountController.text = prescription.amountPerMeal.toString();
                _divergenceReasonController.clear();
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: _isCompliant ? AppTheme.success.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: _isCompliant ? AppTheme.success.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  _isCompliant ? Icons.check_box : Icons.check_box_outline_blank,
                  color: _isCompliant ? AppTheme.success : AppTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Servido em conformidade com a prescrição (${prescription.amountPerMeal}g)',
                    style: GoogleFonts.inter(
                      color: _isCompliant ? Colors.white : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: _isCompliant ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildAmountField(dynamic prescription) {
    final prescribedPerMeal =
        prescription != null ? '${prescription.amountPerMeal}g' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'QUANTIDADE (GRAMAS)',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            if (prescription != null)
              Text(
                'Prescrito: $prescribedPerMeal',
                style: GoogleFonts.inter(
                  color: _nutritionColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _isCompliant ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: _isCompliant ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _amountController,
            enabled: !_isCompliant,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.inter(
              color: _isCompliant ? AppTheme.textTertiary : AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textTertiary.withValues(alpha: 0.4),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              suffixText: 'g',
              suffixStyle: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  /// Campo condicional de motivo da divergência — aparece só quando quantidade diverge >10%.
  Widget _buildDivergenceField(dynamic prescription) {
    if (prescription == null) return const SizedBox.shrink();
    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) return const SizedBox.shrink();

    final prescribedPerMeal = prescription.amountPerMeal as int;
    final divergence = Feeding.calculateDivergence(amount, prescribedPerMeal);
    if (divergence.abs() <= 10) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.06),
            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.24)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Divergência de ${divergence > 0 ? '+' : ''}${divergence.toStringAsFixed(0)}% da prescrição',
                  style: GoogleFonts.inter(
                    color: AppTheme.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          'MOTIVO DA DIVERGÊNCIA',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _divergenceReasonController,
            maxLines: 2,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Ex: pós-treino intenso, orientação veterinária...',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textTertiary.withValues(alpha: 0.4),
                fontSize: 12,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Seletor de horário: Agora / Há 5min / Há 15min / Editar.
  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HORÁRIO',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTimeChip('agora', 'Agora · ${DateFormat('HH:mm').format(DateTime.now())}'),
            _buildTimeChip('5min', 'Há 5min'),
            _buildTimeChip('15min', 'Há 15min'),
            _buildTimeChip('custom', 'Editar'),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeChip(String value, String label) {
    final selected = _timeOption == value;
    final color = selected ? _nutritionColor : AppTheme.textTertiary;

    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        if (value == 'custom') {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_selectedTime),
          );
          if (picked != null) {
            final now = DateTime.now();
            setState(() {
              _timeOption = 'custom';
              _selectedTime = DateTime(
                  now.year, now.month, now.day, picked.hour, picked.minute);
            });
          }
        } else {
          setState(() {
            _timeOption = value;
            final now = DateTime.now();
            switch (value) {
              case 'agora':
                _selectedTime = now;
                break;
              case '5min':
                _selectedTime = now.subtract(const Duration(minutes: 5));
                break;
              case '15min':
                _selectedTime = now.subtract(const Duration(minutes: 15));
                break;
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.12 : 0.04),
          border: Border.all(color: color.withValues(alpha: selected ? 0.4 : 0.1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value == 'custom' && _timeOption == 'custom'
              ? DateFormat('HH:mm').format(_selectedTime)
              : label,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Campo de foto opcional da balança.
  Widget _buildPhotoField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FOTO DA BALANÇA (OPCIONAL)',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            width: double.infinity,
            height: _photoFile != null ? 120 : 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _photoFile != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.file(
                          _photoFile!,
                          width: double.infinity,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => setState(() => _photoFile = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined,
                          color: AppTheme.textTertiary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tirar foto ou escolher da galeria',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: _nutritionColor),
                title: Text('Câmera',
                    style: GoogleFonts.inter(color: AppTheme.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: _nutritionColor),
                title: Text('Galeria',
                    style: GoogleFonts.inter(color: AppTheme.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (xFile != null) {
      setState(() => _photoFile = File(xFile.path));
    }
  }

  Widget _buildObservationsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OBSERVAÇÕES (OPCIONAL)',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _observationsController,
            maxLines: 3,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Ex: cão comeu com apetite normal...',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textTertiary.withValues(alpha: 0.4),
                fontSize: 13,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrescriptionInfo(dynamic prescription) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _nutritionColor.withValues(alpha: 0.08),
        border: Border.all(color: _nutritionColor.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: _nutritionColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${prescription.foodType} • ${prescription.amountGramsPerDay}g/dia • ${prescription.mealsPerDay}x refeições',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(NutritionViewModel vm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withValues(alpha: 0),
            AppTheme.background,
          ],
        ),
      ),
      child: GestureDetector(
        onTap: _saving ? null : () => _save(vm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _saving ? _nutritionColor.withValues(alpha: 0.4) : _nutritionColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _nutritionColor.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_saving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                const Icon(Icons.check_circle_outline,
                    color: Color(0xFF050D10), size: 18),
              const SizedBox(width: 8),
              Text(
                _saving ? 'SALVANDO...' : 'REGISTRAR ALIMENTAÇÃO',
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

  Future<void> _save(NutritionViewModel vm) async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _showError('Informe a quantidade em gramas');
      return;
    }

    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showError('Quantidade inválida');
      return;
    }

    final prescription = vm.prescription;
    final prescriptionAtTime = prescription?.amountPerMeal ?? 0;
    final divergence = prescription != null ? Feeding.calculateDivergence(amount, prescriptionAtTime) : 0.0;

    // Motivo é obrigatório quando a quantidade diverge > 10%
    if (prescription != null && !_isCompliant && divergence.abs() > 10 && _divergenceReasonController.text.trim().isEmpty) {
      _showError('Informe o motivo da divergência');
      return;
    }

    setState(() => _saving = true);

    try {
      final authVM = Provider.of<AuthViewModel>(context, listen: false);
      final fedBy = authVM.user?.uid ?? 'unknown';

      // Usa horário selecionado
      final feedTime = _timeOption == 'agora' ? DateTime.now() : _selectedTime;

      final feeding = Feeding(
        period: _selectedPeriod,
        amountGrams: amount,
        prescriptionAtTime: prescriptionAtTime,
        divergencePercent: divergence,
        divergenceReason: !_isCompliant && divergence.abs() > 10
            ? _divergenceReasonController.text.trim().isNotEmpty
                ? _divergenceReasonController.text.trim()
                : null
            : null,
        observations: _observationsController.text.trim().isNotEmpty
            ? _observationsController.text.trim()
            : null,
        fedAt: feedTime,
        fedBy: fedBy,
      );

      await vm.addFeedingWithPhoto(widget.dogId, feeding, _photoFile);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 12)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
