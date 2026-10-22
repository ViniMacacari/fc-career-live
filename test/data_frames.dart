import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/BackgroundData.dart';

Future<void> settleDataFrames(
  WidgetTester tester, {
  int minimumFrames = 20,
}) async {
  final clock = Stopwatch()..start();
  for (var frame = 0; clock.elapsed < const Duration(seconds: 10); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (frame >= minimumFrames &&
        BackgroundData.pendingJobs == 0 &&
        !tester.binding.hasScheduledFrame) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail(
    'Data loading did not settle: ${BackgroundData.pendingJobs} background jobs pending.',
  );
}
