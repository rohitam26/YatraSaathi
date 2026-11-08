import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/ui/permission_guidance_screen.dart';
import 'package:pathsaathi/ui/privacy_info_screen.dart';
import 'package:pathsaathi/ui/saved_journeys_screen.dart';
import 'package:pathsaathi/ui/settings_screen.dart';
import 'package:pathsaathi/ui/stop_config_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('UI Screens & Dialogs Verification', () {
    testWidgets('SavedJourneysScreen displays journeys and handles search filter', (
      WidgetTester tester,
    ) async {
      final repo = LocalJourneyRepository();
      final now = DateTime(2026, 11, 9);
      await repo.saveJourney(
        Journey(
          id: 'j1',
          name: 'Delhi Metro Express',
          createdAt: now,
          updatedAt: now,
          stops: [
            Stop(id: 's1', name: 'Rajiv Chowk', latitude: 28.6, longitude: 77.2, order: 0),
          ],
        ),
      );
      await repo.saveJourney(
        Journey(
          id: 'j2',
          name: 'Mumbai Suburban Rail',
          createdAt: now,
          updatedAt: now,
          stops: [
            Stop(id: 's2', name: 'Dadar', latitude: 19.0, longitude: 72.8, order: 0),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedJourneysScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Journeys'), findsOneWidget);
      expect(find.text('Delhi Metro Express'), findsOneWidget);
      expect(find.text('Mumbai Suburban Rail'), findsOneWidget);

      // Search filter test
      await tester.enterText(find.byType(SearchBar), 'Mumbai');
      await tester.pumpAndSettle();

      expect(find.text('Mumbai Suburban Rail'), findsOneWidget);
      expect(find.text('Delhi Metro Express'), findsNothing);
    });

    testWidgets('PermissionGuidanceScreen displays transparent Android permission descriptions', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: PermissionGuidanceScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Android Permissions Guide'), findsOneWidget);
      expect(find.text('Precise GPS Location'), findsOneWidget);
      expect(find.text('Foreground Location Service'), findsOneWidget);
      expect(find.text('System Notifications (Android 13+)'), findsOneWidget);
      expect(find.text('Haptic Vibration'), findsOneWidget);
      expect(find.text('Request Location Permission'), findsOneWidget);
      expect(find.text('Open Android System Settings'), findsOneWidget);
    });

    testWidgets('PrivacyInfoScreen displays 100% offline policies', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: PrivacyInfoScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy & Security'), findsOneWidget);
      expect(find.text('Zero Remote Cloud Storage'), findsOneWidget);
      expect(find.text('Local Real-Time GPS Processing'), findsOneWidget);
      expect(find.text('Transparent Android SMS Compliance'), findsOneWidget);
    });

    testWidgets('SettingsScreen displays sensitivity dropdowns and diagnostics', (
      WidgetTester tester,
    ) async {
      final repo = LocalJourneyRepository();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Arrival Detection Parameters'), findsOneWidget);
      expect(find.text('Required Consecutive GPS Samples'), findsOneWidget);
      expect(find.text('Minimum Station Dwell Time'), findsOneWidget);
      expect(find.text('Test Vibration'), findsOneWidget);
      expect(find.text('Test Audio Alert'), findsOneWidget);
    });

    testWidgets('StopConfigDialog renders Location, Alarm and Check-In tabs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StopConfigDialog(order: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title + Add Button both contain 'Add Stop'
      expect(find.text('Add Stop'), findsNWidgets(2));
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Alarm'), findsOneWidget);
      expect(find.text('Check-In'), findsOneWidget);
      expect(find.text('Stop Name'), findsOneWidget);

      // Tap Alarm tab
      await tester.tap(find.text('Alarm'));
      await tester.pumpAndSettle();
      expect(find.text('Sound Alert'), findsOneWidget);
      expect(find.text('Tactile Vibration'), findsOneWidget);

      // Tap Check-In tab
      await tester.tap(find.text('Check-In'));
      await tester.pumpAndSettle();
      expect(find.text('Arrival Check-In Message'), findsOneWidget);
    });
  });
}
