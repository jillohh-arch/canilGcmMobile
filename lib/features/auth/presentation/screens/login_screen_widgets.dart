part of 'login_screen.dart';

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _LoginScreenState._hudCyan.withAlpha(18),
              border: Border.all(
                color: _LoginScreenState._hudCyan.withAlpha(190),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _LoginScreenState._hudCyan.withAlpha(60),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/logo-canil.png',
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'CANIL GCM',
            style: GoogleFonts.oxanium(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SISTEMA OPERACIONAL K9 — CANIL GCM',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _LoginScreenState._hudCyan.withAlpha(210),
              letterSpacing: 2,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _LoginScreenState._hudDanger.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _LoginScreenState._hudDanger.withAlpha(130)),
        boxShadow: [
          BoxShadow(
            color: _LoginScreenState._hudDanger.withAlpha(35),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: _LoginScreenState._hudDanger,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.robotoMono(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPrimaryAction extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onPressed;

  const _LoginPrimaryAction({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _LoginScreenState._hudCyan),
      );
    }

    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _LoginScreenState._hudCyan,
          foregroundColor: _LoginScreenState._hudBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 10,
          shadowColor: _LoginScreenState._hudCyan.withAlpha(120),
        ),
        child: Text(
          'ACESSAR SISTEMA',
          style: GoogleFonts.oxanium(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _BiometricPrimaryAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _BiometricPrimaryAction({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.fingerprint_rounded, size: 30),
        label: Text(
          'ENTRAR COM BIOMETRIA',
          style: GoogleFonts.oxanium(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _LoginScreenState._hudCyan,
          foregroundColor: _LoginScreenState._hudBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 6,
          shadowColor: _LoginScreenState._hudCyan.withAlpha(80),
        ),
      ),
    );
  }
}
