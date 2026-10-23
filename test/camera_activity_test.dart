import 'package:aicheat/navigation/clean_page_transitions.dart';
import 'package:aicheat/services/camera_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Owner extends StatefulWidget {
  const _Owner(this.changes);
  final List<bool> changes;
  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> with CameraActivity<_Owner> {
  @override
  void onCameraActivityChanged() => widget.changes.add(cameraActive);
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Camera'));
}

void main() {
  testWidgets(
    'Camera activity suspends behind another route and resumes on Back',
    (tester) async {
      final changes = <bool>[];
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [appRouteObserver],
          home: _Owner(changes),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      );
      await tester.pumpAndSettle();
      expect(changes.last, isFalse);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(changes.last, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Camera activity suspends in the background and removes observers on disposal',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: _Owner(changes),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(changes.last, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(changes.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      final count = changes.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(changes, hasLength(count));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
