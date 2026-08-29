import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../shared/widgets/health_field_label.dart';
import '../health_professional_draft.dart';

/// Coleta a identidade do profissional EXTERNO que decidiu a restrição.
///
/// Distinto do operador que registra: aquele é resolvido server-side
/// (`recorded_by`), este é a autoridade clínica transcrita.
///
/// O tipo de registro NÃO tem valor inicial. CRMV aparece primeiro por
/// frequência, mas selecionar é afirmação do operador — assumir o conselho
/// seria inventar dado clínico.
final class HealthProfessionalIdentityField extends StatelessWidget {
  const HealthProfessionalIdentityField({
    super.key,
    required this.draft,
    required this.onChanged,
    this.enabled = true,
    this.accentColor = AppTheme.error,
  });

  final HealthProfessionalDraft draft;
  final ValueChanged<HealthProfessionalDraft> onChanged;
  final bool enabled;
  final Color accentColor;

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textSoft, fontSize: 13),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      filled: true,
      fillColor: AppTheme.surfacePanelStrong,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.outline.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.outline.withValues(alpha: 0.3)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HealthFieldLabel('Nome do profissional', required: true),
        TextFormField(
          key: const Key('restriction_professional_name'),
          initialValue: draft.name,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          maxLength: 200,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _decoration('Ex.: Dra. Ana Souza').copyWith(
            counterText: '',
          ),
          onChanged: (value) => onChanged(draft.copyWith(name: value)),
        ),
        const SizedBox(height: 14),

        const HealthFieldLabel('Tipo de registro', required: true),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in kHealthRegistrationTypeOrder)
              ChoiceChip(
                key: Key('restriction_registration_${type.wireName}'),
                label: Text(healthRegistrationTypeLabel(type)),
                selected: draft.registrationType == type,
                showCheckmark: false,
                onSelected: enabled
                    ? (_) => onChanged(draft.copyWith(registrationType: type))
                    : null,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: draft.registrationType == type
                      ? Colors.white
                      : AppTheme.textSoft,
                ),
                selectedColor: accentColor,
                backgroundColor: AppTheme.surfacePanelStrong,
                side: BorderSide(
                  color: draft.registrationType == type
                      ? accentColor
                      : AppTheme.outline.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        const HealthFieldLabel('Número do registro', required: true),
        TextFormField(
          key: const Key('restriction_professional_number'),
          initialValue: draft.registrationNumber,
          enabled: enabled,
          textCapitalization: TextCapitalization.characters,
          maxLength: 200,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _decoration('Ex.: SP-12345').copyWith(counterText: ''),
          onChanged: (value) =>
              onChanged(draft.copyWith(registrationNumber: value)),
        ),
        const SizedBox(height: 14),

        const HealthFieldLabel('Clínica ou instituição', required: true),
        TextFormField(
          key: const Key('restriction_professional_clinic'),
          initialValue: draft.clinic,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          maxLength: 200,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _decoration(
            'Ex.: Clínica Veterinária Central',
          ).copyWith(counterText: ''),
          onChanged: (value) => onChanged(draft.copyWith(clinic: value)),
        ),
        const SizedBox(height: 14),

        const HealthFieldLabel('Especialidade'),
        TextFormField(
          key: const Key('restriction_professional_specialty'),
          initialValue: draft.specialty,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          maxLength: 200,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: _decoration('Opcional. Ex.: Ortopedia').copyWith(
            counterText: '',
          ),
          onChanged: (value) => onChanged(draft.copyWith(specialty: value)),
        ),
      ],
    );
  }
}
