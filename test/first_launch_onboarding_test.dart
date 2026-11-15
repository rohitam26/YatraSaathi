import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/ui/first_launch_onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const notifChannel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'areNotificationsEnabled') return true;
      return true;
    });

    const geoChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geoChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'isLocationServiceEnabled') return true;
      if (methodCall.method == 'checkPermission') return 3; // whileInUse
      return true;
    });
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('FirstLaunchOnboardingScreen renders key steps and purpose notice', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: FirstLaunchOnboardingScreen(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify Title & Tagline
    expect(find.text('Setup & Permissions'), findsOneWidget);
    expect(find.text('Welcome to YatraSaathi'), findsOneWidget);
    expect(
      find.text('Your journey. Your check-ins. Your peace of mind.'),
      findsOneWidget,
    );

    // Verify Purpose explanation
    expect(
      find.textContaining('YatraSaathi uses your location to detect when you reach your journey stops'),
      findsOneWidget,
    );

    // Verify 3 Permission steps
    expect(find.text('1. GPS Hardware Service'), findsOneWidget);
    expect(find.text('2. Precise Location Permission'), findsOneWidget);
    expect(find.text('3. Arrival Notifications'), findsOneWidget);
  });

  testWidgets('Completing onboarding sets SharedPreferences flag', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool callbackInvoked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FirstLaunchOnboardingScreen(
          onCompleted: () => callbackInvoked = true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Tap "Get Started" or "Continue anyway"
    final getStartedButton = find.text('Get Started');
    final continueButton = find.text('Continue anyway (Limited Functionality)');
    final target = getStartedButton.evaluate().isNotEmpty ? getStartedButton : continueButton;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FirstLaunchOnboardingScreen.prefKeyCompleted), isTrue);
    expect(callbackInvoked, isTrue);
  });
}
