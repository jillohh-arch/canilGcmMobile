part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetActions on _DynamicActivitySheetState {
  void _selectSubtype(String type, {String? imagePath}) {
    HapticFeedback.lightImpact();
    _updateState(() {
      _selectedSubtype = type;
      _selectedSubtypeImagePath =
          imagePath ?? 'assets/images/k9_tactical_background.png';
      _formData.clear();
      _showMenu = false;
    });
  }
}
