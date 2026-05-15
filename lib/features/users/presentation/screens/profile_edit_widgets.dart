part of 'profile_screen.dart';

class _ProfileEditSliver extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController callsignController;
  final String raStr;
  final bool isSaving;
  final VoidCallback onSave;

  const _ProfileEditSliver({
    required this.nameController,
    required this.callsignController,
    required this.raStr,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileSectionTitle('EDITAR PERFIL'),
            const SizedBox(height: 16),
            _ProfileEditField(
              controller: nameController,
              label: 'Nome',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 12),
            _ProfileEditField(
              controller: callsignController,
              label: 'Nome de Guerra (Codinome)',
              icon: Icons.military_tech_rounded,
            ),
            const SizedBox(height: 12),
            _ProfileReadonlyRaField(raStr: raStr),
            const SizedBox(height: 20),
            _ProfileSaveButton(isSaving: isSaving, onPressed: onSave),
          ],
        ),
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  final String title;

  const _ProfileSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: _hudCyan.withAlpha(210),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _ProfileEditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _ProfileEditField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      cursorColor: _hudCyan,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          color: _hudCyan.withAlpha(180),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon),
        prefixIconColor: _hudCyan.withAlpha(170),
        filled: true,
        fillColor: _hudPanel.withAlpha(220),
        border: _profileEditBorder(_hudCyan.withAlpha(60)),
        enabledBorder: _profileEditBorder(_hudCyan.withAlpha(60)),
        focusedBorder: _profileEditBorder(_hudCyan),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _ProfileReadonlyRaField extends StatelessWidget {
  final String raStr;

  const _ProfileReadonlyRaField({required this.raStr});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: raStr,
      readOnly: true,
      style: GoogleFonts.inter(
        color: Colors.white54,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'R.A. (somente leitura)',
        labelStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: Colors.white24,
        ),
        filled: true,
        fillColor: _hudPanel.withAlpha(150),
        border: _profileEditBorder(_hudCyan.withAlpha(35)),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _ProfileSaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onPressed;

  const _ProfileSaveButton({required this.isSaving, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: isSaving ? null : onPressed,
        icon: isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(Icons.save_rounded, color: _hudBackground),
        label: Text(
          isSaving ? 'SALVANDO...' : 'SALVAR ALTERAÇÕES',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: _hudBackground,
            fontSize: 14,
            letterSpacing: 0.8,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _hudCyan,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 8,
          shadowColor: _hudCyan.withAlpha(100),
        ),
      ),
    );
  }
}

OutlineInputBorder _profileEditBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: color),
  );
}
