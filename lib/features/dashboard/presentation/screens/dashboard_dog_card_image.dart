part of 'dashboard_screen.dart';

class _DogCardImage extends StatelessWidget {
  final String? imageUrl;
  final double iconSize;
  final int iconAlpha;
  final AlignmentGeometry alignment;

  const _DogCardImage({
    required this.imageUrl,
    required this.iconSize,
    required this.iconAlpha,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return Image.network(imageUrl!, fit: BoxFit.cover, alignment: alignment);
    }

    return Container(
      color: _hudPanelAlt,
      child: Center(
        child: FaIcon(
          FontAwesomeIcons.dog,
          size: iconSize,
          color: _hudCyan.withAlpha(iconAlpha),
        ),
      ),
    );
  }
}
