import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

class UpdateCommandStageModal extends StatefulWidget {
  final String commandName;
  final int currentStage;
  final ValueChanged<int> onStageUpdated;

  const UpdateCommandStageModal({
    super.key,
    required this.commandName,
    required this.currentStage,
    required this.onStageUpdated,
  });

  @override
  State<UpdateCommandStageModal> createState() =>
      _UpdateCommandStageModalState();
}

class _UpdateCommandStageModalState extends State<UpdateCommandStageModal> {
  late int _selectedStage;

  final List<Map<String, String>> _stagesInfo = [
    {
      'name': 'Não treinado',
      'desc': 'O cão não conhece o comando ou está iniciando a indução.',
    },
    {
      'name': 'Introduzido',
      'desc': 'Conhece sob forte estímulo ou recompensa contínua.',
    },
    {
      'name': 'Em desenvolvimento',
      'desc': 'Executa em ambiente controlado com recompensas parciais.',
    },
    {
      'name': 'Consolidado',
      'desc': 'Executa com precisão em distrações moderadas.',
    },
    {
      'name': 'Operacional',
      'desc': 'Fixado de forma confiável em qualquer cenário tático.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedStage = widget.currentStage;
  }

  @override
  Widget build(BuildContext context) {
    final isRegression = _selectedStage < widget.currentStage;

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
                color: Colors.white.withAlpha(24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Atualizar Nível do Comando',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Comando: "${widget.commandName}"',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // List of stages
          ...List.generate(5, (index) {
            final stageNum = index + 1;
            final isCurrent = stageNum == widget.currentStage;
            final isSelected = stageNum == _selectedStage;

            Color borderColor = AppTheme.surfaceWhiteBorder;
            Color bgColor = AppTheme.surfaceWhiteOverlay;
            Color titleColor = Colors.white;

            if (isSelected) {
              borderColor = AppTheme.primary;
              bgColor = AppTheme.primaryDivider;
              titleColor = AppTheme.primary;
            } else if (isCurrent) {
              borderColor = AppTheme.primaryChipBorder;
              bgColor = AppTheme.primaryOverlay;
            }

            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _selectedStage = stageNum;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(color: borderColor, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppTheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0x33FFFFFF),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$stageNum',
                        style: GoogleFonts.inter(
                          color: isSelected
                              ? AppTheme.background
                              : AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _stagesInfo[index]['name']!,
                                style: GoogleFonts.inter(
                                  color: titleColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryChipBorder,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ATUAL',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.primary,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _stagesInfo[index]['desc']!,
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Regression warning card
          if (isRegression) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1FE67E22), // rgba(230, 126, 34, 0.12)
                border: Border.all(color: AppTheme.attention),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AVISO DE REGRESSÃO',
                          style: GoogleFonts.inter(
                            color: AppTheme.attention,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Você está reduzindo o nível de consolidação deste comando. Recomenda-se registrar notas no treino justificando a regressão.',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontSize: 10.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                    side: const BorderSide(color: Color(0x1AFFFFFF)),
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
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onStageUpdated(_selectedStage);
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRegression
                        ? AppTheme.attention
                        : AppTheme.primary,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    isRegression ? 'Confirmar Regressão' : 'Atualizar Nível',
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
    );
  }
}
