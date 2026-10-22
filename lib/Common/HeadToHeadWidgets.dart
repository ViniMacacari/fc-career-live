import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'FixtureResultTile.dart' show FixtureResult;

const h2hWin = AppColors.resultWin;
const h2hDraw = AppColors.resultDraw;
const h2hLoss = AppColors.resultLoss;

Color h2hResultColor(FixtureResult result) => switch (result) {
  FixtureResult.win => h2hWin,
  FixtureResult.draw => h2hDraw,
  FixtureResult.lose => h2hLoss,
};

String h2hResultLetter(FixtureResult result) => switch (result) {
  FixtureResult.win => 'fixtures.winShort',
  FixtureResult.draw => 'fixtures.drawShort',
  FixtureResult.lose => 'fixtures.loseShort',
}.tr();

class H2HRecordBar extends StatelessWidget {
  const H2HRecordBar({
    super.key,
    required this.wins,
    required this.draws,
    required this.losses,
    this.height = 8,
  });
  final int wins, draws, losses;
  final double height;

  @override
  Widget build(BuildContext context) {
    final parts = [
      (wins, h2hWin),
      (draws, h2hDraw),
      (losses, h2hLoss),
    ].where((p) => p.$1 > 0).toList();
    if (parts.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.of(context).line,
          borderRadius: BorderRadius.circular(height),
        ),
      );
    }
    final radius = Radius.circular(height / 2);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final (i, (count, color)) in parts.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: count,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? radius : Radius.zero,
                    right: i == parts.length - 1 ? radius : Radius.zero,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class H2HRecordPills extends StatelessWidget {
  const H2HRecordPills({
    super.key,
    required this.wins,
    required this.draws,
    required this.losses,
    this.fontSize = 13,
  });
  final int wins, draws, losses;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 4,
    children: [
      for (final (count, result) in [
        (wins, FixtureResult.win),
        (draws, FixtureResult.draw),
        (losses, FixtureResult.lose),
      ])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: h2hResultColor(result),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count ${h2hResultLetter(result)}',
              style: TextStyle(
                color: AppColors.of(context).text,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
    ],
  );
}

class H2HResultChip extends StatelessWidget {
  const H2HResultChip(this.result, {super.key});
  final FixtureResult result;

  @override
  Widget build(BuildContext context) => Container(
    width: 25,
    height: 25,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: h2hResultColor(result),
      shape: BoxShape.circle,
    ),
    child: Text(
      h2hResultLetter(result),
      style: TextStyle(
        color: AppColors.ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class H2HCard extends StatelessWidget {
  const H2HCard({super.key, this.title, this.subtitle, required this.child});
  final String? title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: AppColors.of(context).panel,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.of(context).line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        child,
      ],
    ),
  );
}
