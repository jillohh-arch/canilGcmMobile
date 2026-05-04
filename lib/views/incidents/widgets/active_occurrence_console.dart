import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ActiveOccurrenceConsole extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onQuickAction;
  final VoidCallback onOpenCentral;

  const ActiveOccurrenceConsole({
    super.key,
    required this.enabled,
    required this.onQuickAction,
    required this.onOpenCentral,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'REGISTROS RÁPIDOS',
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Toque apenas no que aconteceu no local.',
          style: GoogleFonts.inter(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth = (constraints.maxWidth - 10) / 2;
            final buttonHeight = buttonWidth.clamp(132.0, 164.0);
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TacticalGridButton(
                  label: 'ABORDAGEM FEITA',
                  icon: Icons.person_search_rounded,
                  assetPath: 'assets/images/actions/k9_abordagem.png',
                  color: const Color(0xFFFFC400),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('ABORDAGEM FEITA'),
                ),
                _TacticalGridButton(
                  label: 'CÃO EM AÇÃO',
                  icon: Icons.pets_rounded,
                  color: const Color(0xFF00F5A0),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('CÃO EM AÇÃO'),
                ),
                _TacticalGridButton(
                  label: 'BUSCA FEITA',
                  icon: Icons.search_rounded,
                  color: const Color(0xFF00B8FF),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('BUSCA FEITA'),
                ),
                _TacticalGridButton(
                  label: 'MATERIAL LOCALIZADO',
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xFFA855F7),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('MATERIAL LOCALIZADO'),
                ),
                _TacticalGridButton(
                  label: 'PARTE CONDUZIDA',
                  icon: Icons.person_pin_rounded,
                  color: const Color(0xFFFF8A00),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('PARTE CONDUZIDA'),
                ),
                _TacticalGridButton(
                  label: 'SEM ALTERAÇÃO',
                  icon: Icons.highlight_off_rounded,
                  color: const Color(0xFFB8C2D6),
                  width: buttonWidth,
                  height: buttonHeight,
                  enabled: enabled,
                  onTap: () => onQuickAction('SEM ALTERAÇÃO'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 58,
          child: OutlinedButton.icon(
            onPressed: enabled ? onOpenCentral : null,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: Text(
              'OUTRO EVENTO / CENTRAL',
              style: GoogleFonts.robotoMono(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: BorderSide(
                color: const Color(0xFF00E5FF).withAlpha(125),
                width: 1.4,
              ),
              backgroundColor: const Color(0xFF00E5FF).withAlpha(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TacticalGridButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? assetPath;
  final Color color;
  final double width;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  const _TacticalGridButton({
    required this.label,
    required this.icon,
    this.assetPath,
    required this.color,
    required this.width,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1322),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(140), width: 1.35),
              boxShadow: [
                BoxShadow(color: color.withAlpha(16), blurRadius: 14),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionVisual(icon: icon, assetPath: assetPath, color: color),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    height: 1.08,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionVisual extends StatelessWidget {
  final IconData icon;
  final String? assetPath;
  final Color color;

  const _ActionVisual({
    required this.icon,
    required this.assetPath,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (assetPath != null && assetPath!.isNotEmpty) {
      return SizedBox(
        width: 86,
        height: 76,
        child: Image.asset(
          assetPath!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _FallbackIcon(icon: icon, color: color),
        ),
      );
    }

    return _FallbackIcon(icon: icon, color: color);
  }
}

class _FallbackIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _FallbackIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
