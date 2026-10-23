import 'dart:async';

/// Drops camera frames instead of queuing work. Preview remains at native FPS.
class FrameProcessor {
  FrameProcessor({this.interval = const Duration(milliseconds: 80)})
    : _clock = Stopwatch()..start();

  final Duration interval;
  final Stopwatch _clock;
  Duration _next = Duration.zero;
  bool _busy = false;
  bool _closed = false;

  Future<void> process(Future<void> Function() work) async {
    if (_closed || _busy || _clock.elapsed < _next) return;
    _busy = true;
    final start = _clock.elapsed;
    _next = start + interval;
    try {
      await work();
    } finally {
      // Leave a little CPU headroom when inference takes longer than its budget.
      final elapsed = _clock.elapsed;
      if (elapsed - start > interval) {
        _next = elapsed + const Duration(milliseconds: 20);
      }
      _busy = false;
    }
  }

  void close() => _closed = true;
}
