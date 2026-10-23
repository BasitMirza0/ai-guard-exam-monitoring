import 'package:aicheat/theme/app_theme.dart';
import 'package:aicheat/widgets/admin_workspace.dart';
import 'package:aicheat/widgets/app_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 600.0, 1024.0, 1440.0]) {
    testWidgets('Admin workspace fits $width and supports navigation', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder:
                (context, setState) => AdminWorkspace(
                  name: 'Alex Morgan',
                  selected: selected,
                  onSelect: (value) => setState(() => selected = value),
                  onSignOut: () => signedOut = true,
                  stats: const SizedBox(
                    height: 100,
                    child: Text('Workspace metrics'),
                  ),
                  content: const AppStateView(
                    icon: Icons.check_circle_outline,
                    title: 'You’re all caught up',
                    subtitle: 'New requests appear here.',
                  ),
                ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(find.text('People & access'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width < 1000) {
        await tester.tap(find.byTooltip('Sign out'));
      } else {
        // The desktop action is a text button rather than a compact icon.
        await tester.tap(find.text('Sign out'));
      }
      expect(signedOut, isTrue);
    });
  }
}
