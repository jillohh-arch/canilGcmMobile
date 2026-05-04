import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../viewmodels/auth_viewmodel.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _hudBackground = Color(0xFF070B14);
  static const _hudPanel = Color(0xFF0B1220);
  static const _hudCyan = Color(0xFF00E5FF);
  static const _hudDanger = Color(0xFFFF3B6B);

  final _raController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: _hudDanger.withAlpha(140)),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: const Color(0xFF1A0A12),
      ),
    );
  }

  Future<void> _handleBiometricLogin(AuthViewModel authVM) async {
    HapticFeedback.heavyImpact();
    try {
      final canCheck =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canCheck) {
        _showSnack('Biometria não suportada neste dispositivo.');
        return;
      }
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autentique-se para acessar o CANIL GCM',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (authenticated) {
        final cachedRa = await _secureStorage.read(key: 'cached_ra');
        final cachedPass = await _secureStorage.read(key: 'cached_password');
        if (cachedRa != null &&
            cachedPass != null &&
            cachedRa.isNotEmpty &&
            cachedPass.isNotEmpty) {
          final success = await authVM.signInWithRaAndPassword(
            cachedRa,
            cachedPass,
          );
          if (!success) {
            _showSnack(
              'Credenciais expiradas. Faça login com senha novamente.',
            );
          }
        } else {
          _showSnack(
            'Nenhum acesso salvo. Faça login com R.A. e Senha primeiro.',
          );
        }
      }
    } catch (e) {
      _showSnack('Erro ao acessar biometria ou operação cancelada.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);

    return Scaffold(
      backgroundColor: _hudBackground,
      body: Stack(
        children: [
          // ── Background Image ──────────────────────────────────────────────
          Positioned.fill(
            child: Image.asset(
              'assets/images/k9_tactical_background.png',
              fit: BoxFit.cover,
            ),
          ),

          // ── Gradient Overlay & Blur ───────────────────────────────────────
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _hudBackground,
                      _hudBackground.withAlpha(220),
                      _hudBackground.withAlpha(90),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Login Content ──────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Brand Identity ─────────────────────────────────────
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hudCyan.withAlpha(18),
                                border: Border.all(
                                  color: _hudCyan.withAlpha(190),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _hudCyan.withAlpha(95),
                                    blurRadius: 34,
                                    spreadRadius: 3,
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
                              'SISTEMA TÁTICO OPERACIONAL K9',
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _hudCyan.withAlpha(210),
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 56),

                      // ── Error Message ──────────────────────────────────────
                      if (authVM.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _hudDanger.withAlpha(18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _hudDanger.withAlpha(130),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _hudDanger.withAlpha(35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: _hudDanger,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  authVM.errorMessage!,
                                  style: GoogleFonts.robotoMono(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Inputs ─────────────────────────────────────────────
                      _buildPremiumTextField(
                        controller: _raController,
                        label: 'IDENTIFICAÇÃO R.A.',
                        icon: Icons.badge_rounded,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Informe o R.A.' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildPremiumTextField(
                        controller: _passwordController,
                        label: 'CHAVE DE ACESSO',
                        icon: Icons.key_rounded,
                        obscureText: _obscurePassword,
                        isPassword: true,
                        onTogglePassword: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Senha obrigatória' : null,
                      ),
                      const SizedBox(height: 40),

                      // ── Primary Action ─────────────────────────────────────
                      authVM.isLoading
                          ? const Center(
                              child: CircularProgressIndicator(color: _hudCyan),
                            )
                          : SizedBox(
                              height: 58,
                              child: ElevatedButton(
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  if (_formKey.currentState!.validate()) {
                                    final ra = _raController.text.trim();
                                    final pass = _passwordController.text
                                        .trim();
                                    final success = await authVM
                                        .signInWithRaAndPassword(ra, pass);
                                    if (success) {
                                      await _secureStorage.write(
                                        key: 'cached_ra',
                                        value: ra,
                                      );
                                      await _secureStorage.write(
                                        key: 'cached_password',
                                        value: pass,
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _hudCyan,
                                  foregroundColor: _hudBackground,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  elevation: 10,
                                  shadowColor: _hudCyan.withAlpha(120),
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
                            ),
                      const SizedBox(height: 24),

                      // ── Biometrics & Social ────────────────────────────────
                      Center(
                        child: Text(
                          'AUTENTICAÇÃO SECUNDÁRIA',
                          style: GoogleFonts.robotoMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white38,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Biometria
                          _SocialButton(
                            iconWidget: const Icon(
                              Icons.fingerprint_rounded,
                              color: Colors.white70,
                              size: 28,
                            ),
                            onTap: () => _handleBiometricLogin(authVM),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool isPassword = false,
    VoidCallback? onTogglePassword,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      cursorColor: _hudCyan,
      style: GoogleFonts.robotoMono(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        labelStyle: GoogleFonts.robotoMono(
          color: _hudCyan.withAlpha(190),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        prefixIcon: Icon(icon, color: _hudCyan.withAlpha(180), size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _hudCyan.withAlpha(130),
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: _hudPanel.withAlpha(210),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: _hudCyan.withAlpha(45), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _hudCyan, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: _hudDanger.withAlpha(130)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _hudDanger),
        ),
        errorStyle: GoogleFonts.robotoMono(
          color: _hudDanger,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _raController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class _SocialButton extends StatelessWidget {
  final Widget iconWidget;
  final VoidCallback onTap;

  const _SocialButton({required this.iconWidget, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF101827).withAlpha(220),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF00E5FF).withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withAlpha(28),
              blurRadius: 18,
            ),
          ],
        ),
        child: iconWidget,
      ),
    );
  }
}
