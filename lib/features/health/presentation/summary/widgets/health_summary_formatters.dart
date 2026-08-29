/// Helpers de apresentação do Resumo (sem regras clínicas).
abstract final class HealthSummaryFormatters {
  HealthSummaryFormatters._();

  /// Peso em kg com vírgula BR (ex.: 29,8 kg).
  /// Requer valor finito; não formata NaN/Infinity como peso legítimo.
  static String weightKg(double kg, {int fractionDigits = 1}) {
    if (!kg.isFinite) return '—';
    final digits = fractionDigits < 0 ? 0 : fractionDigits;
    final fixed = kg.toStringAsFixed(digits);
    final localized = fixed.replaceAll('.', ',');
    return '$localized kg';
  }

  /// Quantidade + unidade (ex.: 250 g).
  static String amount(double value, String? unitLabel) {
    if (!value.isFinite) return '—';
    final unit = (unitLabel == null || unitLabel.trim().isEmpty)
        ? ''
        : ' ${unitLabel.trim()}';
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$text$unit';
  }

  /// Data curta dd/MM (sem inventar "hoje" sem base).
  static String shortDate(DateTime at) {
    final d = at.day.toString().padLeft(2, '0');
    final m = at.month.toString().padLeft(2, '0');
    return '$d/$m';
  }

  /// Rótulo de atualização a partir de [updatedAt] e "agora" do build.
  static String updatedLabel(DateTime? updatedAt, {DateTime? now}) {
    if (updatedAt == null) return 'Atualização não informada';
    final reference = now ?? DateTime.now();
    final local = updatedAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final sameDay =
        local.year == reference.year &&
        local.month == reference.month &&
        local.day == reference.day;
    if (sameDay) {
      return 'Atualizado hoje, $hh:$mm';
    }
    return 'Atualizado em ${shortDate(local)}, $hh:$mm';
  }

  /// Dias restantes até [nextDueAt] (apresentação trivial; sem política clínica).
  static String? daysUntilLabel(DateTime? nextDueAt, {DateTime? now}) {
    if (nextDueAt == null) return null;
    final reference = now ?? DateTime.now();
    final due = DateTime(nextDueAt.year, nextDueAt.month, nextDueAt.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    final days = due.difference(today).inDays;
    if (days < 0) return 'Vencida há ${-days} dias';
    if (days == 0) return 'Vence hoje';
    if (days == 1) return 'Próxima dose em 1 dia';
    return 'Próxima dose em $days dias';
  }

  /// Data de pesagem secundária.
  static String lastWeighingLabel(DateTime? measuredAt, {DateTime? now}) {
    if (measuredAt == null) return 'Data não informada';
    final reference = now ?? DateTime.now();
    final local = measuredAt.toLocal();
    final sameDay =
        local.year == reference.year &&
        local.month == reference.month &&
        local.day == reference.day;
    if (sameDay) return 'Última pesagem: hoje';
    return 'Última pesagem: ${shortDate(local)}';
  }
}
