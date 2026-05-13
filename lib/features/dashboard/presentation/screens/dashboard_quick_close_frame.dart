part of 'dashboard_screen.dart';

class _QuickCloseSheetFrame extends StatelessWidget {
  final double bottomInset;
  final Widget child;

  const _QuickCloseSheetFrame({required this.bottomInset, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomInset + 16,
        top: 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161618),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}
