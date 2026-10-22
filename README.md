# FC Career Live — EA SPORTS FC 26 Career Mode Tracker for Android

[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#getting-started)
[![Version](https://img.shields.io/badge/version-0.13.2-informational)](CHANGELOG.md)

**FC Career Live** is an unofficial career mode tracker for **EA SPORTS FC 26**, built with Flutter for Android. Log every match of your manager or player career, follow your squad and every other club, analyse player stats and ratings, record transfers, close seasons and collect trophies, and import data straight from your PC save with the **FC Score** integration.

It also supports **EA SPORTS FC 27, FC 25, FC 24 and FIFA 23**.

## Contents

- [Features](#features)
- [Supported games](#supported-games)
- [FC Score integration](#fc-score-integration)
- [Getting started](#getting-started)
- [Development](#development)
- [Data files](#data-files)
- [Changelog](CHANGELOG.md)
- [Disclaimer](#disclaimer)

## Features

### Matches and lineups

- Record results with scorers and minutes, assists, goal types, cards, own goals, missed penalties, injuries and substitutions, including extra time and penalty shootouts.
- Lineups on a football pitch with 38 formations or a custom one, for your team and the opponent, placed by position compatibility.
- Tap a player on the pitch to add a goal, assist, substitution or card in two taps, edit the full performance, swap players or move them to the bench.
- Player ratings, captaincy and handovers, man of the match, team stats, match timeline and press conferences.
- Head-to-head records, streaks, a calendar view and filters by season, competition and venue.

### Squad and player analytics

- **Squad Center** with availability, active injuries, squad composition, leaders, youth academy and recent matches.
- Player profiles with season tables in totals and per 90 minutes, weighted shot, pass, dribble and tackle accuracy, expected goals and assists, monthly ratings, shot and goal maps, penalties and captaincy.
- A season summary with rating bands, decisive goals, partnerships, goal types and career-by-season tables.
- Player comparison with totals or per 90 minutes, who is ahead in each area and head-to-head bars.
- Player rankings, activity analysis and team analytics: points percentage, goals, possession, results by venue and season comparison.

### Other clubs

- **Other players** shows every other club's squad grouped by league, with search by name, club, position or country and filters by position, overall, age, league and nationality.
- Create, sign, transfer, release or edit players of any club, with a transfer history for every player.
- Season numbers per competition for players of other clubs, including national team games, refreshed from your save on demand.

### Seasons, competitions and trophies

- Seasons with closing, final tables, an animated season recap and a season archive.
- League tables, fixtures, top scorers and assists, and group and knockout stages for imported competitions.
- Trophy cabinet by competition with each campaign summary.
- Career history, records and the manager profile.

### Transfers

- Buy, sell, loan, free transfers, contract ends, youth promotions and swap deals.
- A farewell card when a player leaves, and the player's numbers at the previous club when signing.

### Social feed

- An **X (social network)** feed for your career with AI-generated posts and replies from fans, rivals, pages and newspapers, using your own OpenRouter key.

### Customization and backups

- Custom clubs, leagues, tournaments, trophies and players, plus club name and crest customization.
- Light and dark themes and 10 languages.
- ZIP backups with optional images, and **Import from other apps** for careers saved by other career trackers.

## Supported games

| Game | Clubs, leagues and tournaments | Player catalog |
| --- | --- | --- |
| EA SPORTS FC 27 | Yes | Yes |
| EA SPORTS FC 26 | Yes | Yes |
| EA SPORTS FC 25 | Yes | Yes |
| EA SPORTS FC 24 | Yes | Yes |
| FIFA 23 | Yes | Yes |

The FC Score integration reads EA SPORTS FC 26 (and FC 25) save files.

## FC Score integration

FC Score is a read-only API that runs on your PC and reads your EA SPORTS FC career save. FC Career Live connects to it over Wi‑Fi or USB to import:

- competitions, standings, fixtures and results of every team;
- squads of every club, overalls and season statistics;
- match reports with 93 statistics per player, ratings, man of the match, lineups and substitutions.

Setup:

1. Start the FC Score Career Mode API on the PC (default port **38291**) and allow Node.js on private networks in the Windows firewall.
2. In the app, open **Settings → FC Score API** or the career menu and enter the PC address shown by the API.
3. For USB, enable USB debugging, connect the phone and run:

   ```powershell
   adb reverse tcp:38291 tcp:38291
   ```

Competitions, clubs and players are linked once to the app's own records, and the app always shows the names you configured. Reading data never changes the game saves.

## Getting started

Requirements: the Flutter SDK (Dart 3.13 or later) and the Android SDK.

```bash
flutter pub get
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

On Windows, `build.bat` finds Flutter (`FLUTTER_ROOT`, `E:\flutter_sdk` or `PATH`), builds in release mode and copies the result to `dist\FC_Career_Live.apk`.

- Android package: `com.mcmanager`
- The release build uses the project's development signature; set up your own key for distribution.

## Development

```bash
flutter analyze
flutter test --enable-impeller
```

Widget tests use the Impeller renderer because the local SDK compiles test shaders for Vulkan. Data tests run on an in-memory SQLite database.

Project structure:

| Folder | Contents |
| --- | --- |
| `lib/ManagerCareer` | Manager career screens: matches, squad, players, transfers, other clubs |
| `lib/PlayerCareer` | Player career screens |
| `lib/Common` | Shared screens: match details, pitch, seasons, head-to-head |
| `lib/FcScore` | FC Score API client, mapping and imports |
| `lib/Twitter` | X (social network) feed and AI generation |
| `lib/models` | Data models |
| `lib/utils` | Database, catalogs, backups and shared components |
| `test` | Unit and widget tests |

Dependency versions are pinned in `pubspec.lock`. Icons come from `tabler_icons_plus`, and flag images from `icons_plus`.

## Data files

- `assets/game_catalog.json`: clubs and leagues of every edition, from FIFA 23 to FC 27.
- `assets/game_tournaments.json`: tournaments of every edition. For FC 26, the app lists the 100 competitions that share the same ID and name in FC 25 and FC 27.
- `assets/game_awards.json`: 375 awards with id, name, image, owner and category.
- `assets/*_players.json`: the player catalog of every edition.
- `assets/translations/*.json`: texts for the 10 languages.
- `assets/voice_config.json`: words recognised when logging match events by voice.
- `assets/branding/`: the app brand. Android launcher icons are generated from the square icon with `tooling/refresh_app_icons.py`.
- `assets/fonts/`: the Manrope font and its license (`OFL-Manrope.txt`).

## Disclaimer

FC Career Live is a fan-made project. It is not affiliated with, endorsed, sponsored or approved by Electronic Arts Inc. EA SPORTS FC, FIFA and all related names, logos and trademarks belong to their respective owners.
