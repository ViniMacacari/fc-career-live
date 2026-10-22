import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../PlayerCareer/Fixtures/index.dart';
import '../PlayerCareer/PlayerSeasonsStatistics/PlayerSeasonsStatistics.dart';
import '../PlayerCareer/PlayerStreaks/PlayerStreaks.dart';
import '../PlayerCareer/TransferHistory/TransferHistory.dart';
import '../PlayerCareer/TournamentResults/TournamentResultsPage.dart';
import '../Trophies/Trophies.dart';
import '../models/Person.dart';
import '../Twitter/TwitterPage.dart';
import 'DrawerItem.dart';
import '../Common/Seasons/SeasonArchivePage.dart';
import '../FcScore/FcScoreConnectionPage.dart';
import '../FcScore/CareerCompetitionsPage.dart';

List<DrawerEntry> playerCareerMenuItems(Person person) => [
  DrawerItem(
    id: 'fixtures',
    titleKey: 'sections.fixtures',
    icon: Icons.sports_soccer,
    page: (_) => PlayerFixturesPage(person: person),
  ),
  DrawerItem(
    id: 'careerCompetitions',
    titleKey: 'Classificação',
    icon: Icons.leaderboard_outlined,
    page: (_) => CareerCompetitionsPage(person: person),
  ),
  DrawerItem(
    id: 'twitter',
    titleKey: 'X (Rede Social)',
    icon: TablerIcons.brandX,
    page: (_) => TwitterPage(person: person),
  ),
  DrawerItem(
    id: 'careerPath',
    titleKey: 'sections.careerPath',
    icon: Icons.timeline,
    page: (_) => TransferHistory(person: person),
  ),
  DrawerItem(
    id: 'careerStatistics',
    titleKey: 'sections.careerStatistics',
    icon: Icons.bar_chart,
    page: (_) => PlayerSeasonsStatistics(person: person),
  ),
  DrawerItem(
    id: 'seasonArchive',
    titleKey: 'Temporadas',
    icon: Icons.auto_awesome_outlined,
    page: (_) => SeasonArchivePage(person: person),
  ),
  DrawerItem(
    id: 'tournamentResults',
    titleKey: 'sections.tournamentResults',
    icon: Icons.table_chart,
    page: (_) => TournamentResultsPage(person: person),
  ),
  DrawerItem(
    id: 'trophies',
    titleKey: 'sections.trophiesCabinet',
    icon: Icons.emoji_events,
    page: (_) => TrophiesPage(person: person),
  ),
  const DrawerSeparator(),
  DrawerItem(
    id: 'fcScore',
    titleKey: 'FC Score',
    icon: Icons.connected_tv_rounded,
    page: (_) => FcScoreConnectionPage(initialPerson: person),
  ),
  DrawerItem(
    id: 'streaks',
    titleKey: 'sections.streaks',
    icon: Icons.trending_up,
    page: (_) => PlayerStreaks(person: person),
  ),
];
