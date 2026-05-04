import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hud_panel.dart';

const _hudPanelDeep = Color(0xFF08111D);
const _hudPanel = Color(0xFF0B1220);

class HudStepItem {
  final IconData icon;
  final String label;
  final String helper;

  const HudStepItem({
    required this.icon,
    required this.label,
    required this.helper,
  });
}

class HudProgressStrip extends StatelessWidget {
  final List<HudStepItem> steps;
  final int currentIndex;
  final Color accent;
  final ValueChanged<int> onSelected;

  const HudProgressStrip({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isActive = index == currentIndex;
          final isDone = index < currentIndex;
          final color = isActive || isDone ? accent : Colors.white24;

          return Padding(
            padding: EdgeInsets.only(right: index == steps.length - 1 ? 0 : 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isActive ? 164 : 122,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withAlpha(18)
                      : _hudPanel.withAlpha(170),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive ? accent : Colors.white12,
                    width: isActive ? 1.2 : 0.6,
                  ),
                  boxShadow: isActive
                      ? [BoxShadow(color: accent.withAlpha(45), blurRadius: 16)]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withAlpha(30),
                        border: Border.all(
                          color: color.withAlpha(130),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : step.icon,
                        color: color,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            step.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.robotoMono(
                              color: isActive ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(height: 2),
                            Text(
                              step.helper,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class HudStagePanel extends StatelessWidget {
  final List<String> titles;
  final List<String> subtitles;
  final List<IconData> icons;
  final int currentIndex;
  final Color accent;
  final Widget child;

  const HudStagePanel({
    super.key,
    required this.titles,
    required this.subtitles,
    required this.icons,
    required this.currentIndex,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    assert(titles.length == subtitles.length);
    assert(titles.length == icons.length);

    return HudPanel(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(160)),
                ),
                child: Icon(icons[currentIndex], color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titles[currentIndex].toUpperCase(),
                  softWrap: true,
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                'STEP ${currentIndex + 1}/${titles.length}',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white54,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withAlpha(20), Colors.transparent],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitles[currentIndex],
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(key: ValueKey(currentIndex), child: child),
          ),
        ],
      ),
    );
  }
}

class HudInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double? maxLabelWidth;

  const HudInfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.maxLabelWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _hudPanelDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth ?? 240),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HudMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const HudMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudPanelDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(120)),
        boxShadow: [BoxShadow(color: color.withAlpha(25), blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 14),
          Text(
            value,
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class HudActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double width;
  final bool enabled;

  const HudActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.width,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 58,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withAlpha(14),
          side: BorderSide(color: color.withAlpha(150)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class HudSelectField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;
  final Color accent;
  final String placeholder;

  const HudSelectField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.accent = const Color(0xFF00E5FF),
    this.placeholder = 'Selecione',
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = value == null
        ? placeholder
        : labelBuilder(value as T);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openSelector(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hudPanelDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(95), width: 1),
          boxShadow: [BoxShadow(color: accent.withAlpha(18), blurRadius: 14)],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withAlpha(18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withAlpha(90)),
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(
                      color: accent.withAlpha(190),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.oxanium(
                      color: value == null
                          ? Colors.white.withAlpha(115)
                          : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openSelector(BuildContext context) async {
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF070B14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withAlpha(155)),
            boxShadow: [BoxShadow(color: accent.withAlpha(45), blurRadius: 26)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withAlpha(120)),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: GoogleFonts.robotoMono(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white54,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withAlpha(20), Colors.transparent],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = item == value;
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop(item);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent.withAlpha(28)
                              : _hudPanel.withAlpha(210),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? accent
                                : Colors.white.withAlpha(18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected ? accent : Colors.white30,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                labelBuilder(item),
                                style: GoogleFonts.oxanium(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      onChanged(selected);
    }
  }
}
