import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';

part 'login_screen_widgets.dart';
part 'login_text_field.dart';

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
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAndAutoPrompt();
  }

  Future<void> _checkBiometricAndAutoPrompt() async {
    try {
      final canCheck =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canCheck) return;

      final cachedRa = await _secureStorage.read(key: 'cached_ra');
      final cachedPass = await _secureStorage.read(key: 'cached_password');
      final hasCredentials =
          cachedRa != null &&
          cachedPass != null &&
          cachedRa.isNotEmpty &&
          cachedPass.isNotEmpty;

      if (mounted) {
        setState(() => _biometricAvailable = true);
      }

      // Auto-trigger biometria se houver credenciais salvas
      if (hasCredentials && mounted) {
        final authVM = Provider.of<AuthViewModel>(context, listen: false);
        await _handleBiometricLogin(authVM);
      }
    } catch (_) {
      // Biometria indisponível — segue com login manual
    }
  }

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
          // ── Background sólido com gradiente sutil ─────────────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _hudPanel,
                    _hudBackground,
                  ],
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
                      const _LoginBrand(),
                      const SizedBox(height: 56),

                      // ── Error Message ──────────────────────────────────────
                      if (authVM.errorMessage != null) ...[
                        _LoginErrorBanner(message: authVM.errorMessage!),
                        const SizedBox(height: 24),
                      ],

                      // ── Biometria (primária) ──────────────────────────────
                      if (_biometricAvailable) ...[
                        _BiometricPrimaryAction(
                          onPressed: () => _handleBiometricLogin(authVM),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // ── Divisor ───────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white12)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'ou entre com senha',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white12)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Inputs ─────────────────────────────────────────────
                      _PremiumTextField(
                        controller: _raController,
                        label: 'IDENTIFICAÇÃO R.A.',
                        icon: Icons.badge_rounded,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Informe o R.A.' : null,
                      ),
                      const SizedBox(height: 16),
                      _PremiumTextField(
                        controller: _passwordController,
                        label: 'SENHA',
                        icon: Icons.key_rounded,
                        obscureText: _obscurePassword,
                        isPassword: true,
                        onTogglePassword: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Senha obrigatória' : null,
                      ),
                      const SizedBox(height: 32),

                      // ── Botão Entrar (secundário) ─────────────────────────
                      _LoginPrimaryAction(
                        isLoading: authVM.isLoading,
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          if (_formKey.currentState!.validate()) {
                            final ra = _raController.text.trim();
                            final pass = _passwordController.text.trim();
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

  @override
  void dispose() {
    _raController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
