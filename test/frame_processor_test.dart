import 'dart:async';
import 'package:aicheat/services/frame_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Slow inference drops incoming frames instead of building a backlog',
    () async {
      final frames = FrameProcessor(interval: Duration.zero);
      final pending = Completer<void>();
      var calls = 0;
      final first = frames.process(() {
        calls++;
        return pending.future;
      });
      for (var i = 0; i < 100; i++) {
        await frames.process(() async {
          calls++;
        });
      }
      expect(calls, 1);
      pending.complete();
      await first;
      frames.close();
    },
  );

  test(
    'Inference cadence drops excess frames and closing prevents more work',
    () async {
      final frames = FrameProcessor(interval: const Duration(seconds: 1));
      var calls = 0;
      await frames.process(() async {
        calls++;
      });
      await frames.process(() async {
        calls++;
      });
      expect(calls, 1);
      frames.close();
      await frames.process(() async {
        calls++;
      });
      expect(calls, 1);
    },
  );
}
