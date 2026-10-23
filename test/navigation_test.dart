import 'dart:ui' as ui;
import 'package:aicheat/navigation/clean_page_transitions.dart';
import 'package:aicheat/screens/dashboard/camera_screen.dart';
import 'package:aicheat/screens/dashboard/student_dashboard.dart';
import 'package:aicheat/screens/detection_screen.dart';
import 'package:aicheat/screens/live_detection_screen.dart';
import 'package:aicheat/screens/video_detection_screen.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;

void main() {
  for (final entry in <(String, Widget)>[
    ('Live detection', const LiveDetectionScreen()),
    ('Start an exam', const CameraScreen()),
    ('Image analysis', const DetectionScreen()),
    ('Video analysis', const VideoDetectionScreen()),
  ]) {
    testWidgets(
      '${entry.$1} returns a pixel-identical Home on the first Back frame',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        for (final channel in [
          'plugins.flutter.io/camera',
          'google_mlkit_face_detector',
          'google_mlkit_face_mesh_detector',
          'google_mlkit_image_labeler',
          'google_mlkit_object_detector',
        ]) {
          messenger.setMockMethodCallHandler(
            MethodChannel(channel),
            (_) async => channel == 'plugins.flutter.io/camera' ? [] : null,
          );
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              MethodChannel(channel),
              null,
            ),
          );
        }
        final navigator = GlobalKey<NavigatorState>();
        final boundary = GlobalKey();
        void open() => navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => entry.$2),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorKey: navigator,
              navigatorObservers: [appRouteObserver],
              theme: AppTheme.light,
              home: StudentWorkspace(
                name: 'Alex Smith',
                email: 'alex@example.com',
                onLogout: () {},
                onLive: open,
                onExam: open,
                onImage: open,
                onVideo: open,
                recentActivity: const Text('No recent activity'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = await pixels(tester, boundary);
        await tester.tap(find.text(entry.$1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pump();
        final after = await pixels(tester, boundary);
        expect(after, orderedEquals(before));
        await tester.pump();
        expect(find.byWidget(entry.$2), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
