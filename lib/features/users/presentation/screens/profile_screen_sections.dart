part of 'profile_screen.dart';

extension _ProfileScreenSections on _ProfileScreenState {
  Widget _buildProfileHeroSliver({
    required String? photoStr,
    required String callsign,
    required String nameStr,
    required String raStr,
    required int level,
    required int xp,
  }) {
    return _ProfileHeroSliver(
      photoStr: photoStr,
      newPhotoFile: _newPhotoFile,
      callsign: callsign,
      nameStr: nameStr,
      raStr: raStr,
      level: level,
      xp: xp,
      isEditMode: _isEditMode,
      onToggleEditMode: () => _toggleEditMode(callsign, nameStr),
      onPickPhoto: _pickPhoto,
    );
  }

  Widget _buildProfileEditSliver({
    required String raStr,
    required UserModel? userModel,
    required AuthViewModel authVM,
    required UserViewModel userVM,
  }) {
    return _ProfileEditSliver(
      nameController: _nameController,
      callsignController: _callsignController,
      raStr: raStr,
      isSaving: _isSaving,
      onSave: () {
        HapticFeedback.mediumImpact();
        _saveChanges(userModel, authVM, userVM);
      },
    );
  }

  Widget _buildIdentificationSliver({
    required String callsign,
    required String nameStr,
    required String raStr,
    required UserModel? userModel,
  }) {
    return _ProfileIdentificationSliver(
      callsign: callsign,
      nameStr: nameStr,
      raStr: raStr,
      userModel: userModel,
      isEditMode: _isEditMode,
    );
  }
}
