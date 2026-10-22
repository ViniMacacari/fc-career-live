import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../Common/GoalShotPlacementPage.dart' show penaltySpotLocation;
import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../utils/AppColors.dart';
import 'PlayerAnalysis.dart';
import 'PlayerProfileData.dart';
import 'PlayerProfileVisuals.dart';

class PlayerScoringData {
  PlayerScoringData(List<PlayerMatchData> matches) {
    for (final match in matches) {
      goals += match.goals;
      missed += match.performance.missedPenaltyDetails.length;
      saved += match.performance.penaltySaves ?? 0;
      for (final goal in match.performance.goalDetails) {
        if (goal.isPenalty) penalties++;
        final field =
            goal.fieldLocation ?? (goal.isPenalty ? penaltySpotLocation : null);
        if (_valid(field)) {
          fieldLocations.add(field!);
          final region = goal.isPenalty
              ? 'Pênalti'
              : field.y >= 1 - 5.5 / (68 * 2 / 3) &&
                    field.x >= (68 - 18.32) / 136 &&
                    field.x <= (68 + 18.32) / 136
              ? 'Pequena área'
              : field.y >= 1 - 16.5 / (68 * 2 / 3) &&
                    field.x >= (68 - 40.32) / 136 &&
                    field.x <= (68 + 40.32) / 136
              ? 'Grande área'
              : 'Fora da área';
          origins[region] = origins[region]! + 1;
        }
        if (_valid(goal.goalLocation)) {
          final location = goal.goalLocation!;
          goalLocations.add(location);
          final x = location.x < .28
              ? 0
              : location.x < .72
              ? 1
              : 2;
          final y = (location.y.clamp(0, .999) * 3).floor();
          regions[y * 3 + x]++;
        }
      }
    }
  }
  static bool _valid(GoalShotLocation? p) =>
      p != null &&
      p.x.isFinite &&
      p.y.isFinite &&
      p.x >= 0 &&
      p.x <= 1 &&
      p.y >= 0 &&
      p.y <= 1;
  int goals = 0, penalties = 0, missed = 0, saved = 0;
  final fieldLocations = <GoalShotLocation>[],
      goalLocations = <GoalShotLocation>[];
  final origins = <String, int>{
    'Pequena área': 0,
    'Grande área': 0,
    'Fora da área': 0,
    'Pênalti': 0,
  };
  final regions = List<int>.filled(9, 0);
  int get unknownField => math.max(0, goals - fieldLocations.length);
  int get unknownGoal => math.max(0, goals - goalLocations.length);
  int get attempts => penalties + missed;
  String get conversion => attempts == 0
      ? '—'
      : '${(penalties * 100 / attempts).toStringAsFixed(1).replaceAll('.', ',')}%';
  static String regionLabel(int index) =>
      '${const ['Alta', 'Média', 'Baixa'][index ~/ 3]} · ${const ['esquerda', 'centro', 'direita'][index % 3]}';
}

class PlayerScoringInsights extends StatelessWidget {
  const PlayerScoringInsights({super.key, required this.matches});
  final List<PlayerMatchData> matches;
  Widget _heading(BuildContext context, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.of(context).muted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
        ],
      );

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: TextStyle(color: AppColors.of(context).muted, fontSize: 11.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = PlayerScoringData(matches), c = AppColors.of(context);
    final placed = data.goalLocations.length;
    final favourite = placed == 0
        ? null
        : [for (var i = 0; i < 9; i++) i]
              .reduce((a, b) => data.regions[b] > data.regions[a] ? b : a);
    return Column(
      children: [
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Posicionamento do chute',
                'Onde a bola entrou, na visão de quem chuta · $placed de ${data.goals} gols com destino registrado.',
              ),
              GoalMouth(locations: data.goalLocations),
              if (favourite != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(color: c.muted, fontSize: 12),
                      children: [
                        const TextSpan(text: 'Canto preferido: '),
                        TextSpan(
                          text: PlayerScoringData.regionLabel(favourite),
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${data.regions[favourite]} de $placed gols (${(data.regions[favourite] * 100 / placed).round()}%)',
                        ),
                      ],
                    ),
                  ),
                ),
              if (data.unknownGoal > 0)
                _note(
                  context,
                  '${data.unknownGoal} ${data.unknownGoal == 1 ? 'gol' : 'gols'} sem região do gol informada.',
                ),
            ],
          ),
        ),
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Mapa de gols',
                'De onde saíram os gols · ${data.fieldLocations.length} de ${data.goals} com origem registrada; pênaltis ficam na marca da cobrança.',
              ),
              PitchMap(locations: data.fieldLocations),
              const SizedBox(height: 14),
              AnalysisStrip(
                items: [
                  for (final e in data.origins.entries) ('${e.value}', e.key),
                ],
              ),
              if (data.unknownField > 0)
                _note(
                  context,
                  '${data.unknownField} ${data.unknownField == 1 ? 'gol' : 'gols'} sem origem informada.',
                ),
            ],
          ),
        ),
        ProfilePanel(
          key: const ValueKey('player-penalty-insights'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Pênaltis',
                'Cobranças durante o jogo; o aproveitamento conta convertidos e perdidos.',
              ),
              AnalysisStrip(
                items: [
                  ('${data.penalties}', 'Convertidos'),
                  ('${data.missed}', 'Perdidos'),
                  (data.conversion, 'Aproveitamento'),
                  if (data.saved > 0) ('${data.saved}', 'Defendidos'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PlayerCaptainInsights extends StatelessWidget {
  const PlayerCaptainInsights({super.key, required this.matches});
  final List<PlayerMatchData> matches;
  @override
  Widget build(BuildContext context) {
    final total = PlayerTotals(matches), c = AppColors.of(context);
    return ProfilePanel(
      key: const ValueKey('player-captain-insights'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Capitania',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total.hasCaptaincy
                ? 'Jogos com a braçadeira registrados neste período.'
                : 'Nenhuma informação de capitão registrada neste período.',
            style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.4),
          ),
          if (total.hasCaptaincy) ...[
            const SizedBox(height: 14),
            AnalysisStrip(
              items: [
                ('${total.captainGames}', 'Jogos como capitão'),
                ('${total.captainStarts}', 'Desde o início'),
                ('${total.captainInherited}', 'Assumiu no jogo'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
