part of 'occurrence_event_center_sheet.dart';

class _EventCenterFrame extends StatelessWidget {
  final double bottomInset;
  final Color backgroundColor;
  final Color accentColor;
  final Widget child;

  const _EventCenterFrame({
    required this.bottomInset,
    required this.backgroundColor,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withAlpha(135)),
          boxShadow: [
            BoxShadow(color: accentColor.withAlpha(38), blurRadius: 24),
          ],
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}
