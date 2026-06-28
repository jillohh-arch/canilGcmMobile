import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';

part 'login_screen_widgets.dart';
part 'login_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
    AppFeedback.warning(context, message);
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
        localizedReason: 'Autentique-se para acessar o Canil K9',
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
            AppFeedback.error(
              context,
              'Credenciais expiradas. Faça login com senha novamente.',
            );
          }
        } else {
          _showSnack(
            'Nenhum acesso salvo. Faça login com R.A. e senha primeiro.',
          );
        }
      }
    } catch (e) {
      AppFeedback.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brasão + Título ─────────────────────────────────
                  const _LoginBrand(),
                  const SizedBox(height: 12),
                  Text(
                    'Bem-vindo de volta',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Acesse com sua matrícula e senha institucional',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Erro ───────────────────────────────────────────
                  if (authVM.errorMessage != null) ...[
                    _LoginErrorBanner(message: authVM.errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  // ── Campos ─────────────────────────────────────────
                  _LoginTextField(
                    controller: _raController,
                    label: 'Matrícula (RA)',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Informe o R.A.' : null,
                  ),
                  const SizedBox(height: 12),
                  _LoginTextField(
                    controller: _passwordController,
                    label: 'Senha',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    isPassword: true,
                    onTogglePassword: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Senha obrigatória' : null,
                  ),

                  // ── Esqueci senha ──────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: implementar recuperação de senha
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        'Esqueci minha senha',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Biometria (primária) ───────────────────────────
                  if (_biometricAvailable) ...[
                    _BiometricButton(
                      onPressed: () => _handleBiometricLogin(authVM),
                    ),
                    const SizedBox(height: 12),
                    _Divider(),
                    const SizedBox(height: 12),
                  ],

                  // ── Botão Entrar com Senha ────────────────────────
                  _PasswordLoginButton(
                    isLoading: authVM.isLoading,
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      if (_formKey.currentState!.validate()) {
                        final ra = _raController.text.trim();
                        final pass = _passwordController.text.trim();
                        final success = await authVM.signInWithRaAndPassword(
                          ra,
                          pass,
                        );
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
                  const SizedBox(height: 48),

                  // ── Footer institucional ───────────────────────────
                  Text(
                    'Acesso restrito a guardas da GCM Limeira',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cadastros são feitos pela administração do canil',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
