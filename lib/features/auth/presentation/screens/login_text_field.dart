part of 'login_screen.dart';

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final bool isPassword;
  final VoidCallback? onTogglePassword;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.isPassword = false,
    this.onTogglePassword,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      cursorColor: _LoginScreenState._hudCyan,
      style: GoogleFonts.robotoMono(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        labelStyle: GoogleFonts.robotoMono(
          color: _LoginScreenState._hudCyan.withAlpha(190),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        prefixIcon: Icon(
          icon,
          color: _LoginScreenState._hudCyan.withAlpha(180),
          size: 20,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _LoginScreenState._hudCyan.withAlpha(130),
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: _LoginScreenState._hudPanel.withAlpha(210),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: _LoginScreenState._hudCyan.withAlpha(45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(
            color: _LoginScreenState._hudCyan,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: _LoginScreenState._hudDanger.withAlpha(130),
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _LoginScreenState._hudDanger),
        ),
        errorStyle: GoogleFonts.robotoMono(
          color: _LoginScreenState._hudDanger,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
