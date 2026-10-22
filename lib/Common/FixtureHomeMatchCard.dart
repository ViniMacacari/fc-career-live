import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import 'FixtureResultTile.dart';

class FixtureHomeMatchCard extends StatelessWidget {
  const FixtureHomeMatchCard({
    super.key,
    required this.person,
    required this.fixture,
    required this.tournament,
    required this.onTap,
    this.compact = false,
    this.redCards = 0,
  });
  final Person person;
  final Map<String, Object?> fixture;
  final String tournament;
  final VoidCallback onTap;
  final bool compact;
  final int redCards;

  String _name(String side) =>
      GameCatalog.current?.teamLabel(
        person.fifaVersion,
        '${fixture['${side}TeamId']}',
        leagueId: fixture['${side}TeamLeagueId']?.toString(),
      ) ??
      '${fixture['${side}TeamId']}';

  Widget _club(BuildContext context, String side) => Expanded(
    child: Column(
      children: [
        TeamLogo.lookup(
          fifaVersion: person.fifaVersion,
          teamId: '${fixture['${side}TeamId']}',
          leagueId: fixture['${side}TeamLeagueId']?.toString(),
          size: 36,
        ),
        const SizedBox(height: 8),
        Text(
          _name(side),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final result = fixtureResult(fixture);
    final color = switch (result) {
      FixtureResult.win => c.green,
      FixtureResult.draw => c.amber,
      FixtureResult.lose => c.red,
    };
    final resultLabel = switch (result) {
      FixtureResult.win => 'Vitória',
      FixtureResult.draw => 'Empate',
      FixtureResult.lose => 'Derrota',
    };
    final date = DateTime.tryParse(fixture['date']?.toString() ?? '');
    final away = fixture['location'] == 'away';
    final left = away ? 'opposite' : 'player',
        right = away ? 'player' : 'opposite';
    final leftScore = fixture['${left}TeamScore'] ?? 0,
        rightScore = fixture['${right}TeamScore'] ?? 0;
    final penalties =
        fixture['playerTeamPenaltiesScore'] != null &&
            fixture['oppositeTeamPenaltiesScore'] != null
        ? '${fixture['${left}TeamPenaltiesScore']}–${fixture['${right}TeamPenaltiesScore']} pên.'
        : null;
    final location = fixture['location'] == 'home'
        ? 'Em casa'
        : away
        ? 'Fora de casa'
        : 'Campo neutro';
    final stage = fixture['stage']?.toString() ?? '';
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        resultLabel,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      compact
                          ? Icons.emoji_events_outlined
                          : Icons.calendar_today_outlined,
                      size: 13,
                      color: c.muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        compact
                            ? tournament
                            : date == null
                            ? '—'
                            : DateFormat('dd/MM/yyyy').format(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    ),
                    if (fixture['isFavorite'] == 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: c.amber,
                        ),
                      ),
                    badge,
                  ],
                ),
                const SizedBox(height: 16),
                if (compact)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _name(left),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$leftScore – $rightScore',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _name(right),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      _club(context, left),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            Text(
                              '$leftScore – $rightScore',
                              style: const TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                            ),
                            if (penalties != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  penalties,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _club(context, right),
                    ],
                  ),
                const SizedBox(height: 15),
                Divider(height: 1, color: c.line),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Icon(
                      fixture['location'] == 'home'
                          ? Icons.home_outlined
                          : away
                          ? Icons.flight_takeoff_rounded
                          : Icons.stadium_outlined,
                      size: 14,
                      color: c.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        compact
                            ? '${date == null ? '—' : DateFormat('dd/MM/yy').format(date)} · $location'
                            : '$location${stage.isEmpty ? '' : ' · $stage'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    ),
                    if (compact && penalties != null)
                      Text(
                        penalties,
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    if (redCards > 0)
                      Tooltip(
                        message: '$redCards ${'fixtures.redCards'.tr()}',
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FixtureCardIcon(red: true),
                              Text(
                                '$redCards',
                                style: TextStyle(fontSize: 10, color: c.red),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 5),
                    Icon(Icons.chevron_right_rounded, size: 17, color: c.muted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
