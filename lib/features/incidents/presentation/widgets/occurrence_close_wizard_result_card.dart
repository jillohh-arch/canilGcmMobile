part of 'occurrence_close_wizard.dart';

class _ResultCard extends StatelessWidget {
  final double width;
  final _ResultOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.width,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? option.color.withAlpha(28)
                : const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? option.color : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: option.color.withAlpha(40), blurRadius: 14)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: option.color.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(option.icon, color: option.color, size: 20),
              ),
              const SizedBox(height: 9),
              Text(
                option.label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
