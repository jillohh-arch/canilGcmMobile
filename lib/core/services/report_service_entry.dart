part of 'report_service.dart';

class ReportEntry {
  final DateTime date;
  final String type;
  final String location;
  final String observations;

  const ReportEntry({
    required this.date,
    required this.type,
    required this.location,
    required this.observations,
  });
}
