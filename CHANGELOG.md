# Changelog

All notable changes to **FC Career Live**, the EA SPORTS FC career mode tracker for Android, are listed here. Newest versions come first.

## 0.13.2

- The match pitch places players the same way as the Squad Center: it picks the most compatible combination of positions and slots for both teams. Layouts arranged by hand stay as they are.
- Sided positions from the save (such as right centre-back or left striker) count as the base position and show on the pitch. The player's registered position takes priority.
- Choosing a player for the pitch lists players by position and shows each one's position.
- While editing, tapping a player opens a ring of icons around the player: goal, assist, substitution, yellow and red card, full performance edit, swap and bench. Events only ask for the minute.
- The opponent's man of the match shows photo and rating in the highlights.
- Saving a match opens it in read mode, both when creating and when editing.
- Competitions and clubs linked to the app's records always show the names configured in the app. API names only appear on import screens.

## 0.13.1

- Players of other clubs show every game of the season: opening a profile fetches from FC Score the player's full season at each club and the national team, with games, goals, assists and rating. The panel shows the date of the save numbers.
- An imported club's squad is refreshed when its page opens, and the refresh button fetches again at any time without a full import. Without a connection to the PC, the numbers of the last import remain.
- A player who changed clubs during the season keeps one line per club in the same competition.
- Database 46 creates the `WorldPlayerSeason` table.

## 0.13.0

- **Other players** gathers the squads of every other club, grouped by league, with search by name, club, position or country and filters by position, overall, age, league and nationality.
- Clubs imported from the API show the downloaded squad; the others use the game catalog, without repeating players already in the career.
- Players can be created in a squad, brought from another club, transferred, released or removed. A catalog player becomes a career player on the first edit.
- The player profile shows the club crest and name under the player's name and gains a **Transfers** tab for every player: manual moves, the user's club transfers and the moves detected by the API import when a player appears in another squad.
- For players of other clubs, the Season tab shows numbers per competition from the API, which can be adjusted or added to, and the Career tab gathers the seasons.
- Database 45 creates the `WorldPlayer`, `WorldTransfer` and `WorldPlayerStats` tables; careers imported before use the downloaded squads as their starting point.

## 0.12.5

- The player profile calculates shot, pass, dribble and tackle accuracy from match totals, like the statistics screen, and shows shot conversion, expected goals and assists, and numbers per 90 minutes.
- The Season tab opens with the summary and organizes Attack, Creation and Defence in total and per 90' tables, hiding what was not recorded. Monthly ratings use the rating colour scale.
- In the Summary, shortcuts jump to each section, rating bands follow the colour scale and partnerships show the names of players who only assisted.
- Maps, penalties and captaincy are shown as number strips, and detailed statistics in a single panel.
- Player comparison switches between totals and per 90 minutes, shows who is ahead and the leader of each area, and with two players puts each statistic head to head. Player cards pick the season from a list.

## 0.12.4

- The match Main tab shows the lineup on the pitch, with ratings, events, captain and substitutes, instead of the list.
- While editing, the player list has one fixed-height row per player: repeated events become counts (⚽×3) and substitutions show the minute, with icons of the same size and ratings in an aligned column. Event minutes stay in the Timeline and the player report.
- The lineup opens in the list or on the pitch, following the last choice.

## 0.12.3

- A match opens with score, scorers, competition, date and venue in a single block.
- Statistics compare both teams side by side without rows of zeros. The man of the match leads the highlights without repeating, and the captain appears in the lineup.
- Press conference and head-to-head sit side by side at the end, and removing the match moves to the options menu.
- Timeline and Formation share the same header; the opponent's formation follows the layout of yours, with the pitch unchanged.
- In the editor, the score gains Extra time and Penalties options; tournament, date, venue, stage and man of the match become adjustment rows, and the lineup gathers team, list or pitch and actions in one panel.
- In the performance editor, labels sit above the numbers and events are added from a single panel that shows only what was recorded.

## 0.12.2

- Progress charts show a tooltip on the tapped point, with match, date and value, without opening dialogs; tapping outside hides it.
- Squad statistics become a single table: tapping a header sorts the column, and ratings use the match colour scale.
- Player analysis shows the numbers in rows, with the calculation in a tap tooltip, and each match lists only the events that happened.
- The Squad Center puts availability, composition and shortcuts at the top, followed by active injuries, leaders, recent matches and academy, without repeated blocks.

## 0.12.1

- Sorting uses a searchable list with readable contrast.
- Tapping a chart point opens the match data with access to the report.
- Player analysis gathers per-90 production, goal involvement, conversion and recent form as numeric indicators.
- Yellow and red cards use symbols; formulas and details are in the tap help.

## 0.12.0

- **Trophies** gathers titles by competition, with count, seasons and a campaign summary: matches until the title, results, goals, scorers and assists recorded.
- Player statistics use cards with filters and open an individual analysis with Summary, Statistics and Matches. Missing data stays distinct from recorded zeros.
- The Squad Center gathers availability, active injuries on the career date, squad composition, leaders, academy and recent matches with direct access.

## 0.11.1

- Player searches show the club name and crest when available, prioritizing the squad, transfers and career data.
- Catalog selection and API player pickers use cards with photos.
- Importing or completing a match from the API also updates the configured standings, without downloading the calendar, top scorers or squads. A failure in that update keeps the match saved and shows a warning.

## 0.11.0

- Recorded goals update both clubs' scores without a separate option.
- The backup tool exports an unencrypted ZIP named `carreira_YYYY-MM-DD_HH-mm-ss_clube.zip` and imports backups from other apps.
- App content gathers clubs, leagues and tournaments; a custom trophy belongs to its competition and follows titles and backups.
- Images use the registered files, including SVG, and generic icons when no image is available.
- The migration to database 44 preserves ongoing careers.

## 0.10.15

- Season comparison includes players who left the club during the year, with departure records and performances preserved.
- The selection keeps the chosen season's data and does not duplicate players who returned to the club.
- Statistics use the names "Expected goals" and "Expected assists", keeping the "non-penalty" note when that is the API value.

## 0.10.14

- The Squad Center keeps the formation per season, including empty slots: removing, selling or loaning a starter keeps the other places.
- Changing the formation redistributes players by position, keeping the goalkeeper in goal. The formation also follows the squad into a new season.
- Competitions without a defined format get League, Group stage and Knockout options for the match stage, with the next round or stage suggested from the same competition and season.
- Database version 43.

## 0.10.13

- Current value queries select only the latest candidates and use a linear pass per player.
- Large payloads and API JSON are processed in a background queue, without sorting all histories on the UI thread.
- Matches and statistics fetch only the players involved, and name lookups no longer recalculate the whole career.

## 0.10.12

- The Squad Center opens with the saved player data, without loading the whole catalog.
- Overall and season queries fetch only the players shown, with indexes for existing careers.
- Photos are decoded at the size used on screen, and extra catalog details load on demand, off the main UI.

## 0.10.6

- The match pitch uses the same height, row spacing, photo size and positions as the Squad Center, also on small screens. The rating sits over the photo.
- Wing-backs, full-backs and central players fill their places, and coordinates chosen by the user are preserved.
- Opponent starters are filled in from the saved report and the linked records, with available names, positions and photos, even when the profile is not sent again by the API. The formation considers those positions and manual choices; players wrongly moved to the bench return to the starting eleven. Old empty slots no longer appear as players. This happens locally and does not change the history.

## 0.10.5

- The Squad Center and match formations share the same pitch component, with the same row widths and spacing.
- Goals, assists, cards and substitutions appear as badges over the photos, with substitution minutes. The view stays read-only.
- The refresh button in Matches opens options for standings and top scorers, competition calendars, other clubs' squads, completing the user's own squad and overalls. The selection is remembered per career, even after the save file changes. Unselected data is preserved. This update never adds new matches to the career list; importing games stays in the Customize option.

## 0.10.4

- The lineup in the match editor switches between List and Formation for both clubs. The formation is saved with the match, and the read-only pitch shows goals, assists and substitution minutes.
- New opponents no longer receive eleven empty players automatically: the formation can be chosen by the user or suggested by the starters on import.
- The individual API report is kept in full in each performance, with new statistics blocks in Season and Summary: non-penalty xG, xA, duels, interceptions, crosses, passes under pressure, goalkeeping and more. Fields missing from the API stay hidden when there is no manual value; previous data stays stored. Percentages use the available totals, not a simple average of matches. Database version 38; backups include the new fields.
- Substitutions are imported for both teams when minutes played allow deducing who came on and off; those minutes show a `~` as estimates. Simultaneous changes do not get invented pairs. Events and manual data are preserved when completing a match.
- The quick update in Matches refreshes career data without importing new games into the match list and without marking them as ignored. Explicit importing stays available in the API connection.
- On X, new replies to the opponent's post distinguish its fans, who criticize their own club after a loss, from the career's fans, who tease. Chained replies receive the target's text and author and the conversation context.

## 0.10.3

- Player details organize personal and squad information in blocks, give financial values their own space and use compact histories when there is a single record. Progress charts and the actions to view or add records remain available.
- Season and Summary show where goals were scored from, the goal areas hit, goals without a location and penalties scored, missed, saved and conversion. The Summary respects the season filter. Missing coordinates are never invented.
- The match lineup can record the captain, optionally, and who takes the armband when the captain leaves. The history follows the substitution, even after correcting its minute, and appears in the match view and on the pitch. Individual and squad statistics include games as captain; older matches without that information keep no presumed captain.
- Database version 37; backups keep the new data.

## 0.10.2

- The social network becomes **X (social network)**, with the X symbol and its own black, white and grey palette. Saved conversations and posts remain available.
- In settings, the opponent's official post is optional and considers the result from its perspective.
- When refreshing the feed, **Custom generation** lets you choose a match or recent conversations, the number of fans, pages, newspapers and rivals, and the official posts not yet published. The choice applies to that generation only.
- Completing statistics from the API also merges the opponent's performances, keeping identities, photos, formation, ratings, events and substitutions already filled in. Before creating missing players, the app asks whether to create them, complete only existing ones or cancel. They stay in the opponent club's memory, outside the user's squad.
- The goal picker lists those players and the custom records of the imported squad, and can create a player by name and photo on the same screen. Database, links and backups stay compatible.

## 0.10.1

- Every screen follows the black and green palette in dark mode, or white and green in light mode. Matches, profile, transfers, settings and the social feed respect the selected appearance.
- Colours live in `lib/utils/AppColors.dart`, a `ThemeExtension` registered in the global theme. Components use `AppColors.of(context)` (background, panel, text, border and actions) or the theme's `ColorScheme`; appearance changes also update charts, fields and dialogs.
- Football event colours and chart series are centralized in the same file. Existing layouts and flows are preserved.

## 0.10.0

- **FC Career Live** brand: the square FCCL app icon and the horizontal logo in the menu.
- Teams and competitions without a crest use the FC Career Live logo.
- Existing careers, database and backups keep working after the update.

## 0.9.14

- Matches exported after the game's last save also appear for import and completion, at the top of the list, as "Not saved in the game yet". The report already has every player; once the game saves, the same match is recognized as imported.

## 0.9.13

- Relegation zones show only "Relegation" or "Relegation playoff", without the destination league name, which can be wrong in modded saves.
- A match registered by hand can be completed from the API: the cloud button next to favourite recommends the most similar game in the save (same day, opponent, venue and score) and fills in only what was empty. Score, date, opponent, goals, assists and cards with minutes, substitutions and recorded lineups stay as they are; missing players are added, and automatic imports no longer change that match.

## 0.9.12

- Tables show every column with horizontal scrolling, including wins, draws, losses, goals for and against, and form.
- Title, continental qualification, promotion and relegation zones use the rules sent by the API and the mapped names. Colours work for any league: the continental competition of the top places is tier 1, the next tier 2 and the following tier 3, and entry through the preliminary stage uses a lighter shade.
- Imported matches, or matches with a single configured correspondence, open the career details directly from Standings, even without a connection to the PC.

## 0.9.11

- Team mapping is organized in leagues that expand and collapse. Link selection also groups clubs by league and shows their crests and customizations.
- Custom clubs and leagues registered for several games appear in each compatible version; search opens the groups with results and also accepts the league name.

## 0.9.10

- The post counter and conversation title on the social feed show the total number of replies, including those not loaded yet. Loading more keeps that total; the user's replies are added and deleted ones are subtracted.

## 0.9.9

- Standings use the app's mapped names and crests, also for data already imported. The season switch moves to the calendar in the top bar.
- Tables, matches, rankings and teams follow the career surfaces and typography. Setup and draw stages are hidden; knockout ties show the teams, the games and the aggregate.
- The manager menu starts with Matches, Squad Center, Standings and My manager.

## 0.9.8

- Matches has an update shortcut next to the calendar for careers linked to FC Score. It uses that career's saved connection, a single progress bar from connection to completion, and asks for confirmation before adding new teams or matches. Customize remains available.
- Linked players are reused; unchanged records and overalls are not written again. Statistics, squads and tables keep being updated.
- The social feed shows every saved reply when a conversation opens and only generates more when they run out. The count shows published replies, including older batches. The conversation links authors with a line and, after posting a reply, opens its context. The AI receives the first post, the conversation thread and the full text of the message it must answer.

## 0.9.7

- A link already saved for the same team and career identifies an **update**, even before the first full batch, when the season changes or when the game renames the save file. Confirmed links are loaded from the database and do not need to be redone.
- Hub, queries, preparation, confirmation and result use update labels. The custom review shows only new or pending records; **Show configured links** lets you review the previous ones. Steps without news are skipped. Ignored games stay excluded, and configured games, the squad and history are preserved.

## 0.9.6+69

- Uses the real season statistics from the API: top scorers and rankings for assists, ratings, games, minutes, cards and goalkeepers per competition, including cups. Squads also show totals, competitions and recent games. Older API versions stay compatible.
- When repeating an import, **Update career** reuses the season's links and options and asks only to resolve the conflicts found. **Customize update** lets you review every choice and the mapping.
- Ignored matches stay saved and unselected in later updates; only new games are selected. The **Ignored** filter lets you bring them back. Exclusions made in older versions are read from the saved calendar. Choices are only stored when the import succeeds.

## 0.9.6+68

- Lower memory use when opening standings: full squads are no longer repeated for each scorer, player queries use bounded pages and top scorers only load when their tab opens. Group tables and scorer lists are built while scrolling.
- **Standings** sits directly in the menu, right after Matches.

## 0.9.6+67

- Entries of the same club present in different leagues of the catalog (such as Botafogo and Flamengo) are recognized, keeping their identity and using the linked league to choose the right entry. Older suggestions to create teams are reviewed when preparing the mapping and when importing matches.

## 0.9.6

- Integration with the **FC Score Career Mode API**, available in **Settings → FC Score API** and in each career's menu. The connection is explicit on every access: enter the PC's IP and port (default **38291**) or tap a recent address to fill in the fields. The last eight successful connections are saved. Start the API on the PC, use the same network and allow Node.js through the private network firewall when asked.
- For **USB on Android**, install Android platform-tools on the PC, enable USB debugging on the phone, connect it and authorize the computer. On the PC, run:

  ```powershell
  adb reverse tcp:38291 tcp:38291
  ```

  Then choose **USB cable → Connect** in the app. Repeat the command after reconnecting the cable. If you change the port, use the same port on both sides of the command. The network option also accepts the IP of the USB tethering interface.
- The first access reviews the **mapping** between save, career, club, league, season, competitions and players. You can use an existing career of the same game and type or create a new one. Links are saved and can be corrected from the hub's link icon. Adding the squad and recording current overalls are optional; new players join as substitutes and earlier history is preserved. Creating a career through the integration never silently switches the app's active career.
- Dedicated screens for **club** (manager, finances and records), **standings** (stages, groups, points, campaign and form), **matches** (filters and paging), **reports**, **squad** (with individual details), **competitions**, **history**, **transfers**, **academy** and **tactics**. Reading data never changes the game saves.
- Import shows a preview with date, season, opponent, competition and player links. The save result can be imported into the manager career and later completed with the detailed report, in the same match. Reports v043+ bring individual and team statistics, man of the match, starters and substitutes. Goal times and substitution pairs are never invented; each team's formation can be chosen in the preview. Stoppage time is preserved and does not turn on extra time automatically. In a player career, importing requires a report and the selected player.
- When opening a save result (last result or match list), the app looks for the exported report of the same game by `fixtureId`. When it exists, the preview already brings the players' performances and imports goals, assists, cards, ratings and minutes; without a report, only the score is imported. A match imported with the score only can be opened again and completed with the players.
- In the **+** for a new match, **Import match from the API** at the top lists the games played in the linked save, showing which have player performances and which were already imported.
- The game writes each save with a new file name. The career link, with the whole mapping, follows the save with the same name and type, without redoing the links.
- **Import into career** brings the selected competitions, tables by stage and group, the calendar of every team (results and upcoming games) and the participants' squads. The mapping covers competitions, clubs, leagues and players; earlier links are reused and can be corrected before confirming.
- Data is saved per career and season and is available offline in **Career menu → Competitions**, with **Table, Matches, Top scorers and Teams** tabs. "Tables and top scorers" in tournament results opens the same screen. Standings also feed the season's native tables, without treating the current leader as champion. League top scorers use the squads' `leagueGoals` from the save, without adding reports again; cups only show goals from detailed reports already imported, marked as partial coverage.
- In the manager career, the batch import can add your club's played games to **Matches** and your players to the **Squad Center**. **Review matches** lets you search and filter new or registered games, select the new ones, unselect any game or turn off importing into Matches. The preview identifies manual and imported games with the same validator used when saving: API identifier, or date, club, opponent, competition and venue according to the mapping. Existing games stay unselected and protected, even when the API score differs; changing links reruns the check. The transaction validates again to avoid duplicates even if a game is registered after the preview. Other clubs' games stay in the competitions and do not count in the manager's statistics. Existing matches, custom photos and names, lineups and confirmed final tables are preserved. Importing again updates competition data without duplicating it. Saves older than the latest import and closed seasons are never overwritten. The import writes everything in one transaction: any link or data error cancels the whole batch.
- During the review, the club's own squad and overalls are preserved by default; updating them is an explicit choice. The player review can filter by club and generate only the other teams' pending players. Suggestions prioritize identity and the current squad, reserving each record only once. Older suggestions to create teams are checked again against existing clubs.
- Database **v34** keeps the links and import identities, including the full match report, in backups. Validation considers the game, not only the exported batch: exporting the same game again or changing the save file of the same career never duplicates matches.

## 0.9.5

- Every player link selection in the integration offers **Create player here** and **Generate random**, even when the API sends no name or overall. The form adjusts name, position, overall and potential without leaving the import.
- Generation fills in only missing data; valid API fields and statistics are preserved. The dialog can also generate the data of every pending player at once and review the result.
- These records are only written with the import or link: cancelling the review discards the drafts, and importing again reuses the saved links.

## 0.9.4

- Duplicate, unavailable or incomplete player links open a step-by-step correction dialog before saving. Each step shows names, teams, API IDs, overalls and the chosen record.
- You can change the link or create a separate record; records used by another player are not offered. Cancelling discards the dialog's changes and keeps the import pending, with a shortcut to resume.
- Name suggestions respect known player IDs. Links are checked again inside the transaction and existing history is preserved.

## 0.9.3

- Backups read every database table in a single transaction, including imported API data, links, standings, squads, matches and reports. Data only viewed in the API is not downloaded into the backup.
- The backup also keeps language, theme, advanced options, AI settings and credentials, and the automatic results and trophies dismissed per career. Restoring reapplies those settings; older backups without that block stay valid and keep the current settings.
- Every photo and local image folder is included when **Include images** is checked (default); unchecking it leaves out only the image files, not the records or statistics.

## 0.8.5

- The menu no longer shows **More → Head-to-head**, and the team hub is called **Squad Center** (Central do elenco) in Portuguese.
- Tapping a player in the squad shows **Statistics** before **Remove player**.
- The profile's **Season** and **Summary** tabs show their panels in sequence, with scrolling, keeping chart controls and the season selection.
- In **Matches**, an independent filter chooses the current season, a specific season or all of them, combined with the tournament filter.

## 0.8.4

- The hub is now called **App settings**. Club, league, tournament and club customization forms use compact tabs, card fields with more room and fixed controls at the bottom.
- When creating a club, you can select several games and a source version for the competition. If the league does not exist in a selected version, it is created with the source's teams, without duplicating existing leagues. Existing clubs can also become available in other versions.
- The new **Custom players** tab gathers the players created in careers and lets you create and edit a shared catalog. They can be selected when adding players to the squad or in transfers, in any game and career. Each career keeps its own copy, photo and history; reusing a player in the same career does not duplicate the record. Catalog changes apply to new additions. Database v32 migrates existing players and keeps the catalog and its links in backups.

## 0.8.3

- The man of the match picker shows cards with photo, position, last overall and match performance, name search and the current choice highlighted.
- Team selection has league and club cards, crests, direct search with results in league context and the selected team marked. In a match, the opponent's or the career club's league opens first.
- Both searches keep focus when the keyboard opens and accept names typed without accents.

## 0.8.2

- The player search for purchases keeps focus and text when the keyboard opens or closes, keeping the list's look and filtering.
- Squads, lineups, player selection, transfers, statistics and comparisons show the last overall recorded in the career. Each season's starting values stay in the history.
- When editing a player, market value and wage fields get thousands separators while typing and when opening an existing record, keeping integer values.
- In the squad, tapping a starter or substitute opens **Remove player** and **Statistics**. Removal requires confirmation and affects only the selected season's squad, keeping the player's record and history.
- The confirmation can link the departure to a transfer of the same player with a pending release, or continue without a link. The link records the departure on the current career date, keeping fee, destination and planned release.
- The player stays in the statistics as a former player, even without appearances, and the season's full data (shirt, overall, wage and market value) is archived. The animated farewell also appears on removal, with or without a transfer, considering matches until the departure. Database v30 stores these records and includes them in backups.
- When signing, an optional dialog records games, goals, assists, average rating and notes from the season at the previous club. This data stays with the transfer, can be edited and feeds the posts' context, without creating fake matches or adding to the current club's numbers. Missing records mean unknown information, never that the player did not play that season. Database v31 keeps earlier data and includes this information in backups.
- When saving a new sale in **Transfers**, an animated farewell shows photo, destination club, games, goals, assists, average rating, man of the match awards, hat-tricks and the results record. The card also highlights the first recorded appearance, a standout match and season; goalkeepers get their recorded saves. The numbers consider only the selling club and matches up to the agreement date, across all seasons. Editing a transfer does not repeat the farewell, and failed saves never show it.

## 0.8.1

- Match registration keeps a single screen and the compact performance list. The switch between **Club** and **Opponent** sits inside **Lineups**.
- The opponent uses the same list and performance screen as the club. The **+** button registers a name and an optional photo; tapping a row opens the match events. Name and photo can be changed from the performance header or by long-pressing the row. Photos also appear on the pitch and are reused in later meetings.
- Coming on and going off use the same green and red triangles in the list and the formation.
- The opponent's goal and own goal shortcuts are on the main screen, below the lineup. The extra button to edit the opponent's lineup was removed from the view, keeping the pencil in the header. Detail tabs have 16 px side margins and space below.

## 0.8.0

- Match details have **Main**, **Timeline** and **Formation** tabs. The table position shows a discreet up, down or unchanged icon next to the number.
- Recorded events build the timeline, with stoppage time, assistants, substitutions and a running score when every goal is recorded.
- The formation shows the pitch, photos, ratings and cards; it lets you change the shape, move players by dragging and select related substitutes. The formation catalog was expanded in the squad and accepts custom shapes in a match. The lineup is saved per game, independent of later squad changes.
- In **Lineups → Opponent**, choosing a formation prepares the 11 positions to fill in the names, with performance, substitutions and related substitutes. The **Formation** tab switches between both teams' pitches, and the timeline gathers their events. Later games against the same team reuse names, formation and bench, which can be edited; ratings and events start empty. Database v29 adds these optional records per match and keeps earlier data.

## 0.7.1

- Refreshing the social feed continues the conversations of recent posts, including topics, announcements, transfers and matches.
- In **Generate posts → Club**, write the context and choose the day for the AI to publish a post from the career club's official account. Generations keep the context and club identity for consistent follow-ups.
- The refresh context uses only the last 10 posts from the last three days of the career. Reactions keep the date of the topic that started them, so a new post never makes old news recent again.
- A blank table position keeps the last known position of the same club, tournament and season. Match details show the rise, drop or no change compared with the previous game of that tournament.
- Individual reactions on the social feed consider the season's production and tell a bad performance from a bad run, keeping the tone chosen by the user.

## 0.7.0 and earlier

- **My manager** uses rounded fields and a birth date calendar, with age calculated on the career date. Name, nationality, birth date, playing style and biography feed upcoming news and interviews. The post composer lets you choose the publication day in the career.
- The side menu organizes pages in sections, highlights the current page and keeps settings and mode switching within reach.
- The matches hub shows the club, a results summary and recent form, with score cards and list, table and calendar views. Seasons, competitions and venue can be filtered, including all seasons. Games, Summary and Charts sit in separate tabs, one chart at a time: progress, results or performance by venue.
- The player profile has a renewed header and panels; Season and Summary let you choose a statistics group or analysis, with the progress of ratings, goals, assists and minutes per appearance.
- The visual style extends to the team hub, squad, transfers, academy, injuries, history, trophies, campaigns, head-to-head and settings. Fields, calendars, buttons, cards and dialogs share the same theme in light and dark modes. Streaks have Overall, Home and Production tabs. The social feed keeps its own theme. The Manrope font is bundled with its license in `assets/fonts/OFL-Manrope.txt`.
- Creating a custom player organizes the form in Identity, Attributes and Squad tabs, with a live preview, optional photo, position and nationality search, smooth transitions and animated overall and potential bars. It warns when the starting eleven is full and the player joins as a substitute. It is available when adding to the squad, in the player list and in transfers.
- Shot placement has a net with depth, soft posts and subtle grass stripes. The goal (3:1) and pitch (3:2) proportions, screen positions and tap coordinates stay the same.
- The **Seasons** menu closes the current season or any earlier one. Creating the next season first offers to close the current one. The final table can keep only your team's position or the other clubs too, with optional statistics, selection of the league's clubs and drag ordering. The entered standings define the league's final result.
- The season recap saves an animated presentation and **Summary**, **Competitions**, **Highlights** and **Journey** tabs, with progress, results, attack, defence, venue, rankings, biggest scores and season events. The data is preserved on closing and can be updated after corrections. Database v25 adds optional fields and stays compatible with earlier backups and careers.
- **Team analysis** gathers points percentage, goals, goal difference and possession over time, results distribution, attack and defence by month or season, performance by venue, technical averages, season comparison and a match timeline. Everything follows the period, season, club or national team, competition and venue filters. Missing statistics are left out of averages. Results use the score before penalties; points percentage uses `(3W + D) / (3G)`.
- The app creates and selects careers and registers seasons, matches, tournaments, trophies, career history, the manager's squad, transfers, academy (with promotion to the first team), injuries and tournament results. Matches record events per player (goals with minute, assistant and type, assists, substitutions, cards, own goals, missed penalties and injuries) and the opponent's goals. Custom leagues, clubs and tournaments, club customization, 10 languages, light and dark themes and ZIP backups are available. Data is stored in SQLite.
