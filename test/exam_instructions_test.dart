import 'package:aicheat/widgets/exam_instructions.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(240, 320),
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(600, 960),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Static exam rules at $size, text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var started = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
            home: Scaffold(
              body: SafeArea(
                child: ExamInstructions(onBegin: () => started = true),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);
        expect(find.text('Camera check'), findsNothing);
        expect(find.text('Begin Exam').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Begin Exam'));
        expect(started, isTrue);
      });
    }
  }
  testWidgets('Camera failure exposes retry without camera section', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExamInstructions(
            onBegin: null,
            error: 'Allow camera access to start your exam.',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
  });
}
