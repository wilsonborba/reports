import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reports_ui/main.dart';

/// Opens the whole app at [path] with a window of [size]. With [reduce] the platform asks
/// for reduced motion. Tall windows let every public section come into view.
Future<void> openPublic(WidgetTester tester, String path, {Size size = const Size(1440, 4000), bool reduce = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      reduce ? const FakeAccessibilityFeatures(disableAnimations: true) : const FakeAccessibilityFeatures();
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(ReportsApp(initialLocation: path));
  await tester.pumpAndSettle();
}
