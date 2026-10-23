import 'dart:async';
import 'package:aicheat/branding/app_launch.dart';
import 'package:aicheat/branding/brand_mark.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Splash holds until startup and destination are ready, then removes its overlay',
    (tester) async {
      final startup = Completer<void>();
      late VoidCallback ready;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AppLaunch(
            initialize: () => startup.future,
            builder: (_, onReady) {
              ready = onReady;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      startup.complete();
      await tester.pump();
      expect(find.byType(BrandMark), findsOneWidget);
      ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BrandMark), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reduced motion skips reveal and tiny screens fit enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(240, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final startup = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
          home: AppLaunch(
            initialize: () => startup.future,
            builder:
                (_, ready) => LaunchDestination(
                  onReady: ready,
                  child: const Scaffold(body: Text('Home')),
                ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      startup.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(BrandMark), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets(
    'Startup failure shows a retry and successful retry enters the app',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AppLaunch(
            initialize: () async {
              if (attempts++ == 0) throw StateError('offline');
            },
            builder:
                (_, ready) => LaunchDestination(
                  onReady: ready,
                  child: const Scaffold(body: Text('Home')),
                ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(BrandMark), findsNothing);
    },
  );
}
