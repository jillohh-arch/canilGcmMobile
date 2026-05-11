part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _forwardingEventCategory() {
  return const OccurrenceEventCategory(
    title: 'Encaminhamento',
    icon: Icons.local_hospital_rounded,
    color: Color(0xFFFF3B5C),
    actions: [
      OccurrenceQuickAction(
        title: 'Parte conduzida',
        description: 'Parte conduzida para providências posteriores.',
        icon: Icons.person_rounded,
        color: Color(0xFFFF8A3D),
      ),
      OccurrenceQuickAction(
        title: 'Encaminhado à Santa Casa',
        description: 'Parte encaminhada à Santa Casa para atendimento.',
        icon: Icons.local_hospital_rounded,
        color: Color(0xFFFF3B5C),
      ),
      OccurrenceQuickAction(
        title: 'Encaminhado à UPA',
        description: 'Parte encaminhada à UPA para atendimento.',
        icon: Icons.medical_services_rounded,
        color: Color(0xFFFF3B5C),
      ),
      OccurrenceQuickAction(
        title: 'Apresentado no DP',
        description: 'Ocorrência apresentada no Distrito Policial.',
        icon: Icons.account_balance_rounded,
        color: Color(0xFF4FA3FF),
      ),
    ],
  );
}
