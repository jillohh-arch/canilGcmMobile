import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

class AddCommandModal extends StatefulWidget {
  final Dog dog;

  const AddCommandModal({super.key, required this.dog});

  @override
  State<AddCommandModal> createState() => _AddCommandModalState();
}

class _AddCommandModalState extends State<AddCommandModal> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  String _commandType = 'Vocálico'; // Vocálico, Gestual, Misto

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary.withAlpha(24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Novo Comando de Obediência',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cadastre um comando customizado para ${widget.dog.name}',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),

            // Command Name Field
            Text(
              'NOME DO COMANDO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Ex: Sit, Platz, Junto, Aqui...',
                hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceWhiteOverlay,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: AppTheme.surfaceWhiteBorderMedium,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Insira o nome do comando';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Command Type Segmented Row
            Text(
              'TIPO DE COMANDO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: ['Vocálico', 'Gestual', 'Misto'].map((type) {
                final isActive = _commandType == type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _commandType = type;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.primaryDivider
                            : AppTheme.surfaceWhiteOverlay,
                        border: Border.all(
                          color: isActive
                              ? AppTheme.primary
                              : AppTheme.surfaceWhiteBorder,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        type,
                        style: GoogleFonts.inter(
                          color: isActive
                              ? AppTheme.primary
                              : AppTheme.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Description / notes
            Text(
              'DESCRIÇÃO / OBJETIVO',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descController,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Ex: Sentar rápido e focado ao lado esquerdo...',
                hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceWhiteOverlay,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: AppTheme.surfaceWhiteBorder,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),

            // Actions row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textTertiary,
                      side: const BorderSide(
                        color: AppTheme.surfaceWhiteBorderMedium,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveCommand,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Cadastrar',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _saveCommand() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final cmdName = _nameController.text.trim();
    // Simulate save success
    AppFeedback.success(context, 'Comando "$cmdName" cadastrado com sucesso!');
    Navigator.of(context).pop(true);
  }
}
