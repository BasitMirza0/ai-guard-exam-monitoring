import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aicheat/screens/auth/login_screen.dart';
import 'package:aicheat/screens/auth/signup_screen.dart';

void main() {
  testWidgets('Login fits a narrow screen and toggles password visibility', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
  });

  testWidgets(
    'Signup supports role selection and matching password validation',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
      await tester.ensureVisible(find.text('Teacher'));
      await tester.tap(find.text('Teacher'));
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Teacher'))
            .selected,
        isTrue,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Alex Smith');
      await tester.enterText(fields.at(1), 'alex@example.com');
      await tester.enterText(fields.at(2), 'password1');
      await tester.enterText(fields.at(3), 'password2');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Wide login shows the companion panel', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('A fairer exam.\nA clearer future.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
