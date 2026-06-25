import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/profiles/domain/seal_data.dart';

/// Bottom sheet reutilizavel para exibir detalhes de um selo de conformidade.
class SealDetailSheet extends StatelessWidget {
  final SealData seal;

  const SealDetailSheet({super.key, required this.seal});

  static void show(BuildContext context, SealData seal) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.transparent,
      builder: (_) => SealDetailSheet(seal: seal),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _SealIcon(seal: seal),
            const SizedBox(height: 14),
            Text(
              seal.name,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              seal.subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            if (seal.isActive) _ActiveContent(seal: seal),
            if (!seal.isActive) _InactiveContent(seal: seal),
          ],
        ),
      ),
    );
  }
}

class _SealIcon extends StatelessWidget {
  final SealData seal;

  const _SealIcon({required this.seal});

  @override
  Widget build(BuildContext context) {
    final color = seal.isActive ? AppTheme.success : AppTheme.textSoft;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withAlpha(80), width: 2),
      ),
      child: Icon(seal.icon, color: color, size: 24),
    );
  }
}

class _ActiveContent extends StatelessWidget {
  final SealData seal;

  const _ActiveContent({required this.seal});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (seal.criterion != null)
          _DetailSection(label: 'CRITÉRIO', text: seal.criterion!),
        if (seal.activity != null) ...[
          const SizedBox(height: 14),
          _DetailSection(label: 'ATIVIDADE', text: seal.activity!),
        ],
        if (seal.howToMaintain != null) ...[
          const SizedBox(height: 14),
          _DetailSection(label: 'COMO MANTER', text: seal.howToMaintain!),
        ],
        const SizedBox(height: 20),
        _SheetButton(
          label: 'Ver detalhes',
          filled: false,
          onTap: () {
            // TODO: implementar navegacao para detalhe do selo
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Em breve',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _InactiveContent extends StatelessWidget {
  final SealData seal;

  const _InactiveContent({required this.seal});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (seal.currentState != null)
          _DetailSection(label: 'ESTADO ATUAL', text: seal.currentState!),
        if (seal.requiredAction != null) ...[
          const SizedBox(height: 14),
          _DetailSection(label: 'AÇÃO NECESSÁRIA', text: seal.requiredAction!),
        ],
        const SizedBox(height: 20),
        if (seal.actionButtonLabel != null)
          _SheetButton(
            label: seal.actionButtonLabel!,
            filled: true,
            onTap: () {
              // TODO: implementar navegacao para actionRoute
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Em breve',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String label;
  final String text;

  const _DetailSection({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(8),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? AppTheme.primary : AppTheme.transparent,
          border: Border.all(
            color: filled ? AppTheme.primary : AppTheme.primary.withAlpha(128),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: filled ? AppTheme.background : AppTheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
