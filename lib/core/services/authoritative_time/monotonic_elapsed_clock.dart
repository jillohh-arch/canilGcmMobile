abstract interface class MonotonicElapsedClock {
  Duration get elapsed;
}

final class StopwatchMonotonicElapsedClock implements MonotonicElapsedClock {
  StopwatchMonotonicElapsedClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get elapsed => _stopwatch.elapsed;
}
