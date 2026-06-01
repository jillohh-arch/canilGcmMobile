import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

class ActivityFormScaffold extends StatelessWidget {
  final String title;
  final String? imagePath;
  final String? heroTag;
  final bool isSaving;
  final Widget child;
  final VoidCallback onBack;

  const ActivityFormScaffold({
    super.key,
    required this.title,
    required this.imagePath,
    required this.heroTag,
    required this.isSaving,
    required this.child,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.surfaceModal,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
              onPressed: isSaving ? null : onBack,
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              title: Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath != null && heroTag != null)
                    Hero(
                      tag: heroTag!,
                      child: Image.asset(
                        imagePath!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    )
                  else
                    Container(color: AppTheme.surfaceModal),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.transparent, AppTheme.background],
                        stops: [0.3, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(color: AppTheme.background, child: child),
          ),
        ],
      ),
    );
  }
}
