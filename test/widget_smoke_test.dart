import 'package:classcast_offline/app.dart';
import 'package:classcast_offline/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boot gate: the real app must start without provider errors and reach
/// role selection. This catches startup crashes (e.g. "Provider not
/// found") on CI before any APK is built.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // SQLite is not available in the widget-test environment; the
    // SharedPreferences store exercises the same SessionStore API.
    setLocalStoreOverride(PrefsLocalStore());
  });

  tearDown(() => setLocalStoreOverride(null));

  testWidgets('app boots to role selection', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(),
        child: const ClassCastApp(),
      ),
    );
    // Splash (1.4s timer) then role selection.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Choose your role'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
  });

  testWidgets('tap Teacher opens teacher dashboard', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(),
        child: const ClassCastApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.text('Teacher'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Create New Session'), findsOneWidget);
    // The dashboard waits on a network probe with a timeout, so the timer has
    // to be allowed to fire or the test ends with a pending one.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tap Student opens join screen', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(),
        child: const ClassCastApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.text('Student'));
    // StudentShell uses an IndexedStack that eagerly builds the waiting
    // screen, which shows an endless CircularProgressIndicator. So we
    // cannot use pumpAndSettle() here — it would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Join Classroom'), findsWidgets);
  });

  testWidgets('teacher shell has a back button to role selection',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(),
        child: const ClassCastApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.text('Teacher'));
    await tester.pumpAndSettle();

    // The shell is the app's home route, so this back button must be an
    // explicit leading rather than an automaticallyImplyLeading arrow.
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your role'), findsOneWidget);
  });

  testWidgets('student join screen has a back button to role selection',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(),
        child: const ClassCastApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.text('Student'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    // Same IndexedStack caveat as above: avoid pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Choose your role'), findsOneWidget);
  });
}
