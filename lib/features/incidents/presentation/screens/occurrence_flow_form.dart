import 'package:flutter/material.dart';

import 'package:canil_gcm/views/shifts/dynamic_activity_sheet.dart';

class OccurrenceFlowForm extends StatelessWidget {
  final String dogId;
  final String dogName;
  final Map<String, dynamic>? initialData;
  final String? documentId;

  const OccurrenceFlowForm({
    super.key,
    required this.dogId,
    this.dogName = '',
    this.initialData,
    this.documentId,
  });

  @override
  Widget build(BuildContext context) {
    return DynamicActivitySheet(
      category: 'Ocorrencia',
      dogId: dogId,
      dogName: dogName,
      initialData: initialData,
      documentId: documentId,
      fullScreen: true,
    );
  }
}
