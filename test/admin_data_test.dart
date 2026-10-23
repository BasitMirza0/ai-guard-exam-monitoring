// Test doubles supply snapshots without connecting to a live Firebase project.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:aicheat/screens/dashboard/admin_dashboard.dart';
import 'package:aicheat/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  Document(this.id, this.values);
  @override
  final String id;
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> data() => values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Profiles requiring approval on mobile appear in admin approvals and counts',
    (tester) async {
      final users = StreamController<QuerySnapshot>.broadcast();
      final violations = StreamController<QuerySnapshot>.broadcast();
      addTearDown(users.close);
      addTearDown(violations.close);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboard(
            adminName: 'Admin',
            usersStream: users.stream,
            violationsStream: violations.stream,
          ),
        ),
      );
      violations.add(Snapshot([]));
      users.add(Snapshot([]));
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);

      String? countFor(String label) {
        final column =
            tester
                .element(find.text(label))
                .findAncestorWidgetOfExactType<Column>()!;
        return (column.children.first as Text).data;
      }

      for (final statusFields in <Map<String, dynamic>>[
        {},
        {'status': null},
        {'status': ''},
        {'status': 'pending'},
        {'status': ' Pending '},
        {'status': 'unexpected_status'},
        {'status': 'pending', 'role': 'teacher'},
      ]) {
        users.add(
          Snapshot([
            Document('student', {
              'name': 'New Student',
              'email': 'student@example.com',
              'role': 'student',
              ...statusFields,
            }),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('New Student'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
        expect(find.text('You’re all caught up'), findsNothing);
        expect(countFor('Awaiting review'), '1');
        expect(countFor('Total users'), '1');
        await tester.tap(find.text('Users'));
        await tester.pumpAndSettle();
        expect(find.text('Pending'), findsOneWidget);
        await tester.tap(find.text('Approvals'));
        await tester.pumpAndSettle();
      }

      for (final status in ['approved', 'rejected']) {
        users.add(
          Snapshot([
            Document('student', {
              'name': 'New Student',
              'role': 'student',
              'status': status,
            }),
          ]),
        );
        await tester.pumpAndSettle();
        expect(find.text('You’re all caught up'), findsOneWidget);
        expect(find.text('New Student'), findsNothing);
        expect(countFor('Awaiting review'), '0');
        expect(countFor('Total users'), '1');
      }
    },
  );

  testWidgets(
    'Late tab selection uses existing data and updates live without another event',
    (tester) async {
      final users = StreamController<QuerySnapshot>.broadcast();
      final violations = StreamController<QuerySnapshot>.broadcast();
      addTearDown(users.close);
      addTearDown(violations.close);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboard(
            adminName: 'Admin',
            usersStream: users.stream,
            violationsStream: violations.stream,
          ),
        ),
      );
      users.add(
        Snapshot([
          Document('person', {
            'name': 'Jordan',
            'email': 'jordan@example.com',
            'status': 'pending',
            'role': 'student',
          }),
        ]),
      );
      violations.add(
        Snapshot([
          Document('event', {
            'reason': 'Test recorded event',
            'studentEmail': 'jordan@example.com',
          }),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jordan'), findsOneWidget);
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(find.text('Jordan'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Violations').first);
      await tester.pumpAndSettle();
      expect(find.text('Test recorded event'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Approvals'));
      await tester.pumpAndSettle();
      users.add(
        Snapshot([
          Document('person', {'name': 'Jordan', 'status': 'approved'}),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);
      users.addError(StateError('Permission denied'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load this section'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
