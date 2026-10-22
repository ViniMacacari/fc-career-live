import 'package:mcmanager/utils/themes.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/Twitter/TwitterClubPostForm.dart';
import 'package:mcmanager/Twitter/TwitterModels.dart';

import 'ui_preview_fonts.dart';

void main() {
  const club = TwitterAccount(
    id: 'club',
    personId: 'career',
    name: 'São Paulo',
    handle: 'SaoPauloFC',
    kind: TwitterAccountKind.club,
    teamId: '40-13',
    leagueId: '1014',
  );
  setUpAll(loadPreviewFonts);

  Widget app({
    required void Function(String, DateTime) submit,
    GlobalKey? captureKey,
    double keyboard = 0,
  }) => RepaintBoundary(
    key: captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: managerDarkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: DefaultTabController(
          length: 4,
          initialIndex: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Gerar posts'),
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Partidas'),
                  Tab(text: 'Transferências'),
                  Tab(text: 'Assunto'),
                  Tab(text: 'Clube'),
                ],
              ),
            ),
            body: TwitterClubPostForm(
              club: club,
              version: 'FC26',
              initialDate: DateTime(2026, 2, 20),
              onSubmit: submit,
            ),
          ),
        ),
      ),
    ),
  );
  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key) async {
    final dir = Platform.environment['PROFILE_PREVIEW_DIR'];
    if (dir == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/clubLogos/sao-paulo.png'),
        key.currentContext!,
      );
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/twitter_post_clube.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Official identity, Twitter rounded fields and context submission',
    (tester) async {
      viewport(tester, const Size(390, 844));
      String? context;
      DateTime? date;
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          captureKey: key,
          submit: (c, d) {
            context = c;
            date = d;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('São Paulo'), findsOneWidget);
      expect(find.text('@SaoPauloFC'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      final theme = Theme.of(tester.element(find.byType(TextField)));
      expect(
        (theme.inputDecorationTheme.border as OutlineInputBorder).borderRadius,
        BorderRadius.circular(16),
      );
      await tester.enterText(
        find.byType(TextField),
        '  Renovamos com o capitão por mais duas temporadas.  ',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await capture(tester, key);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      expect(context, 'Renovamos com o capitão por mais duas temporadas.');
      expect(date, DateTime(2026, 2, 20));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Calendar changes the publication day', (tester) async {
    viewport(tester, const Size(390, 844));
    DateTime? date;
    await tester.pumpWidget(app(submit: (_, d) => date = d));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('15/02/2026'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Anunciar a renovação');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    expect(date, DateTime(2026, 2, 15));
  });
  testWidgets('Small screen with keyboard can reach the publish action', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    String? submitted;
    await tester.pumpWidget(
      app(keyboard: 260, submit: (c, _) => submitted = c),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      List.filled(15, 'Contexto do anúncio. ').join(),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    expect(submitted, startsWith('Contexto do anúncio'));
    expect(tester.takeException(), isNull);
  });
}
