part of 'profile_screen.dart';

class _ProfileHeroSliver extends StatelessWidget {
  final String? photoStr;
  final File? newPhotoFile;
  final String callsign;
  final String nameStr;
  final String raStr;
  final int level;
  final int xp;
  final bool isEditMode;
  final VoidCallback onToggleEditMode;
  final Future<void> Function() onPickPhoto;

  const _ProfileHeroSliver({
    required this.photoStr,
    required this.newPhotoFile,
    required this.callsign,
    required this.nameStr,
    required this.raStr,
    required this.level,
    required this.xp,
    required this.isEditMode,
    required this.onToggleEditMode,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: _hudBackground,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.close_rounded : Icons.edit_rounded,
            color: Colors.white,
          ),
          onPressed: onToggleEditMode,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            _ProfileHeroBackground(photoStr: photoStr),
            _ProfileHeroOverlay(),
            _ProfileHeroContent(
              photoStr: photoStr,
              newPhotoFile: newPhotoFile,
              callsign: callsign,
              nameStr: nameStr,
              raStr: raStr,
              level: level,
              xp: xp,
              isEditMode: isEditMode,
              onPickPhoto: onPickPhoto,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeroBackground extends StatelessWidget {
  final String? photoStr;

  const _ProfileHeroBackground({required this.photoStr});

  @override
  Widget build(BuildContext context) {
    if (photoStr == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A2A1A), Color(0xFF0C1A2E)],
          ),
        ),
      );
    }

    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: CachedNetworkImage(
          imageUrl: photoStr!,
          fit: BoxFit.cover,
          color: Colors.black.withValues(alpha: 0.31),
        ),
      ),
    );
  }
}

class _ProfileHeroOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black45, _hudBackground.withAlpha(220)],
        ),
      ),
    );
  }
}

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
          const SizedBox(height: 12),
          _ProfileLevelChip(level: level, xp: xp),
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
                  color: _hudCyan.withAlpha(110),
                  blurRadius: 30,
                  spreadRadius: 3,
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
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _hudCyan,
              ),
              child: const Icon(
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
          style: GoogleFonts.oxanium(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.8,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
        if (nameStr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
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
          style: GoogleFonts.robotoMono(
            fontSize: 13,
            color: _hudCyan.withAlpha(180),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProfileLevelChip extends StatelessWidget {
  final int level;
  final int xp;

  const _ProfileLevelChip({required this.level, required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(215),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudAmber.withAlpha(170)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: _hudAmber, size: 16),
          const SizedBox(width: 6),
          Text(
            'NÍVEL $level • $xp XP',
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _hudAmber,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
