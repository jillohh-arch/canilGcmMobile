import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Tela de splash exibida por 1-2 segundos enquanto o app
/// verifica estado de autenticação e turno ativo.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),
            // ── Brasão ──────────────────────────────────────────────
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withAlpha(15),
                border: Border.all(
                  color: AppTheme.primary.withAlpha(80),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo-canil.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.shield_rounded,
                    size: 56,
                    color: AppTheme.primary.withAlpha(180),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Título ──────────────────────────────────────────────
            Text(
              'CANIL K9',
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'GCM LIMEIRA-SP',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 48),

            // ── Loading dots ────────────────────────────────────────
            _LoadingDots(controller: _dotController),

            const Spacer(flex: 4),

            // ── Footer ──────────────────────────────────────────────
            Text(
              'v1.0.0',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Três pontos animados em sequência.
class _LoadingDots extends StatelessWidget {
  final AnimationController controller;

  const _LoadingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = (value < 0.5)
                ? (value * 2).clamp(0.3, 1.0)
                : ((1.0 - value) * 2).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}