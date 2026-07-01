import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/services/onboarding_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

part 'onboarding_pages.dart';

/// Onboarding carousel shown on first app access.
/// 5 screens with icon, title, and brief description.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Icons.shield_rounded,
      title: 'K9 Ops Mobile',
      description:
          'Seu app operacional de turno. Registra turno, K9, ocorrências, treinos e saúde — tudo com autoria, data e histórico que defendem seu trabalho.',
    ),
    _OnboardingPageData(
      icon: Icons.timer_outlined,
      title: 'Comece pelo turno',
      description:
          'Escolha seu K9 de serviço, confira os alertas dele e assuma a viatura. Sem turno ativo, o app te leva direto pra essa tela.',
    ),
    _OnboardingPageData(
      icon: Icons.add_circle_outline_rounded,
      title: 'Botão "Nova"',
      description:
          'O botão central inicia ou continua uma ocorrência. Registre os fatos perto do momento em que acontecem — isso fortalece o histórico.',
    ),
    _OnboardingPageData(
      icon: Icons.auto_awesome_rounded,
      title: 'Transforme seu relato',
      description:
          'Escreva o relato do seu jeito e toque em "Transformar em minuta". A IA organiza em texto institucional. Você sempre revisa antes de usar — a IA nunca finaliza sozinha.',
    ),
    _OnboardingPageData(
      icon: Icons.science_outlined,
      title: 'É uma versão de teste',
      description:
          'Explore à vontade. Se algo travar ou parecer errado, reporte — seu retorno ajuda a melhorar o app antes do lançamento oficial.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      HapticFeedback.lightImpact();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skip() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    await OnboardingService().markOnboardingCompleted();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Pular',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return _OnboardingPage(
                    icon: page.icon,
                    title: page.title,
                    description: page.description,
                  );
                },
              ),
            ),
            // Page indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primary : AppTheme.textMuted.withAlpha(77),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // Action button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? 'Começar' : 'Próximo',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
