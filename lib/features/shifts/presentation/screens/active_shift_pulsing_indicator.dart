part of 'active_shift_dashboard_screen.dart';

class _PulsingIndicator extends StatefulWidget {
  const _PulsingIndicator();

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 2, end: 10).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _hudGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _hudGreen.withAlpha(150),
                    blurRadius: _animation.value,
                    spreadRadius: _animation.value / 2,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          'EM PATRULHA',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _hudGreen,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
