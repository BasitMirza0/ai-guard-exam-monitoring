import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:aicheat/screens/dashboard/student_dashboard.dart';
import 'package:aicheat/screens/detection_screen.dart';
import 'package:aicheat/screens/video_detection_screen.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:aicheat/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  scrollBehavior: const AppScrollBehavior(),
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
  home: child,
);
void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1200, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Workspace actions work at $size and text scale $scale', (
        tester,
      ) async {
        setSize(tester, size);
        final actions = <String>[];
        await tester.pumpWidget(
          app(
            StudentWorkspace(
              name: 'Alex Smith with a long display name',
              email: 'alex.long.email@example.com',
              onLogout: () => actions.add('logout'),
              onLive: () => actions.add('live'),
              onExam: () => actions.add('exam'),
              onImage: () => actions.add('image'),
              onVideo: () => actions.add('video'),
              recentActivity: const Text('Recent record'),
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final item in [
          ('Live detection', 'live'),
          ('Start an exam', 'exam'),
          ('Image analysis', 'image'),
          ('Video analysis', 'video'),
        ]) {
          await tester.scrollUntilVisible(
            find.text(item.$1),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(item.$1));
          await tester.pumpAndSettle();
          expect(actions.last, item.$2);
        }
        await tester.tap(find.byTooltip('Sign out'));
        expect(actions.last, 'logout');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Avatar shows the downloaded Google photo and limits decode size',
    (tester) async {
      final client = _ImageClient();
      debugNetworkImageHttpClientProvider = () => client;
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: ProfileAvatar(
              photoUrl: 'https://example.com/avatar.png',
              name: 'Alex Smith',
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(client.requested?.path, '/avatar.png');
      expect(find.text('AS'), findsNothing);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<ResizeImage>(),
      );
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets('Failed avatar download keeps a stable initials fallback', (
    tester,
  ) async {
    debugNetworkImageHttpClientProvider = () => _ImageClient(fail: true);
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: ProfileAvatar(
            photoUrl: 'https://example.com/missing.png',
            name: 'Alex Smith',
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('AS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('Missing avatar uses a professional default', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: ProfileAvatar())));
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  for (final video in [false, true]) {
    testWidgets(
      '${video ? 'Video' : 'Image'} analysis header and actions fit small screens',
      (tester) async {
        setSize(tester, const Size(320, 568));
        await tester.pumpWidget(
          app(
            video ? const VideoDetectionScreen() : const DetectionScreen(),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(video ? 'Video analysis' : 'Image analysis'),
          findsOneWidget,
        );
        expect(find.text('Analysis tools'), findsOneWidget);
        final action = find.text(video ? 'Select Video' : 'Gallery');
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _ImageClient implements HttpClient {
  _ImageClient({this.fail = false});
  final bool fail;
  Uri? requested;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requested = uri;
    return _ImageRequest(fail);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.fail);
  final bool fail;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(fail);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.fail);
  final bool fail;
  final Uint8List bytes = Uint8List.fromList(
    img.encodePng(
      img.Image(width: 2, height: 2)..setPixelRgb(0, 0, 120, 150, 100),
    ),
  );
  @override
  int get statusCode => fail ? 404 : 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
