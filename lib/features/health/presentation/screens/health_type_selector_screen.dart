import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'health_event_form_screen.dart';

class HealthTypeSelectorScreen extends StatefulWidget {
  final String dogId;

  const HealthTypeSelectorScreen({super.key, required this.dogId});

  @override
  State<HealthTypeSelectorScreen> createState() =>
      _HealthTypeSelectorScreenState();
}

class _HealthTypeSelectorScreenState extends State<HealthTypeSelectorScreen> {
  String? _selectedType;

  final List<Map<String, dynamic>> _categories = [
    {
      'id': 'vaccination',
      'label': 'Vacinação',
      'icon': Icons.vaccines_rounded,
      'color': AppTheme.success,
    },
    {
      'id': 'antiparasitic',
      'label': 'Antiparasitário',
      'icon': Icons.bug_report_rounded,
      'color': AppTheme.healthAccent,
    },
    {
      'id': 'exam',
      'label': 'Exame',
      'icon': Icons.biotech_rounded,
      'color': AppTheme.info,
    },
    {
      'id': 'consultation',
      'label': 'Consulta',
      'icon': Icons.medical_services_rounded,
      'color': AppTheme.successOperational,
    },
    {
      'id': 'medication',
      'label': 'Medicação',
      'icon': Icons.medication_rounded,
      'color': AppTheme.warning,
    },
    {
      'id': 'symptom',
      'label': 'Sintoma observado',
      'icon': Icons.warning_rounded,
      'color': AppTheme.error,
    },
    {
      'id': 'surgery',
      'label': 'Cirurgia',
      'icon': Icons.healing_rounded,
      'color': AppTheme.attention,
    },
    {
      'id': 'other',
      'label': 'Outro',
      'icon': Icons.more_horiz_rounded,
      'color': AppTheme.textSoft,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Registrar Evento de Saúde',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione a Categoria',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Escolha o tipo de registro médico que deseja adicionar ao prontuário.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.25,
                          ),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSelected = _selectedType == cat['id'];
                        final color = cat['color'] as Color;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedType = cat['id'];
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withAlpha(25)
                                  : cs.surfaceContainerHighest.withAlpha(140),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : AppTheme.textPrimary.withAlpha(26),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withAlpha(50),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      cat['icon'] as IconData,
                                      size: 28,
                                      color: isSelected
                                          ? color
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    cat['label'] as String,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Dynamic disclaimer and action button panel
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(26),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedType == 'symptom') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.error.withAlpha(50),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.gavel_rounded,
                              color: AppTheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Aviso Ético Institucional:\nO condutor registra sintomas observados. O diagnóstico de lesões ou condições médicas é responsabilidade exclusiva do médico veterinário.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.background,
                          disabledBackgroundColor: AppTheme.textPrimary
                              .withAlpha(26),
                          disabledForegroundColor: AppTheme.textPrimary
                              .withAlpha(77),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _selectedType != null ? 4 : 0,
                        ),
                        onPressed: _selectedType == null
                            ? null
                            : () async {
                                final saved = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HealthEventFormScreen(
                                      dogId: widget.dogId,
                                      type: _selectedType!,
                                    ),
                                  ),
                                );
                                if (!context.mounted) return;
                                if (saved == true) {
                                  Navigator.pop(context, true);
                                }
                              },
                        child: Text(
                          'Continuar',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
