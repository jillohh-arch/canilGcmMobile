import 'package:flutter/material.dart';

import '../../models/incident.dart';
import 'occurrence_flow_form.dart';

class OccurrenceFlowScreen extends StatelessWidget {
  final String dogId;
  final String dogName;
  final Incident? incident;

  const OccurrenceFlowScreen({
    super.key,
    required this.dogId,
    this.dogName = '',
    this.incident,
  });

  @override
  Widget build(BuildContext context) {
    final data = incident?.toJson();
    if (incident != null && data != null) {
      data['_rawDate'] = incident!.startedAt;
      data['_rawHandlerId'] = incident!.handlerId;
    }

    return OccurrenceFlowForm(
      dogId: dogId,
      dogName: incident?.dogName.isNotEmpty == true
          ? incident!.dogName
          : dogName,
      initialData: data,
      documentId: incident?.id,
    );
  }
}
