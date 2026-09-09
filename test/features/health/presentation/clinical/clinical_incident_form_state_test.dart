import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_incident_form_state.dart';

void main() {
  group('ClinicalIncidentFormState', () {
    test('validates required fields', () {
      final state = ClinicalIncidentFormState();
      state.openNewCase = false;
      state.selectedCaseId = null;

      expect(state.validate(), contains('Selecione o caso clínico'));

      state.openNewCase = true;
      expect(state.validate(), contains('Selecione a categoria'));

      state.category = IncidentCategory.digestive;
      expect(state.validate(), contains('Descreva o que ocorreu'));

      state.description = '   ';
      expect(state.validate(), contains('Descreva o que ocorreu'));

      state.description = 'Vômito após refeição';
      expect(state.validate(), isNull);
    });

    test('rejects future date', () {
      final state = ClinicalIncidentFormState();
      state.openNewCase = true;
      state.category = IncidentCategory.allergic;
      state.description = 'Picada de inseto';
      state.occurredAt = DateTime.now().add(const Duration(hours: 1));

      expect(state.validate(), contains('futuro'));
    });

    test('builds command with stable operation ids per attempt', () {
      final state = ClinicalIncidentFormState();
      state.openNewCase = true;
      state.caseTitle = 'Caso Emergencial';
      state.category = IncidentCategory.trauma;
      state.severity = IncidentSeverity.severe;
      state.description = 'Queda de nível';
      state.initialConductNotes = 'Imobilização';
      state.conductActions.add(IncidentConductAction.firstAidApplied);
      state.hasOperationalImpact = true;
      state.veterinarianName = 'Dra. Maria';

      final cmd1 = state.toCommand(dogId: 'dog-42');
      final cmd2 = state.toCommand(dogId: 'dog-42');

      expect(cmd1.operationId, cmd2.operationId);
      expect(cmd1.finalizeOperationId, cmd2.finalizeOperationId);
      expect(cmd1.caseTitle, 'Caso Emergencial');
      expect(cmd1.professional?.name, 'Dra. Maria');
      expect(cmd1.hasOperationalImpact, isTrue);

      state.completeAttempt();
      final cmd3 = state.toCommand(dogId: 'dog-42');
      expect(cmd3.operationId, isNot(cmd1.operationId));
    });
  });
}
