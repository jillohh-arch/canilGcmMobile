part of 'event_details_bottom_sheet.dart';

class _EvidenceActions extends StatelessWidget {
  final Color accentColor;
  final Color warningColor;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onCaptureLocation;

  const _EvidenceActions({
    required this.accentColor,
    required this.warningColor,
    required this.onAddPhotos,
    required this.onCaptureLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EventOutlineActionButton(
            label: 'FOTO',
            icon: Icons.add_a_photo_rounded,
            color: accentColor,
            onPressed: onAddPhotos,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _EventOutlineActionButton(
            label: 'GPS',
            icon: Icons.my_location_rounded,
            color: warningColor,
            onPressed: onCaptureLocation,
          ),
        ),
      ],
    );
  }
}
