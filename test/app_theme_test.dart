import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/PlayerWidget.dart';
import 'package:mcmanager/ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart';
import 'package:mcmanager/ManagerCareer/TeamTransfers/TransferStyle.dart';
import 'package:mcmanager/Settings/CustomConfiguration/CustomConfigurationComponents.dart';
import 'package:mcmanager/utils/AppColors.dart';
import 'package:mcmanager/utils/Components/CareerPageWidgets.dart';
import 'package:mcmanager/utils/Components/FootballPitch.dart';
import 'package:mcmanager/utils/themes.dart';

import 'ui_preview_fonts.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  setUpAll(loadPreviewFonts);

  for (final colors in [AppColors.dark, AppColors.light]) {
    test(
      'Application text and action ink keep accessible contrast ${colors.background}',
      () {
        for (final surface in [colors.background, colors.panel, colors.field]) {
          for (final foreground in [colors.text, colors.muted, colors.accent]) {
            expect(contrast(foreground, surface), greaterThanOrEqualTo(4.5));
          }
        }
        expect(
          contrast(colors.onAccent, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
        for (final fill in [
          AppColors.ratingExcellent,
          AppColors.ratingGood,
          AppColors.ratingAverage,
          AppColors.ratingBelowAverage,
          AppColors.ratingPoor,
          AppColors.ratingUnknown,
        ]) {
          expect(
            contrast(AppColors.onColor(fill), fill),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );
  }

  testWidgets(
    'Live theme changes reach nested screens, pitch, names and modal fields',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mode = ValueNotifier(ThemeMode.dark);
      addTearDown(mode.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (_, selected, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: managerLightTheme,
            darkTheme: managerDarkTheme,
            themeMode: selected,
            home: RepaintBoundary(key: boundary, child: const _ThemePreview()),
          ),
        ),
      );

      for (final selected in [
        ThemeMode.dark,
        ThemeMode.light,
        ThemeMode.dark,
      ]) {
        mode.value = selected;
        await tester.pumpAndSettle();
        final expected = selected == ThemeMode.dark
            ? AppColors.dark
            : AppColors.light;
        final context = tester.element(find.byType(ProfilePanel));
        expect(Theme.of(context).scaffoldBackgroundColor, expected.background);
        expect(Theme.of(context).colorScheme.primary, expected.accent);
        expect(
          tester.widget<Text>(find.text('Calleri')).style!.color,
          expected.text,
        );
        expect(
          tester.widget<Text>(find.text('79')).style!.color,
          expected.onAccent,
        );
        final pitch = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is FootballPitchPainter,
          ),
        );
        expect(
          (pitch.painter as FootballPitchPainter).colors.pitchStart,
          expected.pitchStart,
        );
        final path = Platform.environment['THEME_PREVIEW_DIR'];
        if (path != null) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final picture = await render.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$path/shared-${selected.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('Abrir opções'));
      await tester.pumpAndSettle();
      final fieldContext = tester.element(find.byType(TransferPickerField));
      expect(Theme.of(fieldContext).brightness, Brightness.dark);
      expect(Theme.of(fieldContext).colorScheme.onSurface, AppColors.dark.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) => TransferTheme(
    child: CustomConfigurationTheme(
      child: Builder(
        builder: (context) => Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('FC Career Live')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const CareerPageHeader(
                  title: 'Sua carreira, ao vivo',
                  subtitle: 'Partidas, elenco e competições no mesmo lugar.',
                  eyebrow: 'FC CAREER LIVE',
                  icon: Icons.sports_soccer,
                ),
                ProfilePanel(
                  child: Column(
                    children: [
                      const Text('Central do elenco'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 115,
                        child: PlayerWidget(
                          name: 'Calleri',
                          position: 'ATA',
                          fifaVersion: 'FC26',
                          overall: 79,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 140,
                  child: FootballPitch(
                    formation: '4-3-3',
                    slotBuilder: (_, _) => Icon(
                      Icons.person_outline,
                      size: 16,
                      color: AppColors.of(context).accent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => TransferTheme(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: TransferPickerField(
                          label: 'Clube',
                          value: 'São Paulo',
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir opções'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
