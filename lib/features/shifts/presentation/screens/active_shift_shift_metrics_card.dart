part of 'active_shift_dashboard_screen.dart';

class _ShiftMetricsCockpitCard extends StatefulWidget {
  final Dog dog;

  const _ShiftMetricsCockpitCard({required this.dog});

  @override
  State<_ShiftMetricsCockpitCard> createState() =>
      _ShiftMetricsCockpitCardState();
}

class _ShiftMetricsCockpitCardState extends State<_ShiftMetricsCockpitCard> {
  Timer? _timer;
  String _activeTimeText = '--h --m';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final startTime = shiftVM.shiftStartTime;
    if (startTime != null) {
      final diff = DateTime.now().difference(startTime);
      final hours = diff.inHours.toString().padLeft(2, '0');
      final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _activeTimeText = '${hours}h ${minutes}m ${seconds}s';
      });
    } else {
      setState(() {
        _activeTimeText = '--h --m';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayLogs = _countTodayRecords(context, widget.dog.id);

    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TEMPO ATIVO',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 0.9,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: _hudCyan, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _activeTimeText,
                    style: GoogleFonts.oxanium(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _hudCyan,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '$todayLogs registro${todayLogs == 1 ? '' : 's'} hoje',
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
