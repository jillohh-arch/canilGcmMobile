part of 'dog_prontuario_tab_screen.dart';

/// Seção de nutrição no prontuário do cão.
/// Exibe: prescrição vigente, refeições do dia, conformidade alimentar.
extension _DogProntuarioNutricao on _DogProntuarioTabScreenState {
  /// Cor temática da nutrição (laranja).
  static final _nutritionColor = AppTheme.attention;

  Widget _buildNutricaoSection(Dog dog) {
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    // Inicializa o ViewModel para o cão ativo
    if (nutritionVM.activeDogId != dog.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nutritionVM.loadForDog(dog.id);
      });
    }

    if (nutritionVM.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: _nutritionColor,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('NUTRIÇÃO', action: 'Histórico →'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Card de prescrição vigente
              _buildPrescriptionCard(nutritionVM),
              const SizedBox(height: 10),
              // Grid de refeições do dia
              _buildTodayMealsGrid(nutritionVM),
              const SizedBox(height: 10),
              // Card de conformidade
              _buildConformityCard(nutritionVM),
              const SizedBox(height: 10),
              // Botão registrar alimentação
              _buildRegisterFeedingButton(dog),
            ],
          ),
        ),
      ],
    );
  }

  /// Card com prescrição vigente (tipo de ração, quantidade/dia, refeições).
  Widget _buildPrescriptionCard(NutritionViewModel vm) {
    final prescription = vm.prescription;

    if (prescription == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: _nutritionColor.withAlpha(40)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: _nutritionColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhuma prescrição nutricional vigente',
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border.all(color: _nutritionColor.withAlpha(40)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ícone + tipo de ração
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _nutritionColor.withAlpha(31),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: _nutritionColor,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prescription.foodType.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: _nutritionColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              // Badge vigente
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _greenAccent.withAlpha(31),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'VIGENTE',
                  style: GoogleFonts.inter(
                    color: _greenAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Métricas: quantidade/dia | por refeição | refeições/dia
          Row(
            children: [
              _buildPrescriptionMetric(
                '${prescription.amountGramsPerDay}g',
                'por dia',
              ),
              _buildPrescriptionDivider(),
              _buildPrescriptionMetric(
                '${prescription.amountPerMeal}g',
                'por refeição',
              ),
              _buildPrescriptionDivider(),
              _buildPrescriptionMetric(
                '${prescription.mealsPerDay}x',
                'refeições',
              ),
            ],
          ),
          // Veterinário (se disponível)
          if (prescription.vetName != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.medical_services_outlined,
                    color: _textMuted, size: 12),
                const SizedBox(width: 6),
                Text(
                  'Dr(a). ${prescription.vetName}',
                  style: GoogleFonts.inter(
                    color: _textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (prescription.vetCrmv != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '• CRMV ${prescription.vetCrmv}',
                    style: GoogleFonts.inter(
                      color: _dimMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrescriptionMetric(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              color: _textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withAlpha(20),
    );
  }

  /// Grid de refeições do dia (manhã, almoço, noite).
  Widget _buildTodayMealsGrid(NutritionViewModel vm) {
    final periods = ['manha', 'almoco', 'noite'];
    final feedings = vm.todayFeedings;

    return Row(
      children: periods.map((period) {
        final feeding = feedings.cast<Feeding?>().firstWhere(
              (f) => f?.period == period,
              orElse: () => null,
            );
        final isLast = period == periods.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8),
            child: _buildMealSlot(period, feeding, vm),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMealSlot(String period, Feeding? feeding, NutritionViewModel vm) {
    final done = feeding != null;
    final label = NutritionViewModel.periodLabel(period);
    final iconData = _periodIcon(period);

    final slotColor = done ? _greenAccent : _nutritionColor;
    final bgAlpha = done ? 15 : 8;
    final borderAlpha = done ? 50 : 30;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: slotColor.withAlpha(bgAlpha),
        border: Border.all(color: slotColor.withAlpha(borderAlpha)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(iconData, color: slotColor, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: slotColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (done) ...[
            Text(
              '${feeding.amountGrams}g',
              style: GoogleFonts.inter(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (feeding.divergencePercent.abs() > 0)
              Text(
                '${feeding.divergencePercent > 0 ? '+' : ''}${feeding.divergencePercent.toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  color: feeding.divergencePercent.abs() <= 5
                      ? _greenAccent
                      : _redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ] else ...[
            Text(
              '—',
              style: GoogleFonts.inter(
                color: _dimMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'pendente',
              style: GoogleFonts.inter(
                color: _dimMuted,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _periodIcon(String period) {
    switch (period) {
      case 'manha':
        return Icons.wb_sunny_outlined;
      case 'almoco':
        return Icons.wb_cloudy_outlined;
      case 'noite':
        return Icons.nightlight_outlined;
      default:
        return Icons.restaurant;
    }
  }

  /// Card de conformidade alimentar do dia.
  Widget _buildConformityCard(NutritionViewModel vm) {
    final progress = vm.dayProgress.clamp(0.0, 1.0);
    final consumed = vm.totalConsumedToday;
    final prescribed = vm.prescribedPerDay;
    final mealsCompleted = vm.mealsCompleted;
    final mealsExpected = vm.mealsExpected;

    // Cor do progresso baseada na conformidade
    final progressColor = progress >= 0.9
        ? _greenAccent
        : progress >= 0.5
            ? _nutritionColor
            : _redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border.all(color: Colors.white.withAlpha(20)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONSUMO DO DIA',
                style: GoogleFonts.inter(
                  color: _textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '$mealsCompleted/$mealsExpected refeições',
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Barra de progresso
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withAlpha(15),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 8),
          // Valores
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${consumed}g',
                      style: GoogleFonts.inter(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${prescribed}g',
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  color: progressColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Botão para abrir a tela de registro de alimentação.
  Widget _buildRegisterFeedingButton(Dog dog) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FeedingRegistrationScreen(
              dogId: dog.id,
              dogName: dog.name,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _nutritionColor.withAlpha(20),
          border: Border.all(color: _nutritionColor.withAlpha(60)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: _nutritionColor, size: 16),
            const SizedBox(width: 8),
            Text(
              'REGISTRAR ALIMENTAÇÃO',
              style: GoogleFonts.inter(
                color: _nutritionColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
