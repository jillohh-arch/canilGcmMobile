import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'health_event_form_screen.dart';

class HealthTypeSelectorScreen extends StatefulWidget {
  final String dogId;
  final bool showBackButton;
  final bool popOnSave;
  final String? dogName;
  final String? dogBreed;
  final int? dogAgeYears;
  final double? currentWeightKg;
  final String? dogImageUrl;
  final String? handlerName;
  final Future<bool> Function(BuildContext context)? onRegisterWeight;
  final Future<bool> Function(BuildContext context)? onRegisterNutrition;
  final Future<bool> Function(BuildContext context)? onAttachDocument;

  const HealthTypeSelectorScreen({
    super.key,
    required this.dogId,
    this.showBackButton = true,
    this.popOnSave = true,
    this.dogName,
    this.dogBreed,
    this.dogAgeYears,
    this.currentWeightKg,
    this.dogImageUrl,
    this.handlerName,
    this.onRegisterWeight,
    this.onRegisterNutrition,
    this.onAttachDocument,
  });

  @override
  State<HealthTypeSelectorScreen> createState() =>
      _HealthTypeSelectorScreenState();
}

class _HealthTypeSelectorScreenState extends State<HealthTypeSelectorScreen> {
  String? _selectedType;
  bool _isContinuing = false;

  List<_HealthActionCategory> get _mainCategories => [
    const _HealthActionCategory(
      id: 'vaccination',
      label: 'Vacinação',
      subtitle: 'Registrar dose aplicada',
      icon: Icons.vaccines_rounded,
      color: AppTheme.primary,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'weight',
      label: 'Pesagem',
      subtitle: 'Registrar peso corporal',
      icon: Icons.monitor_weight_rounded,
      color: AppTheme.primary,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'nutrition',
      label: 'Nutrição',
      subtitle: 'Alimentação ou suplemento',
      icon: Icons.restaurant_rounded,
      color: AppTheme.attention,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'document',
      label: 'Documento/PDF',
      subtitle: 'Anexar laudo ao prontuário',
      icon: Icons.upload_file_rounded,
      color: AppTheme.info,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'antiparasitic',
      label: 'Antiparasitário',
      subtitle: 'Registrar aplicação e proteção',
      icon: Icons.bug_report_rounded,
      color: AppTheme.success,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'exam',
      label: 'Exame',
      subtitle: 'Solicitar ou anexar exame realizado',
      icon: Icons.biotech_rounded,
      color: AppTheme.healthAccent,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'consultation',
      label: 'Consulta',
      subtitle: 'Registrar atendimento e orientações',
      icon: Icons.medical_services_rounded,
      color: AppTheme.info,
      group: _HealthActionGroup.frequent,
    ),
    const _HealthActionCategory(
      id: 'medication',
      label: 'Medicação',
      subtitle: 'Registrar medicação e posologia',
      icon: Icons.medication_rounded,
      color: AppTheme.warning,
      group: _HealthActionGroup.clinical,
    ),
    const _HealthActionCategory(
      id: 'symptom',
      label: 'Sintoma',
      subtitle: 'Adicionar reação ou sintoma',
      icon: Icons.warning_rounded,
      color: AppTheme.error,
      group: _HealthActionGroup.clinical,
    ),
    const _HealthActionCategory(
      id: 'surgery',
      label: 'Cirurgia',
      subtitle: 'Registrar procedimento cirúrgico',
      icon: Icons.healing_rounded,
      color: AppTheme.attention,
      group: _HealthActionGroup.clinical,
    ),
    const _HealthActionCategory(
      id: 'other',
      label: 'Outro',
      subtitle: 'Registrar outros eventos de saúde',
      icon: Icons.more_horiz_rounded,
      color: AppTheme.textSoft,
      group: _HealthActionGroup.clinical,
    ),
  ];

  List<_HealthActionCategory> get _categories =>
      _mainCategories.where(_isCategoryAvailable).toList();

  bool _isCategoryAvailable(_HealthActionCategory category) {
    return switch (category.id) {
      'weight' => widget.onRegisterWeight != null,
      'nutrition' => widget.onRegisterNutrition != null,
      'document' => widget.onAttachDocument != null,
      _ => true,
    };
  }

  void _selectType(_HealthActionCategory category) {
    setState(() => _selectedType = category.id);
  }

  Future<void> _continueSelected() async {
    if (_isContinuing) return;
    _HealthActionCategory? selected;
    for (final category in _categories) {
      if (category.id == _selectedType) {
        selected = category;
        break;
      }
    }
    if (selected == null) return;
    final selectedId = selected.id;

    setState(() => _isContinuing = true);

    try {
      await _openSelectedCategory(selectedId);
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  Future<void> _openSelectedCategory(String selectedId) async {
    if (selectedId == 'weight') {
      final saved = await widget.onRegisterWeight?.call(context) ?? false;
      if (!mounted) return;
      if (saved && widget.popOnSave) Navigator.pop(context, true);
      return;
    }

    if (selectedId == 'nutrition') {
      final saved = await widget.onRegisterNutrition?.call(context) ?? false;
      if (!mounted) return;
      if (saved && widget.popOnSave) Navigator.pop(context, true);
      return;
    }

    if (selectedId == 'document') {
      final saved = await widget.onAttachDocument?.call(context) ?? false;
      if (!mounted) return;
      if (saved && widget.popOnSave) Navigator.pop(context, true);
      return;
    }

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HealthEventFormScreen(dogId: widget.dogId, type: selectedId),
      ),
    );
    if (!mounted) return;
    if (saved == true && widget.popOnSave) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frequent = _categories
        .where((category) => category.group == _HealthActionGroup.frequent)
        .toList();
    final clinical = _categories
        .where((category) => category.group == _HealthActionGroup.clinical)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.primary,
                  size: 30,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'Registrar Evento de Saúde',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HealthHubDogCard(
                      dogName: widget.dogName,
                      dogBreed: widget.dogBreed,
                      dogAgeYears: widget.dogAgeYears,
                      currentWeightKg: widget.currentWeightKg,
                      dogImageUrl: widget.dogImageUrl,
                      handlerName: widget.handlerName,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Selecione a categoria',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Escolha o tipo de registro que deseja adicionar ao prontuário.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _HealthHubSection(
                      title: 'MAIS USADOS',
                      icon: Icons.star_rounded,
                      categories: frequent,
                      selectedType: _selectedType,
                      onSelected: _selectType,
                    ),
                    const SizedBox(height: 22),
                    _HealthHubSection(
                      title: 'CLÍNICO',
                      icon: Icons.monitor_heart_rounded,
                      categories: clinical,
                      selectedType: _selectedType,
                      onSelected: _selectType,
                    ),
                  ],
                ),
              ),
            ),

            // Dynamic disclaimer and action button panel
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceNavigation,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(26),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedType == 'symptom') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.error.withAlpha(50),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.gavel_rounded,
                              color: AppTheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Aviso Ético Institucional:\nO condutor registra sintomas observados. O diagnóstico de lesões ou condições médicas é responsabilidade exclusiva do médico veterinário.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.background,
                          disabledBackgroundColor: AppTheme.textPrimary
                              .withAlpha(26),
                          disabledForegroundColor: AppTheme.textPrimary
                              .withAlpha(77),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _selectedType != null ? 4 : 0,
                        ),
                        onPressed: _selectedType == null || _isContinuing
                            ? null
                            : _continueSelected,
                        child: Text(
                          'Continuar',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _HealthActionGroup { frequent, clinical }

class _HealthActionCategory {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _HealthActionGroup group;

  const _HealthActionCategory({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.group,
  });
}

class _HealthHubDogCard extends StatelessWidget {
  final String? dogName;
  final String? dogBreed;
  final int? dogAgeYears;
  final double? currentWeightKg;
  final String? dogImageUrl;
  final String? handlerName;

  const _HealthHubDogCard({
    required this.dogName,
    required this.dogBreed,
    required this.dogAgeYears,
    required this.currentWeightKg,
    required this.dogImageUrl,
    required this.handlerName,
  });

  @override
  Widget build(BuildContext context) {
    final name = dogName?.trim().isNotEmpty == true ? dogName!.trim() : 'Cão';
    final handler = handlerName?.trim().isNotEmpty == true
        ? handlerName!.trim()
        : 'Condutor';
    final breed = dogBreed?.trim().isNotEmpty == true ? dogBreed!.trim() : 'K9';
    final age = dogAgeYears == null ? null : '${dogAgeYears!} anos';
    final weight = currentWeightKg == null
        ? null
        : '${currentWeightKg!.toStringAsFixed(1)} kg';
    final meta = [breed, ?age, ?weight].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryOverlay,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryDivider),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(48),
              border: Border.all(color: AppTheme.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(85),
                  blurRadius: 18,
                ),
              ],
            ),
            child: ClipOval(
              child: dogImageUrl?.trim().isNotEmpty == true
                  ? Image.network(dogImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: AppTheme.surfacePanel,
                      child: const Icon(
                        Icons.pets_rounded,
                        color: AppTheme.primary,
                        size: 42,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · $handler',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withAlpha(18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.success.withAlpha(150)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        color: AppTheme.success,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Saúde',
                        style: GoogleFonts.inter(
                          color: AppTheme.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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

class _HealthHubSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_HealthActionCategory> categories;
  final String? selectedType;
  final ValueChanged<_HealthActionCategory> onSelected;

  const _HealthHubSection({
    required this.title,
    required this.icon,
    required this.categories,
    required this.selectedType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: AppTheme.primaryDivider)),
            const SizedBox(width: 10),
            Icon(icon, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: AppTheme.primaryDivider)),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.42,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return _HealthHubActionCard(
              category: category,
              selected: selectedType == category.id,
              onTap: () => onSelected(category),
            );
          },
        ),
      ],
    );
  }
}

class _HealthHubActionCard extends StatelessWidget {
  final _HealthActionCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _HealthHubActionCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withAlpha(24)
              : AppTheme.surfacePanel.withAlpha(210),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : AppTheme.surfaceWhiteBorderMedium,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withAlpha(70),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppTheme.background,
                    size: 22,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(category.icon, color: color, size: 32),
                const Spacer(),
                Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  category.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
