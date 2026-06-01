import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';

class QuickEventItem {
  final String label;
  final String icon;
  final Color color;
  final OccurrenceEventCategory category;
  final String autoTitle;

  const QuickEventItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.category,
    required this.autoTitle,
  });
}

const _quickEvents = [
  QuickEventItem(
    label: 'Abordagem',
    icon: '👤',
    color: AppTheme.warning,
    category: OccurrenceEventCategory.approach,
    autoTitle: 'Abordagem',
  ),
  QuickEventItem(
    label: 'Emprego K9',
    icon: '🐾',
    color: AppTheme.success,
    category: OccurrenceEventCategory.dogWork,
    autoTitle: 'Emprego do cão',
  ),
  QuickEventItem(
    label: 'Busca K9',
    icon: '🔍',
    color: AppTheme.info,
    category: OccurrenceEventCategory.dogWork,
    autoTitle: 'Busca com cão',
  ),
  QuickEventItem(
    label: 'Material',
    icon: '📦',
    color: AppTheme.healthAccent,
    category: OccurrenceEventCategory.seizure,
    autoTitle: 'Material apreendido',
  ),
  QuickEventItem(
    label: 'Parte\nconduzida',
    icon: '⛓',
    color: AppTheme.attention,
    category: OccurrenceEventCategory.other,
    autoTitle: 'Parte conduzida',
  ),
  QuickEventItem(
    label: 'Sem\nalteração',
    icon: '○',
    color: AppTheme.textSecondary,
    category: OccurrenceEventCategory.closure,
    autoTitle: 'Sem alteração',
  ),
];

class ActiveOccurrenceQuickGrid extends StatelessWidget {
  final ValueChanged<QuickEventItem> onQuickEvent;
  final VoidCallback onOtherEvent;
  final bool isLoading;

  const ActiveOccurrenceQuickGrid({
    super.key,
    required this.onQuickEvent,
    required this.onOtherEvent,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Row(
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.primary,
                ),
              ),
            ] else ...[
              const Text('⚡', style: TextStyle(fontSize: 12)),
            ],
            const SizedBox(width: 8),
            Text(
              isLoading ? 'REGISTRANDO...' : 'REGISTROS RÁPIDOS',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Grid 3x2
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          children: _quickEvents.map((item) {
            return _QuickCard(
              item: item,
              onTap: isLoading
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onQuickEvent(item);
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // "Outro evento" button
        GestureDetector(
          onTap: onOtherEvent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withAlpha(100),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '+',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Outro evento / Central',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  final QuickEventItem item;
  final VoidCallback? onTap;

  const _QuickCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(item.icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 8),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
