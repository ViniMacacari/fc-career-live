import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/BackgroundData.dart';
import 'package:mcmanager/utils/PlayerValueHistory.dart';

Future<String?> _queued(({SendPort port, int id}) job) async {
  job.port.send('start${job.id}');
  await Future<void>.delayed(const Duration(milliseconds: 20));
  job.port.send('end${job.id}');
  if (job.id == 1) throw StateError('failed job');
  return Isolate.current.debugName;
}

Map<String, Map<String, Object?>> _latest(List<Map<String, Object?>> rows) =>
    PlayerValueHistory.latest(rows, [], 'Overall');

int _square(int number) => number * number;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CPU jobs run outside the UI isolate, serialize and recover from errors',
    () async {
      final port = ReceivePort();
      final events = <Object?>[];
      final subscription = port.listen(events.add);
      final first = BackgroundData.run(_queued, (
        port: port.sendPort,
        id: 0,
      ), label: 'first');
      final failing = BackgroundData.run(_queued, (
        port: port.sendPort,
        id: 1,
      ), label: 'second');
      final third = BackgroundData.run(_queued, (
        port: port.sendPort,
        id: 2,
      ), label: 'third');
      final failed = expectLater(failing, throwsStateError);
      expect(await first, isNot(Isolate.current.debugName));
      await failed;
      expect(await third, isNot(Isolate.current.debugName));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['start0', 'end0', 'start1', 'end1', 'start2', 'end2']);
      await subscription.cancel();
      port.close();
    },
  );

  test(
    'The UI event loop keeps ticking during a large history calculation',
    () async {
      final rows = <Map<String, Object?>>[
        for (var player = 0; player < 4000; player++)
          for (var month = 1; month <= 12; month++)
            {
              'customPlayerId': 'p$player',
              'overall': 60 + month,
              'date': '2028-${month.toString().padLeft(2, '0')}-01',
            },
      ];
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      final latest = await BackgroundData.run(
        _latest,
        rows,
        label: 'large history',
      );
      timer.cancel();
      expect(ticks, greaterThan(0));
      expect(latest.length, 4000);
      expect(latest.values.every((r) => r['overall'] == 72), isTrue);
    },
  );

  test('Large UTF-8 API and saved JSON preserve Unicode and errors release the worker queue', () async {
    final data = {
      'name': 'São Paulo 🏆',
      'players': [
        for (var i = 0; i < 3000; i++) {'id': i, 'name': 'Jogador $i'},
      ],
    };
    final source = jsonEncode(data);
    expect(source.length, greaterThan(65536));
    expect(
      await BackgroundData.jsonBytes(Uint8List.fromList(utf8.encode(source))),
      data,
    );
    await expectLater(
      BackgroundData.jsonString('${' ' * 65536}invalid'),
      throwsFormatException,
    );
    expect(await BackgroundData.jsonString(source), data);
  });

  testWidgets('A widget zone can submit and finish a background job', (
    tester,
  ) async {
    int? result;
    BackgroundData.run(
      _square,
      2,
      label: 'widget zone',
    ).then((value) => result = value);
    final clock = Stopwatch()..start();
    while (result == null && clock.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(result, 4);
    expect(BackgroundData.pendingJobs, 0);
  });

  test('A subsequent zone can reuse the completed queue link', () async {
    expect(await BackgroundData.run(_square, 3, label: 'subsequent zone'), 9);
  });
}
