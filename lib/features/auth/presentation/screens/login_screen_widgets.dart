part of 'login_screen.dart';

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withAlpha(12),
              border: Border.all(
                color: AppTheme.primary.withAlpha(60),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo-canil.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.shield_rounded,
                  size: 48,
                  color: AppTheme.primary.withAlpha(180),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CANIL K9',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'GCM LIMEIRA-SP',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  final String message;

  const _LoginErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.error.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BiometricButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.fingerprint_rounded, size: 24),
        label: Text(
          'ENTRAR COM BIOMETRIA',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _PasswordLoginButton extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onPressed;

  const _PasswordLoginButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppTheme.primary.withAlpha(180)),
        ),
        child: Text(
          'ENTRAR COM SENHA',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppTheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFF1D2C33))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OU',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFF1D2C33))),
      ],
    );
  }
}