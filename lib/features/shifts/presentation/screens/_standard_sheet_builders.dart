part of 'dynamic_activity_sheet.dart';

extension _StandardSheetBuilders on _DynamicActivitySheetState {
  Widget _buildStandardFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      children: [
        _buildTopActionRow(),
        const SizedBox(height: 16),
        _buildLocationTimeRow(),
        const SizedBox(height: 32),
        ..._buildDynamicFields(),
        ..._buildCategorySpecificFields(),
        ..._buildStandardContextFields(),
        ..._buildTrainingMetaFields(),
        ..._buildHealthMetaFields(),
        const SizedBox(height: 24),
        _buildDescriptionField(),
        const SizedBox(height: 24),
        _buildImageGallery(),
        const SizedBox(height: 48),
        _buildSaveButton(tColor),
      ],
    );
  }
}
