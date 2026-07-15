import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';

/// Mapper puro Dog → [HealthSummaryDogContextView].
///
/// Sem I/O, sem Firestore, sem cálculo de prontidão.
/// Uso previsto na Fase 2E (K9 ativo); a 2D apenas expõe a adaptação.
abstract final class HealthSummaryDogContextMapper {
  HealthSummaryDogContextMapper._();

  static HealthSummaryDogContextView fromDog(Dog dog, {DateTime? now}) {
    final breed = dog.breed.trim();
    final photo = dog.profileImageUrl?.trim();
    return HealthSummaryDogContextView(
      dogId: dog.id,
      name: dog.name,
      breed: breed.isEmpty ? null : breed,
      sexLabel: _sexLabel(dog.sex),
      ageLabel: ageLabelFor(dog.dateOfBirth, now: now),
      photoUrl: (photo == null || photo.isEmpty) ? null : photo,
    );
  }

  /// Label de idade em português (apresentação cadastral, não clínica).
  static String? ageLabelFor(DateTime dateOfBirth, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final birth = dateOfBirth.toLocal();
    var years = reference.year - birth.year;
    var months = reference.month - birth.month;
    if (reference.day < birth.day) {
      months -= 1;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years < 0) return null;
    if (years == 0) {
      if (months <= 0) return 'Menos de 1 mês';
      return months == 1 ? '1 mês' : '$months meses';
    }
    if (years == 1) return '1 ano';
    return '$years anos';
  }

  static String? _sexLabel(String sex) {
    final s = sex.trim().toUpperCase();
    if (s == 'M' || s == 'MACHO') return 'Macho';
    if (s == 'F' || s == 'FÊMEA' || s == 'FEMEA') return 'Fêmea';
    final raw = sex.trim();
    return raw.isEmpty ? null : raw;
  }
}
