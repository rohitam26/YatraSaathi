import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('YatraSaathi home screen displays key sections and navigates to planner', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const YatraSaathiApp());
    await tester.pumpAndSettle();

    // Verify AppBar title.
    expect(find.text('YatraSaathi'), findsOneWidget);

    // Verify Active Journey status card.
    expect(find.text('Active Journey'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('No active journey in progress.'), findsOneWidget);

    // Verify Upcoming Stops and empty state.
    expect(find.text('Upcoming Stops'), findsOneWidget);
    expect(find.text('No Stops Planned'), findsOneWidget);

    // Verify Create Journey action buttons exist.
    expect(find.text('Create Journey'), findsOneWidget);
    expect(find.text('New Journey'), findsOneWidget);
    expect(find.byIcon(Icons.add_road), findsOneWidget);
    expect(find.byTooltip('Create Journey'), findsOneWidget);

    // Tap the Create Journey button to navigate to the planner.
    await tester.tap(find.text('Create Journey'));
    await tester.pumpAndSettle();

    // Verify we have navigated to the Journey Planner Screen.
    expect(find.text('Create Journey'), findsOneWidget); // AppBar title
    expect(find.text('Journey Title'), findsOneWidget);
    expect(find.text('Stops (0)'), findsOneWidget);
    expect(find.text('Add Stop'), findsOneWidget);
  });
}
