import 'package:aicheat/screens/auth/login_screen.dart';
import 'package:aicheat/screens/auth/signup_screen.dart';
import 'package:aicheat/screens/dashboard/pending_screen.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:aicheat/widgets/responsive_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget screen, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  scrollBehavior: const AppScrollBehavior(),
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
  home: screen,
);

void viewport(WidgetTester tester, Size size, {double ratio = 1}) {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final sizes = [
    const Size(240, 320),
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
    const Size(844, 390),
    const Size(1024, 600),
  ];
  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      for (final signup in [false, true]) {
        testWidgets(
          '${signup ? 'Signup' : 'Login'} at $size with text scale $scale',
          (tester) async {
            viewport(tester, size, ratio: 2);
            await tester.pumpWidget(
              app(
                signup ? const SignupScreen() : const LoginScreen(),
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.text('AI Guard Pro · Examination workspace'),
              findsNothing,
            );
            final action = find.text(
              signup ? 'Sign up with Google' : 'Continue with Google',
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'Keyboard leaves the auth header anchored and drag dismisses focus',
    (tester) async {
      viewport(tester, const Size(390, 844));
      await tester.pumpWidget(app(const LoginScreen()));
      final position = tester.getTopLeft(find.text('Welcome back.'));
      await tester.tap(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Welcome back.')), position);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isNot(true),
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Status screen scrolls on a short phone with large text', (
    tester,
  ) async {
    viewport(tester, const Size(320, 320));
    await tester.pumpWidget(
      app(const PendingScreen(status: 'pending'), scale: 2),
    );
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign Out').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Dashboard headers scroll to reveal list content on short screens',
    (tester) async {
      viewport(tester, const Size(320, 320));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: DashboardBody(
              headers: const [
                SizedBox(height: 240, child: Text('Dashboard header')),
              ],
              child: ListView.builder(
                itemCount: 40,
                itemBuilder:
                    (_, index) => ListTile(title: Text('Record $index')),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -280));
      await tester.pumpAndSettle();
      expect(find.text('Record 3').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Adaptive controls remain usable with enlarged text on narrow phones',
    (tester) async {
      viewport(tester, const Size(240, 400));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveGrid(
                children: [
                  for (var index = 0; index < 4; index++)
                    AdaptiveRow(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {},
                            child: const Text('Primary action'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {},
                            child: const Text('Secondary action'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.ensureVisible(find.text('Secondary action').last);
      await tester.pumpAndSettle();
      expect(find.text('Secondary action').last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
