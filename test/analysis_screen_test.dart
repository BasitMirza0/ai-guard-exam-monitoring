import 'dart:async';
import 'dart:typed_data';
import 'package:aicheat/models/detection_result.dart';
import 'package:aicheat/screens/detection_screen.dart';
import 'package:aicheat/screens/video_detection_screen.dart';
import 'package:aicheat/services/api_service.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class _Api extends ApiService {
  final image = Completer<DetectionResult>();
  bool closed = false;
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<DetectionResult> detectImageFromBytes(
    Uint8List bytes,
    String fileName,
  ) => image.future;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _Picker extends ImagePicker {
  int picks = 0;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    picks++;
    return XFile.fromData(
      img.encodePng(img.Image(width: 4, height: 4)),
      name: 'demo.png',
    );
  }
}

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
);

void main() {
  Widget app(Widget screen) => MaterialApp(theme: AppTheme.light, home: screen);

  testWidgets(
    'Image actions lock during analysis and late completion cannot update a disposed screen',
    (tester) async {
      final api = _Api();
      final picker = _Picker();
      await tester.pumpWidget(
        app(DetectionScreen(apiService: api, imagePicker: picker)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gallery'));
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Detect'));
      await tester.tap(find.text('Detect'));
      await tester.pump();
      final gallery = tester.widget<ElevatedButton>(button('Gallery'));
      expect(gallery.onPressed, isNull);
      expect(picker.picks, 1);
      await tester.pumpWidget(const SizedBox());
      expect(api.closed, isTrue);
      api.image.complete(
        const DetectionResult(
          violationsFound: false,
          totalDetections: 0,
          totalViolations: 0,
          inferenceTimeMs: 1,
          violations: [],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Image failure unlocks retry and never presents an all-clear result',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        app(DetectionScreen(apiService: api, imagePicker: _Picker())),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gallery'));
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Detect'));
      await tester.tap(find.text('Detect'));
      await tester.pump();
      api.image.completeError(const ApiException('Service unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Service unavailable'), findsOneWidget);
      expect(find.text('All Clear!'), findsNothing);
      expect(
        tester.widget<ElevatedButton>(button('Detect')).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    for (final video in [false, true]) {
      testWidgets(
        '${video ? 'Video' : 'Image'} screen at $size with large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = _Api();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: child!,
                  ),
              home:
                  video
                      ? VideoDetectionScreen(apiService: api)
                      : DetectionScreen(apiService: api),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(video ? 'Analyze' : 'Detect'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<ElevatedButton>(button(video ? 'Analyze' : 'Detect'))
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(const SizedBox());
          expect(api.closed, isTrue);
        },
      );
    }
  }
}
