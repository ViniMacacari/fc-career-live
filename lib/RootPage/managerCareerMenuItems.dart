import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../ManagerCareer/Fixtures/ManagerFixturesPage.dart';
import '../ManagerCareer/ManagerCareerPath/ManagerCareerPathPage.dart';
import '../ManagerCareer/ManagerSeasonsStatistics/ManagerSeasonsStatistics.dart';
import '../ManagerCareer/ManagerStreaks/ManagerStreaks.dart';
import '../ManagerCareer/OtherPlayers/OtherPlayersPage.dart';
import '../ManagerCareer/PlayersStat/PlayersStatPage.dart';
import '../ManagerCareer/TeamCenter/TeamCenterPage.dart';
import '../ManagerCareer/TeamTransfers/TeamTransfersPage.dart';
import '../PlayerCareer/TournamentResults/TournamentResultsPage.dart';
import '../Trophies/Trophies.dart';
import '../models/Person.dart';
import '../ManagerCareer/MyManager/MyManagerPage.dart';
import '../ManagerCareer/Graphics/ManagerGraphics.dart';
import '../Twitter/TwitterPage.dart';
import 'DrawerItem.dart';
import '../Common/Seasons/SeasonArchivePage.dart';
import '../FcScore/FcScoreConnectionPage.dart';
import '../FcScore/CareerCompetitionsPage.dart';

List<DrawerEntry> managerCareerMenuItems(Person person) => [
  DrawerItem(
    id: 'fixtures',
    titleKey: 'sections.fixtures',
    icon: Icons.sports_soccer,
    page: (_) => ManagerFixturesPage(person: person),
  ),
  DrawerItem(
    id: 'teamCenter',
    titleKey: 'players.teamCenter',
    icon: Icons.groups,
    page: (_) => TeamCenterPage(person: person),
  ),
  DrawerItem(
    id: 'careerCompetitions',
    titleKey: 'Classificação',
    icon: Icons.leaderboard_outlined,
    page: (_) => CareerCompetitionsPage(person: person),
  ),
  DrawerItem(
    id: 'myManager',
    titleKey: 'Meu técnico',
    icon: Icons.person,
    page: (_) => MyManagerPage(person: person),
  ),
  DrawerItem(
    id: 'playerStatistics',
    titleKey: 'sections.playerStatistics',
    icon: Icons.query_stats,
    page: (_) => PlayersStatPage(person: person),
  ),
  DrawerItem(
    id: 'otherPlayers',
    titleKey: 'Outros jogadores',
    icon: Icons.person_search_outlined,
    page: (_) => OtherPlayersPage(person: person),
  ),
  DrawerItem(
    id: 'transfers',
    titleKey: 'sections.transfers',
    icon: Icons.swap_horiz,
    page: (_) => TeamTransfersPage(person: person),
  ),
  DrawerItem(
    id: 'twitter',
    titleKey: 'X (Rede Social)',
    icon: TablerIcons.brandX,
    page: (_) => TwitterPage(person: person),
  ),
  const DrawerSeparator(),
  DrawerItem(
    id: 'fcScore',
    titleKey: 'FC Score',
    icon: Icons.connected_tv_rounded,
    page: (_) => FcScoreConnectionPage(initialPerson: person),
  ),
  DrawerItem(
    id: 'careerPath',
    titleKey: 'sections.careerPath',
    icon: Icons.timeline,
    page: (_) => ManagerCareerPathPage(person: person),
  ),
  DrawerItem(
    id: 'careerStatistics',
    titleKey: 'sections.careerStatistics',
    icon: Icons.bar_chart,
    page: (_) => ManagerSeasonsStatistics(person: person),
  ),
  DrawerItem(
    id: 'teamAnalytics',
    titleKey: 'Análise do time',
    icon: Icons.insights_rounded,
    page: (_) => ManagerGraphics(person: person),
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
    id: 'streaks',
    titleKey: 'sections.streaks',
    icon: Icons.trending_up,
    page: (_) => ManagerStreaks(person: person),
  ),
];
