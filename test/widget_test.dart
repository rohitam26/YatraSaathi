import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'has_completed_onboarding_v2': true,
    });
  });

  testWidgets('STOP Vanthachu home screen displays key sections and navigates to planner', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const YatraSaathiApp());
    await tester.pumpAndSettle();

    // Verify AppBar title and dashboard header.
    expect(find.widgetWithText(AppBar, 'STOP Vanthachu'), findsOneWidget);
    expect(find.text('STOP Vanthachu'), findsNWidgets(2));

    // Verify Active Journey status card.
    expect(find.text('Active Journey'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('No journey currently being tracked.'), findsOneWidget);

    // Verify Journey Stops and empty state.
    expect(find.text('Journey Stops'), findsOneWidget);
    expect(find.text('No upcoming stops configured.'), findsOneWidget);

    // Verify Create/Plan Journey action buttons exist.
    expect(find.text('Plan a Journey'), findsOneWidget);
    expect(find.text('New Journey'), findsOneWidget);
    expect(find.byIcon(Icons.add_road), findsOneWidget);
    expect(find.text('Plan Journey'), findsOneWidget);

    // Tap the Plan a Journey button to navigate to the wizard.
    await tester.tap(find.text('Plan a Journey'));
    await tester.pumpAndSettle();

    // Verify we have navigated to the Journey Wizard Screen.
    expect(find.text('Plan a Journey'), findsOneWidget); // Wizard AppBar title
    expect(find.text('Name Your Journey'), findsOneWidget);
    expect(find.text('Journey Name *'), findsOneWidget);
    expect(find.text('Starting Point'), findsWidgets);
    expect(find.text('Final Destination'), findsWidgets);
    expect(find.text('Next Step'), findsOneWidget);
  });
}
