import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/utils/Components/PlayerAvatar.dart';

void main() {
  Widget host(PlayerAvatar avatar) => MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3),
      child: Center(child: avatar),
    ),
  );

  testWidgets(
    'A large portrait decodes at avatar size and preserves its aspect ratio',
    (tester) async {
      final file = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.green, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2048, 3072);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory('build/avatar-memory-test')
            .create(recursive: true);
        final file = File(
          '${directory.absolute.path}/portrait-${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        return file;
      });
      addTearDown(PaintingBinding.instance.imageCache.clear);
      final size = await tester.runAsync(() async {
        await tester.pumpWidget(
          host(
            PlayerAvatar(
              fifaVersion: 'FC26',
              customAvatarFilePath: file!.path,
              radius: 26,
            ),
          ),
        );
        final widget = tester.widget<Image>(find.byType(Image));
        final completer = Completer<Size>();
        final stream = widget.image.resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            completer.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            );
            info.dispose();
          },
          onError: (Object error, StackTrace? stack) =>
              completer.completeError(error, stack),
        );
        stream.addListener(listener);
        try {
          return await completer.future.timeout(const Duration(seconds: 10));
        } finally {
          stream.removeListener(listener);
        }
      });
      expect(size, const Size(160, 240));
      expect(size!.width * size.height, lessThan(2048 * 3072 / 100));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Network photos use the same bounded decode size', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const PlayerAvatar(
          fifaVersion: 'FC26',
          realPlayerId: '158023',
          radius: 26,
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 160);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('A missing custom photo still shows a placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const PlayerAvatar(
          fifaVersion: 'FC26',
          customAvatarFilePath: 'build/does-not-exist/avatar.png',
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
