part of 'user_management_screen.dart';

class _UserFormSheet extends StatefulWidget {
  final UserModel? user;

  const _UserFormSheet({this.user});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  late final TextEditingController _raController;
  late final TextEditingController _nameController;
  late final TextEditingController _callsignController;
  late final TextEditingController _unitController;

  final _picker = ImagePicker();
  final _storageService = StorageService();

  bool _isSaving = false;
  File? _imageFile;
  late String _accessLevel;
  String? _currentPhotoUrl;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _raController = TextEditingController(text: user?.ra ?? '');
    _nameController = TextEditingController(text: user?.name ?? '');
    _callsignController = TextEditingController(text: user?.callsign ?? '');
    _unitController = TextEditingController(text: user?.unit ?? '');
    _accessLevel = user?.accessLevel ?? 'Condutor';
    _currentPhotoUrl = user?.photoUrl;
  }

  @override
  void dispose() {
    _raController.dispose();
    _nameController.dispose();
    _callsignController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked != null && mounted) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (_raController.text.trim().isEmpty ||
        _callsignController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty) {
      return;
    }

    setState(() => _isSaving = true);
    String? finalPhotoUrl = _currentPhotoUrl;

    try {
      if (_imageFile != null) {
        if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
          try {
            await _storageService.deleteImageFromUrl(_currentPhotoUrl!);
          } catch (_) {}
        }
        finalPhotoUrl = await _storageService.uploadProfileImage(
          _imageFile!,
          'users',
        );
      }

      final newUser = UserModel(
        ra: _raController.text.trim(),
        name: _nameController.text.trim(),
        callsign: _callsignController.text.trim(),
        unit: _unitController.text.trim(),
        accessLevel: _accessLevel,
        photoUrl: finalPhotoUrl,
        userBadges: widget.user?.userBadges ?? const [],
        xp: widget.user?.xp ?? 0,
      );

      if (!mounted) return;
      await Provider.of<UserViewModel>(
        context,
        listen: false,
      ).saveUser(newUser);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Editar Condutor' : 'Novo Condutor',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _UserFormAvatar(
              imageFile: _imageFile,
              currentPhotoUrl: _currentPhotoUrl,
              onPickImage: _pickImage,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _raController,
              enabled: !_isEditing,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'R.A.',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _callsignController,
              decoration: const InputDecoration(
                labelText: 'Nome de Guerra',
                prefixIcon: Icon(Icons.military_tech_outlined),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Unidade',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nível de Acesso',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _UserAccessLevelPicker(
              accessLevel: _accessLevel,
              onChanged: (value) => setState(() => _accessLevel = value),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('SALVAR'),
            ),
          ],
        ),
      ),
    );
  }
}
