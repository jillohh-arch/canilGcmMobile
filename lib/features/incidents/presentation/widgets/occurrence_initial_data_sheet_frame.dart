part of 'occurrence_initial_data_sheet.dart';

class _InitialDataSheetFrame extends StatelessWidget {
  final double bottomInset;
  final Color accentColor;
  final Color backgroundColor;
  final Widget child;

  const _InitialDataSheetFrame({
    required this.bottomInset,
    required this.accentColor,
    required this.backgroundColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withAlpha(125)),
        boxShadow: [
          BoxShadow(color: accentColor.withAlpha(35), blurRadius: 24),
        ],
      ),
      child: child,
    );
  }
}
