part of 'profile_screen.dart';

class _ProfileHeroContent extends StatelessWidget {
  final String? photoStr;
  final File? newPhotoFile;
  final String callsign;
  final String nameStr;
  final String raStr;
  final int level;
  final int xp;
  final bool isEditMode;
  final Future<void> Function() onPickPhoto;

  const _ProfileHeroContent({
    required this.photoStr,
    required this.newPhotoFile,
    required this.callsign,
    required this.nameStr,
    required this.raStr,
    required this.level,
    required this.xp,
    required this.isEditMode,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _ProfileAvatar(
            photoStr: photoStr,
            newPhotoFile: newPhotoFile,
            callsign: callsign,
            isEditMode: isEditMode,
            onPickPhoto: onPickPhoto,
          ),
          const SizedBox(height: 12),
          _ProfileIdentityBlock(
            callsign: callsign,
            nameStr: nameStr,
            raStr: raStr,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? photoStr;
  final File? newPhotoFile;
  final String callsign;
  final bool isEditMode;
  final Future<void> Function() onPickPhoto;

  const _ProfileAvatar({
    required this.photoStr,
    required this.newPhotoFile,
    required this.callsign,
    required this.isEditMode,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = newPhotoFile != null
        ? FileImage(newPhotoFile!) as ImageProvider
        : (photoStr != null ? CachedNetworkImageProvider(photoStr!) : null);

    return GestureDetector(
      onTap: isEditMode ? () => onPickPhoto() : null,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _hudCyan, width: 3),
              boxShadow: [
                BoxShadow(
                  color: _hudCyan.withAlpha(60),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 52,
              backgroundColor: _hudPanelAlt,
              backgroundImage: image,
              child: image == null
                  ? Text(
                      callsign.isNotEmpty ? callsign[0].toUpperCase() : 'O',
                      style: GoogleFonts.inter(
                        fontSize: 36,
                        color: _hudCyan,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
          if (isEditMode)
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hudCyan,
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: 16,
                color: _hudBackground,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileIdentityBlock extends StatelessWidget {
  final String callsign;
  final String nameStr;
  final String raStr;

  const _ProfileIdentityBlock({
    required this.callsign,
    required this.nameStr,
    required this.raStr,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          callsign.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.8,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
        if (nameStr.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              nameStr,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white60,
                fontWeight: FontWeight.w500,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'RA: $raStr',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: _hudCyan.withAlpha(180),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
