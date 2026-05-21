import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/occurrence_nature_search.dart';

class StartOccurrenceNatureLink extends StatelessWidget {
  final bool expanded;
  final String natureText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<OccurrenceNature> natures;
  final VoidCallback onToggle;
  final ValueChanged<OccurrenceNature> onSelected;
  final ValueChanged<String> onChanged;

  const StartOccurrenceNatureLink({
    super.key,
    required this.expanded,
    required this.natureText,
    required this.controller,
    required this.focusNode,
    required this.natures,
    required this.onToggle,
    required this.onSelected,
    required this.onChanged,
  });

  static const _quickSpecs = [
    _QuickNatureSpec(
      OccurrenceNature(
        code: 'PATRULHA',
        name: 'Patrulhamento',
        group: 'Operacional',
      ),
      ['patrul', 'ronda', 'averigu'],
    ),
    _QuickNatureSpec(
      OccurrenceNature(
        code: 'FARO_VEICULAR',
        name: 'Faro veicular',
        group: 'Operacional',
      ),
      ['faro veicul', 'veicul', 'entorpec'],
    ),
    _QuickNatureSpec(
      OccurrenceNature(
        code: 'VISTORIA_RESIDENCIAL',
        name: 'Vistoria residencial',
        group: 'Operacional',
      ),
      ['vistoria', 'resid', 'domicil'],
    ),
    _QuickNatureSpec(
      OccurrenceNature(
        code: 'BUSCA_MATA',
        name: 'Busca em mata',
        group: 'Operacional',
      ),
      ['busca mata', 'mata', 'rural'],
    ),
    _QuickNatureSpec(
      OccurrenceNature(code: 'APOIO', name: 'Apoio', group: 'Operacional'),
      ['apoio', 'suporte'],
    ),
    _QuickNatureSpec(
      OccurrenceNature(code: 'OUTRA', name: 'Outra', group: 'Operacional'),
      ['outra', 'outros'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final quickNatures = _buildQuickNatures();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, color: AppTheme.primary, size: 14),
            const SizedBox(width: 6),
            Text(
              'NATUREZA DA OCORRENCIA',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.94,
          children: quickNatures.map((nature) {
            final selected = _isSelected(nature);
            return _NatureTile(
              nature: nature,
              selected: selected,
              icon: _iconForNature(nature),
              onTap: () {
                HapticFeedback.lightImpact();
                onSelected(nature);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.search_rounded,
                  color: AppTheme.primary,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Text(
                  expanded
                      ? 'Fechar lista completa'
                      : natureText.isEmpty
                      ? 'Buscar outro tipo de ocorrencia'
                      : 'Tipo selecionado: $natureText',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withAlpha(50)),
            ),
            child: OccurrenceNatureSearch(
              controller: controller,
              focusNode: focusNode,
              natures: natures,
              panelColor: const Color(0xFF0E1A1F),
              accent: AppTheme.primary,
              fieldBuilder: _buildField,
              onSelected: onSelected,
              onChanged: onChanged,
            ),
          ),
        ],
      ],
    );
  }

  List<OccurrenceNature> _buildQuickNatures() {
    final active = natures
        .where((nature) => nature.active && nature.name.trim().isNotEmpty)
        .toList();
    final selected = <OccurrenceNature>[];

    if (active.length >= 6 && active.length <= 12) {
      selected.addAll(active.take(6));
    } else {
      for (final spec in _quickSpecs) {
        final match = _findMatchingNature(active, spec);
        selected.add(match ?? spec.fallback);
      }
    }

    for (final spec in _quickSpecs) {
      if (selected.length >= 6) break;
      if (!_containsNature(selected, spec.fallback)) {
        selected.add(spec.fallback);
      }
    }

    return selected.take(6).toList();
  }

  OccurrenceNature? _findMatchingNature(
    List<OccurrenceNature> active,
    _QuickNatureSpec spec,
  ) {
    for (final nature in active) {
      if (_containsNature([nature], spec.fallback)) return nature;
      final searchable = nature.searchableText;
      if (spec.tokens.any((token) => searchable.contains(token))) {
        return nature;
      }
    }
    return null;
  }

  bool _containsNature(List<OccurrenceNature> items, OccurrenceNature target) {
    final targetCode = target.code.trim().toLowerCase();
    final targetName = OccurrenceNature.normalizeForSearch(target.name);
    return items.any((item) {
      final itemCode = item.code.trim().toLowerCase();
      final itemName = OccurrenceNature.normalizeForSearch(item.name);
      return itemCode == targetCode || itemName == targetName;
    });
  }

  bool _isSelected(OccurrenceNature nature) {
    return natureText == nature.label ||
        natureText == nature.name ||
        natureText == nature.code;
  }

  IconData _iconForNature(OccurrenceNature nature) {
    final searchable = nature.searchableText;
    if (searchable.contains('veicul') || searchable.contains('carro')) {
      return Icons.directions_car_outlined;
    }
    if (searchable.contains('resid') || searchable.contains('domicil')) {
      return Icons.home_outlined;
    }
    if (searchable.contains('mata') || searchable.contains('rural')) {
      return Icons.park_outlined;
    }
    if (searchable.contains('apoio') || searchable.contains('suporte')) {
      return Icons.support_agent_outlined;
    }
    if (searchable.contains('outra') || searchable.contains('outro')) {
      return Icons.more_horiz_rounded;
    }
    if (searchable.contains('faro') || searchable.contains('busca')) {
      return Icons.search_rounded;
    }
    return Icons.shield_outlined;
  }

  Widget _buildField(
    BuildContext context,
    TextEditingController ctrl,
    FocusNode fn,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: fn,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar natureza...',
        hintStyle: GoogleFonts.inter(
          color: Colors.white.withAlpha(100),
          fontSize: 14,
        ),
        prefixIcon: Icon(Icons.search, color: AppTheme.primary, size: 20),
        filled: true,
        fillColor: const Color(0xFF0E1A1F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary.withAlpha(60)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary.withAlpha(60)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

class _NatureTile extends StatelessWidget {
  final OccurrenceNature nature;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _NatureTile({
    required this.nature,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppTheme.primary
        : Colors.white.withAlpha(25);
    final foreground = selected ? AppTheme.primary : AppTheme.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(24)
              : Colors.white.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: selected ? 1.7 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 24),
            const SizedBox(height: 8),
            Text(
              nature.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: foreground,
                fontSize: 11,
                height: 1.15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickNatureSpec {
  final OccurrenceNature fallback;
  final List<String> tokens;

  const _QuickNatureSpec(this.fallback, this.tokens);
}
