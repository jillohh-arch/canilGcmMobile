part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioStatusMedico on _DogProntuarioTabScreenState {
  Widget _buildStatusMedico(Dog dog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('STATUS MÉDICO'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              _buildMedCard(
                icon: Icons.vaccines,
                label: 'VACINAS',
                value: _vaccineStatusText(),
                sub: _vaccineSubText(),
                status: _vaccineStatus(),
              ),
              _buildMedCard(
                icon: Icons.monitor_weight_outlined,
                label: 'PESO',
                value: dog.weight != null ? '${dog.weight} kg' : '—',
                sub: _weightSubText(dog),
                status: _weightStatus(dog),
              ),
              _buildMedCard(
                icon: Icons.pets,
                label: 'CONDIÇÃO',
                value: dog.condicaoCorporal ?? 'Normal',
                sub: '',
                status: 'ok',
              ),
              _buildMedCard(
                icon: Icons.calendar_today,
                label: 'TREINO',
                value: _trainingStatusText(dog),
                sub: _trainingSubText(dog),
                status: _trainingStatus(dog),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required String status,
  }) {
    final Color borderColor;
    final Color iconBg;
    final Color iconColor;

    switch (status) {
      case 'warn':
        borderColor = _yellowAccent;
        iconBg = _yellowAccent.withAlpha(31);
        iconColor = _yellowAccent;
        break;
      case 'critical':
        borderColor = _redAccent;
        iconBg = _redAccent.withAlpha(31);
        iconColor = _redAccent;
        break;
      default:
        borderColor = _greenAccent;
        iconBg = _greenAccent.withAlpha(31);
        iconColor = _greenAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: _textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              color: _textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              style: GoogleFonts.inter(
                color: _textSecondary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // ─── Helpers de status ───────────────────────────────────────

  String _vaccineStatusText() {
    if (_vaccines.isEmpty) return 'Sem dados';
    final expired = _vaccines.where((v) => v.isExpired).length;
    if (expired > 0) return '$expired vencida${expired > 1 ? 's' : ''}';
    return 'Em dia';
  }

  String _vaccineSubText() {
    if (_vaccines.isEmpty) return '';
    final next = _vaccines
        .where((v) => !v.isExpired)
        .toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    if (next.isEmpty) return 'Verificar carteira';
    final days = next.first.dataVencimento.difference(DateTime.now()).inDays;
    return 'Próx: ${next.first.nome} em ${days}d';
  }

  String _vaccineStatus() {
    if (_vaccines.isEmpty) return 'warn';
    final expired = _vaccines.where((v) => v.isExpired).length;
    if (expired > 0) return 'critical';
    final soonExpiring = _vaccines.where((v) {
      final days = v.dataVencimento.difference(DateTime.now()).inDays;
      return days <= 30;
    }).length;
    if (soonExpiring > 0) return 'warn';
    return 'ok';
  }

  String _weightStatus(Dog dog) {
    if (dog.weight == null || dog.idealWeightMin == null || dog.idealWeightMax == null) {
      return 'ok';
    }
    if (dog.weight! >= dog.idealWeightMin! && dog.weight! <= dog.idealWeightMax!) {
      return 'ok';
    }
    final distance = dog.weight! < dog.idealWeightMin!
        ? dog.idealWeightMin! - dog.weight!
        : dog.weight! - dog.idealWeightMax!;
    return distance > 2.0 ? 'critical' : 'warn';
  }

  String _weightSubText(Dog dog) {
    if (dog.weight == null) return '';
    if (dog.idealWeightMin != null && dog.idealWeightMax != null) {
      if (dog.weight! >= dog.idealWeightMin! && dog.weight! <= dog.idealWeightMax!) {
        return 'Dentro da faixa ideal';
      }
      return 'Faixa: ${dog.idealWeightMin}–${dog.idealWeightMax} kg';
    }
    return '';
  }

  String _trainingStatusText(Dog dog) {
    if (dog.lastTrainingDate == null) return 'Sem dados';
    final days = DateTime.now().difference(dog.lastTrainingDate!).inDays;
    if (days == 0) return 'Hoje';
    if (days == 1) return 'Ontem';
    return 'Há $days dias';
  }

  String _trainingSubText(Dog dog) {
    if (dog.lastTrainingDate == null) return '';
    return DateFormat('dd/MM').format(dog.lastTrainingDate!);
  }

  String _trainingStatus(Dog dog) {
    if (dog.lastTrainingDate == null) return 'warn';
    final days = DateTime.now().difference(dog.lastTrainingDate!).inDays;
    if (days <= 3) return 'ok';
    if (days <= 7) return 'warn';
    return 'critical';
  }
}
