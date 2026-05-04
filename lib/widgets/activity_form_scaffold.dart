import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF1E1E1E),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white,
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
                  color: Colors.white,
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
                    Container(color: const Color(0xFF1E1E1E)),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF121212)],
                        stops: [0.3, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(color: const Color(0xFF121212), child: child),
          ),
        ],
      ),
    );
  }
}
