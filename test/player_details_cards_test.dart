import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerDetailsCards.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileCharts.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'package:mcmanager/utils/themes.dart';

import 'ui_preview_fonts.dart';

void main() {
  setUpAll(loadPreviewFonts);
  for (final dark in [true, false]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'Financial histories fit $width in ${dark ? 'dark' : 'light'} and retain actions',
        (tester) async {
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var history = 0, add = 0;
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? managerDarkTheme : managerLightTheme,
              home: RepaintBoundary(
                key: key,
                child: Scaffold(
                  appBar: AppBar(title: const Text('Jogador')),
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        PlayerInfoGrid(
                          title: 'No elenco',
                          items: const [
                            (
                              label: 'Salário semanal',
                              value: '1.250.000 €',
                              leading: null,
                            ),
                            (
                              label: 'Valor de mercado',
                              value: '999.999.999 €',
                              leading: null,
                            ),
                          ],
                        ),
                        PlayerHistoryCard(
                          title: 'Salário',
                          value: '1.250.000 €',
                          points: [
                            ProfileChartPoint(1250000, date: DateTime(2028)),
                          ],
                          onHistory: () => history++,
                          onAdd: () => add++,
                        ),
                        PlayerHistoryCard(
                          title: 'Valor de mercado',
                          value: '999.999.999 €',
                          points: [
                            ProfileChartPoint(50000000, date: DateTime(2028)),
                            ProfileChartPoint(
                              999999999,
                              date: DateTime(2028, 9),
                            ),
                          ],
                          compactAxis: true,
                          onHistory: () {},
                          onAdd: () {},
                        ),
                        const ProfilePanel(
                          child: ProfileLine('Anual', '999.999.999.999 €'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(OverallChart), findsOneWidget);
          expect(
            tester.getSize(find.byType(OverallChart)).width,
            greaterThan(240),
          );
          expect(find.text('Primeiro registro em 01/01/2028.'), findsOneWidget);
          await tester.tap(find.byTooltip('Ver histórico de Salário'));
          await tester.tap(find.byTooltip('Adicionar registro de Salário'));
          expect(history, 1);
          expect(add, 1);
          expect(tester.takeException(), isNull);
          final directory = Platform.environment['PROFILE_PREVIEW_DIR'];
          if (directory != null && width == 390) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(directory).create(recursive: true);
              await File(
                '$directory/player-finances-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
