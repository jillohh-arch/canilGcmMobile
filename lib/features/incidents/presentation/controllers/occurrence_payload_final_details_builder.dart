import 'occurrence_payload_field_writer.dart';

class OccurrencePayloadFinalDetailsBuilder {
  const OccurrencePayloadFinalDetailsBuilder._();

  static Map<String, dynamic> build({
    required List<Map<String, dynamic>> drugRows,
    required List<Map<String, dynamic>> detainedIndividuals,
    required List<Map<String, dynamic>> seizedObjects,
    required List<Map<String, dynamic>> detainedVehicles,
  }) {
    final details = <String, dynamic>{};

    final detained = detainedIndividuals
        .map(
          (row) => {
            'quantidade': OccurrencePayloadFieldWriter.text(row['quantidade']),
          },
        )
        .where((row) => (row['quantidade'] ?? '').isNotEmpty)
        .toList();
    if (detained.isNotEmpty) {
      details['individuosDetidos'] = detained;
    }

    final objects = seizedObjects
        .map(
          (row) => {
            'descricao': OccurrencePayloadFieldWriter.text(row['descricao']),
            'quantidade': OccurrencePayloadFieldWriter.text(row['quantidade']),
          },
        )
        .where(
          (row) =>
              (row['descricao'] ?? '').isNotEmpty ||
              (row['quantidade'] ?? '').isNotEmpty,
        )
        .toList();
    if (objects.isNotEmpty) {
      details['objetosApreendidos'] = objects;
    }

    final drugs = buildDrugDetails(drugRows);
    if (drugs.isNotEmpty) {
      details['drogasApreendidas'] = drugs;
    }

    final vehicles = detainedVehicles
        .map(
          (row) => {
            'tipo': OccurrencePayloadFieldWriter.text(row['tipo']),
            'placa': OccurrencePayloadFieldWriter.text(row['placa']),
          },
        )
        .where(
          (row) =>
              (row['tipo'] ?? '').isNotEmpty || (row['placa'] ?? '').isNotEmpty,
        )
        .toList();
    if (vehicles.isNotEmpty) {
      details['veiculosDetidos'] = vehicles;
    }

    return details;
  }

  static List<Map<String, dynamic>> buildDrugDetails(
    List<Map<String, dynamic>> drugRows,
  ) {
    return drugRows
        .map(
          (row) => {
            'tipo': row['tipo'] == 'Outros'
                ? OccurrencePayloadFieldWriter.text(row['especificar'])
                : row['tipo'],
            'quantidade': OccurrencePayloadFieldWriter.text(row['quantidade']),
          },
        )
        .where(
          (row) =>
              (row['tipo'] ?? '').toString().isNotEmpty ||
              (row['quantidade'] ?? '').toString().isNotEmpty,
        )
        .toList();
  }
}
