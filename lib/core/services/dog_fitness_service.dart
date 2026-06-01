import 'package:canil_gcm/features/dogs/domain/dog.dart';

/// Status de aptidão do cão para assumir plantão.
enum DogFitnessStatus {
  /// Sem pendências críticas — pode assumir normalmente.
  apt,

  /// Pendências leves (vacina vencendo, antipulgas próximo) — pode assumir.
  warning,

  /// Pendências críticas (vacina vencida, em recuperação) — requer confirmação.
  unfit,
}

/// Uma pendência individual do cão.
class DogPendency {
  final String label;
  final DogPendencySeverity severity;

  const DogPendency({required this.label, required this.severity});
}

enum DogPendencySeverity { warning, critical }

/// Resultado do cálculo de aptidão de um cão.
class DogFitnessResult {
  final DogFitnessStatus status;
  final List<DogPendency> pendencies;

  const DogFitnessResult({required this.status, required this.pendencies});

  String get statusLabel => switch (status) {
    DogFitnessStatus.apt => 'APTO PARA PLANTÃO',
    DogFitnessStatus.warning => 'APTO COM PENDÊNCIA',
    DogFitnessStatus.unfit => 'NÃO APTO PARA PLANTÃO',
  };

  String get statusIcon => switch (status) {
    DogFitnessStatus.apt => '✓',
    DogFitnessStatus.warning => '!',
    DogFitnessStatus.unfit => '⊘',
  };
}

/// Calcula aptidão do cão baseado em dados de saúde disponíveis.
class DogFitnessService {
  const DogFitnessService();

  /// Calcula aptidão a partir do modelo [Dog].
  ///
  /// Regras:
  /// - Vacina vencida há >7 dias → NÃO APTO (critical)
  /// - Vacina vencendo em 30 dias → APTO COM PENDÊNCIA (warning)
  /// - Status != 'Ativo' (Licença, Aposentado) → NÃO APTO (critical)
  /// - Banho/antipulgas vencido há >30 dias → warning
  DogFitnessResult evaluate(Dog dog) {
    final now = DateTime.now();
    final pendencies = <DogPendency>[];

    // ── Status do cão ──────────────────────────────────────────────
    if (dog.status != 'Ativo') {
      pendencies.add(
        DogPendency(
          label: _statusLabel(dog.status),
          severity: DogPendencySeverity.critical,
        ),
      );
    }

    // ── Vacina ─────────────────────────────────────────────────────
    if (dog.lastVaccineDate != null) {
      final daysSinceVaccine = now.difference(dog.lastVaccineDate!).inDays;

      // Vacina anual: vencida se >365 dias
      if (daysSinceVaccine > 372) {
        // Vencida há mais de 7 dias
        final daysOverdue = daysSinceVaccine - 365;
        pendencies.add(
          DogPendency(
            label: 'Vacina vencida há $daysOverdue dias',
            severity: DogPendencySeverity.critical,
          ),
        );
      } else if (daysSinceVaccine > 335) {
        // Vencendo em 30 dias
        final daysLeft = 365 - daysSinceVaccine;
        pendencies.add(
          DogPendency(
            label: 'Vacina vence em $daysLeft dias',
            severity: DogPendencySeverity.warning,
          ),
        );
      }
    } else {
      // Sem registro de vacina
      pendencies.add(
        DogPendency(
          label: 'Sem registro de vacinação',
          severity: DogPendencySeverity.critical,
        ),
      );
    }

    // ── Banho / Antipulgas ─────────────────────────────────────────
    if (dog.lastBathDate != null) {
      final daysSinceBath = now.difference(dog.lastBathDate!).inDays;

      // Antipulgas mensal: vencendo se >25 dias, vencido se >30
      if (daysSinceBath > 30) {
        final daysOverdue = daysSinceBath - 30;
        pendencies.add(
          DogPendency(
            label: 'Antipulgas vencido há $daysOverdue dias',
            severity: DogPendencySeverity.warning,
          ),
        );
      } else if (daysSinceBath > 25) {
        final daysLeft = 30 - daysSinceBath;
        pendencies.add(
          DogPendency(
            label: 'Antipulgas vence em $daysLeft dias',
            severity: DogPendencySeverity.warning,
          ),
        );
      }
    }

    // ── Determinar status final ────────────────────────────────────
    final hasCritical = pendencies.any(
      (p) => p.severity == DogPendencySeverity.critical,
    );
    final hasWarning = pendencies.any(
      (p) => p.severity == DogPendencySeverity.warning,
    );

    final status = hasCritical
        ? DogFitnessStatus.unfit
        : hasWarning
        ? DogFitnessStatus.warning
        : DogFitnessStatus.apt;

    return DogFitnessResult(status: status, pendencies: pendencies);
  }

  String _statusLabel(String status) => switch (status) {
    'Licença' => 'Em licença',
    'Aposentado' => 'Aposentado',
    _ => status,
  };
}
