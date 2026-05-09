part of 'occurrence_close_wizard.dart';

class _DrugEntry {
  String type;
  final TextEditingController quantityController;

  _DrugEntry() : type = 'Maconha', quantityController = TextEditingController();

  void dispose() {
    quantityController.dispose();
  }
}

class _ResultOption {
  final String label;
  final IconData icon;
  final Color color;

  const _ResultOption({
    required this.label,
    required this.icon,
    required this.color,
  });
}
