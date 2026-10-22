part of 'TwitterGenerationService.dart';

extension TwitterTransferGeneration on TwitterGenerationService {
  String transferEventLabel(Person person, SocialRow row) =>
      person.category == PersonCategory.manager
      ? transferCardLabel(row)
      : const {
              'transwer': 'Transferência',
              'inloan': 'Empréstimo',
              'outloan': 'Volta de empréstimo',
              'contractChange': 'Renovação de contrato',
              'retired': 'Aposentadoria',
            }[row['type']] ??
            'Transferência';

  Future<List<SocialRow>> transferEvents(Person person) async {
    final database = await _store.db;
    if (person.category == PersonCategory.manager) {
      return database.rawQuery(
        '''SELECT t.*, cp.name AS playerName
        FROM TeamTransferItem t LEFT JOIN CustomCreatedPlayer cp
          ON cp.id = t.playerInstanceId AND cp.personId = t.personId
        WHERE t.personId = ? AND t.id NOT LIKE '%:exchange'
        ORDER BY julianday(t.date) DESC, t.rowid DESC LIMIT 60''',
        [person.id],
      );
    }
    return (await database.query(
          'PlayerTransferItem',
          where: "personId = ? AND type NOT IN ('startCareer', 'startExistingPlayerCareer')",
          whereArgs: [person.id],
          orderBy: 'transferDate DESC',
          limit: 60,
        ))
        .map(
          (row) => <String, Object?>{
            ...row,
            'date': row['transferDate'],
            'playerName': person.name,
          },
        )
        .toList();
  }

  Future<SocialRow?> _transferEvent(
    Person person,
    String id, {
    bool release = false,
  }) async {
    final database = await _store.db;
    final manager = person.category == PersonCategory.manager;
    final rows = manager
        ? await database.rawQuery(
            '''SELECT t.*, cp.name AS playerName
          FROM TeamTransferItem t LEFT JOIN CustomCreatedPlayer cp
            ON cp.id = t.playerInstanceId AND cp.personId = t.personId
          WHERE t.id = ? AND t.personId = ?''',
            [id, person.id],
          )
        : await database.query(
            'PlayerTransferItem',
            where: 'id = ? AND personId = ?',
            whereArgs: [id, person.id],
          );
    if (rows.isEmpty) return null;
    final row = <String, Object?>{...rows.first};
    if (!manager) {
      if (['startCareer', 'startExistingPlayerCareer'].contains(row['type'])) {
        return null;
      }
      row['date'] = row['transferDate'];
      row['playerName'] = person.name;
    }
    final incoming = manager
        ? isIncomingTeamTransfer(row, person.teamId)
        : row['toTeamId'] == person.teamId ||
              row['fromTeamId'] != person.teamId;
    final careerTeam = manager
        ? row[incoming ? 'toTeamId' : 'fromTeamId'] as String? ?? person.teamId
        : person.teamId;
    final careerLeague = manager
        ? row[incoming ? 'toLeagueId' : 'fromLeagueId'] as String? ??
              person.leagueId
        : person.leagueId;
    final otherTeam = row[incoming ? 'fromTeamId' : 'toTeamId'];
    final exchange = manager
        ? await database.rawQuery(
            '''SELECT t.*, cp.name AS playerName FROM TeamTransferItem t
      LEFT JOIN CustomCreatedPlayer cp
        ON cp.id = t.playerInstanceId AND cp.personId = t.personId
      WHERE t.personId = ? AND t.id = ?''',
            [person.id, '$id:exchange'],
          )
        : <SocialRow>[];
    return {
      'id': id,
      'eventType': release ? 'transferRelease' : 'transfer',
      'date': release ? row['releaseDate'] ?? row['date'] : row['date'],
      'playerTeamId': careerTeam,
      'playerTeamLeagueId': careerLeague,
      'oppositeTeamId': otherTeam,
      'oppositeTeamLeagueId': row[incoming ? 'fromLeagueId' : 'toLeagueId'],
      'direction': incoming ? 'arrival' : 'departure',
      'transfer': row,
      if (exchange.isNotEmpty) 'exchangeTransfer': exchange.first,
    };
  }

  Future<SocialRow?> _generationEvent(Person person, SocialRow job) async {
    if (job['eventType'] == 'feed' || job['eventType'] == 'clubTopic') {
      final snapshot = job['contextJson'] as String?;
      if (snapshot == null) {
        throw const FormatException(
          'O contexto salvo da publicação não foi encontrado.',
        );
      }
      return Map<String, Object?>.from(jsonDecode(snapshot) as Map);
    }
    if (job['eventType'] == 'topic') {
      var date = DateTime.tryParse(job['eventDate']?.toString() ?? '');
      final database = await _store.db;
      if (date == null) {
        final post = (await database.query(
          'TwitterPosts',
          columns: ['postedAt'],
          where: 'personId = ? AND generationId = ?',
          whereArgs: [person.id, job['id']],
          orderBy: 'createdAt ASC',
          limit: 1,
        )).firstOrNull;
        date = DateTime.tryParse(post?['postedAt']?.toString() ?? '');
        if (date == null) {
          final draft = (await database.query(
            'TwitterDrafts',
            columns: ['snapshot'],
            where: 'personId = ? AND generationId = ?',
            whereArgs: [person.id, job['id']],
            orderBy: 'createdAt ASC',
            limit: 1,
          )).firstOrNull;
          if (draft != null) {
            final snapshot = jsonDecode(draft['snapshot'] as String) as Map;
            if (snapshot['fixture'] case final Map event) {
              date = DateTime.tryParse(event['date']?.toString() ?? '');
            }
          }
        }
      }
      final event = await _topicEvent(
        person,
        topic: job['topic'] as String?,
        id: job['id'] as String,
        date: date,
      );
      if (job['eventDate'] == null) {
        await database.update(
          'TwitterGenerations',
          {'eventDate': event['date']},
          where: 'personId = ? AND id = ?',
          whereArgs: [person.id, job['id']],
        );
      }
      return event;
    }
    return job['transferId'] == null
        ? SqlService.withDatabase(
            await _store.db,
          ).getFixture(person.category, person.id, job['fixtureId'] as String)
        : _transferEvent(
            person,
            job['transferId'] as String,
            release: job['eventType'] == 'transferRelease',
          );
  }

  static String _transferFingerprint(SocialRow event) {
    final row = event['transfer'] as Map;
    final facts = {
      for (final key in [
        'playerInstanceId',
        'fromTeamId',
        'fromLeagueId',
        'toTeamId',
        'toLeagueId',
        'type',
        'date',
        'releaseDate',
        'endOfLoanDirection',
        'transferValue',
        'wage',
        'weeklyWage',
        'yearlyWage',
        'previousClubStats',
      ])
        key: row[key],
    };
    if (event['exchangeTransfer'] case final Map exchange) {
      facts['exchange'] = {
        for (final key in [
          'playerInstanceId',
          'fromTeamId',
          'toTeamId',
          'previousClubStats',
        ])
          key: exchange[key],
      };
    }
    return jsonEncode(facts).codeUnits
        .fold<int>(0, (hash, unit) => (hash * 31 + unit) & 0x7fffffff)
        .toRadixString(16);
  }

  Future<void> _enqueueTransfer(
    Person person,
    SocialRow event,
    String id,
  ) async {
    final settings = await _store.preferences(person.id);
    final now = DateTime.now().toIso8601String();
    await (await _store.db).insert('TwitterGenerations', {
      'id': id,
      'personId': person.id,
      'fixtureId': '',
      'transferId': event['id'],
      'eventType': event['eventType'],
      'status': 'queued',
      'postCount': settings.postCount,
      'replyCount': settings.replyCount,
      'createdAt': now,
      'updatedAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> onTransferSaved(Person person, String id) async {
    try {
      await _store.initialize(person);
      final settings = await _store.preferences(person.id);
      if (!settings.enabled ||
          !settings.generateTransfers ||
          settings.triggerMode == 'manual') {
        return;
      }
      final event = await _transferEvent(person, id);
      if (event == null) return;
      await _enqueueTransfer(
        person,
        event,
        '${person.id}:transfer:$id:${_transferFingerprint(event)}',
      );
      _store.changed();
      unawaited(runPending(person));
    } catch (error) {
      errors[person.id] = TwitterGenerationService.errorText(error);
      _store.changed();
    }
  }

  Future<void> generateTransfer(Person person, String id) async {
    if (isBusy(person.id)) {
      throw const FormatException('Já existe uma geração em andamento.');
    }
    await _store.initialize(person);
    final event = await _transferEvent(person, id);
    if (event == null) {
      throw const FormatException('A transferência foi removida.');
    }
    if (!await _isReady()) {
      throw const FormatException(
        'Configure a chave de API e o modelo nas configurações de IA.',
      );
    }
    final jobId = 'manual:${const Uuid().v4()}';
    await _enqueueTransfer(person, event, jobId);
    await runPending(person, onlyId: jobId);
    final job = (await (await _store.db).query(
      'TwitterGenerations',
      where: 'id = ? AND personId = ?',
      whereArgs: [jobId, person.id],
    )).firstOrNull;
    if (job != null && job['status'] != 'done') {
      throw FormatException(
        job['error']?.toString() ?? 'Geração pendente. Tente novamente.',
      );
    }
  }

  Future<void> onTransferDeleted(Person person, String id) async {
    final database = await _store.db;
    await database.transaction((txn) async {
      final jobs = await txn.query(
        'TwitterGenerations',
        columns: ['id'],
        where: "personId = ? AND transferId = ? AND status != 'done'",
        whereArgs: [person.id, id],
      );
      for (final job in jobs) {
        await txn.update(
          'TwitterDrafts',
          {'consumed': 1},
          where: 'personId = ? AND generationId = ?',
          whereArgs: [person.id, job['id']],
        );
        await txn.update(
          'TwitterGenerations',
          {'status': 'cancelled', 'error': null},
          where: 'personId = ? AND id = ?',
          whereArgs: [person.id, job['id']],
        );
      }
    });
    _store.changed();
  }

  Future<void> _enqueueDueTransferReleases(
    Person person,
    String gameDate,
  ) async {
    if (person.category != PersonCategory.manager) return;
    final settings = await _store.preferences(person.id);
    if (!settings.enabled ||
        !settings.generateTransfers ||
        settings.triggerMode == 'manual') {
      return;
    }
    final rows = await (await _store.db).rawQuery(
      '''SELECT t.id
      FROM TeamTransferItem t
      WHERE t.personId = ? AND date(t.releaseDate) > date(t.date)
        AND date(t.releaseDate) <= date(?)
        AND t.id NOT LIKE '%:exchange'
        AND EXISTS (SELECT 1 FROM TwitterGenerations g WHERE g.personId = t.personId
          AND g.transferId = t.id AND g.eventType = 'transfer' AND g.status = 'done')
        AND NOT EXISTS (SELECT 1 FROM TwitterGenerations g WHERE g.personId = t.personId
          AND g.transferId = t.id AND g.eventType = 'transferRelease'
          AND g.status != 'cancelled')''',
      [person.id, gameDate],
    );
    for (final row in rows) {
      final event = await _transferEvent(
        person,
        row['id'] as String,
        release: true,
      );
      if (event != null) {
        await _enqueueTransfer(
          person,
          event,
          '${person.id}:transferRelease:${event['id']}:${_transferFingerprint(event)}',
        );
      }
    }
  }

  Future<Map<String, Object?>> _eventContext(
    Person person,
    SocialRow event,
  ) async => _customizedContext(person, await _baseEventContext(person, event));

  Future<Map<String, Object?>> _baseEventContext(
    Person person,
    SocialRow event,
  ) async {
    if (TwitterGenerationService._conversationEvent(event)) {
      return _topicContext(person, event);
    }
    if (!TwitterGenerationService._isTransfer(event)) {
      return compactContext(person, event);
    }
    final database = await _store.db;
    final catalog = await GameCatalog.load();
    final row = Map<String, Object?>.from(event['transfer'] as Map);
    String? team(Object? id, Object? league) => id == null
        ? null
        : catalog.teamLabel(
            person.fifaVersion,
            id.toString(),
            leagueId: league?.toString(),
          );
    final agreement = DateTime.tryParse(row['date']?.toString() ?? '');
    final release = DateTime.tryParse(row['releaseDate']?.toString() ?? '');
    final asOf = DateTime.parse(event['date'] as String);
    final phase = event['eventType'] == 'transferRelease'
        ? 'release'
        : 'agreement';
    final status = phase == 'release'
        ? 'released'
        : release != null && agreement != null && release.isAfter(agreement)
        ? 'pendingRelease'
        : release != null
        ? 'released'
        : 'releaseUnknown';
    final summary = await TwitterCareerSummary.load(
      database,
      person,
      teamId: event['playerTeamId'] as String,
      date: event['date'] as String,
      seasonId: row['seasonId'] as String?,
    );
    final social = await database.rawQuery(
      '''SELECT p.*, a.handle
      FROM TwitterPosts p JOIN TwitterAccounts a ON a.id = p.accountId AND a.personId = p.personId
      WHERE p.personId = ? AND p.deleted = 0 AND p.aiGenerated = 1
        AND julianday(p.postedAt) <= julianday(?)
        AND julianday(p.postedAt) >= julianday(?)
      ORDER BY (p.transferId = ?) DESC, p.createdAt DESC LIMIT 8''',
      [
        person.id,
        event['date'],
        asOf.subtract(const Duration(days: 30)).toIso8601String(),
        row['id'],
      ],
    );
    final performances = person.category != PersonCategory.manager
        ? <SocialRow>[]
        : await database.rawQuery(
            '''SELECT p.*, f.date, f.playerTeamId, f.seasonId, f.tournamentId,
              f.extraTime, f.captaincy, f.playerOfTheMatchId, f.isPotmFromMyTeam
          FROM ManagerFixturePlayerPerformances p
          JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
          WHERE p.personId = ? AND p.playerInstanceId = ? AND julianday(f.date) <= julianday(?)
            AND f.playerTeamId = ?
            AND p.rowid = (SELECT MAX(d.rowid) FROM ManagerFixturePlayerPerformances d
              WHERE d.personId = p.personId AND d.fixtureId = p.fixtureId
                AND d.playerInstanceId = p.playerInstanceId)
          ORDER BY julianday(f.date) DESC, p.rowid DESC''',
            [
              person.id,
              row['playerInstanceId'],
              event['date'],
              event['playerTeamId'],
            ],
          );
    final exchange = event['exchangeTransfer'] as Map?;
    Map<String, Object?> previousPerformance(Map transfer) {
      final parsed = TransferPreviousClubStats.decode(
        transfer['previousClubStats'],
      );
      final stats = parsed?.availableAt(asOf) == true ? parsed : null;
      return {
        'status': stats == null ? 'unknown' : 'provided',
        'club': team(transfer['fromTeamId'], transfer['fromLeagueId']),
        'clubId': transfer['fromTeamId'],
        'seasonId': transfer['seasonId'],
        'scope': 'previousClubOnly',
        if (stats != null) ...stats.toMap(),
      };
    }

    return {
      'career': {
        'name': summary.coachName ?? person.name,
        if (summary.coachProfile != null)
          'coachProfile': summary.coachProfile!.context,
        'mode': person.category.name,
        'club': team(event['playerTeamId'], event['playerTeamLeagueId']),
        'clubId': event['playerTeamId'],
        'currency': person.currency ?? 'EUR',
      },
      'eventDate': event['date'],
      'eventPhase': phase,
      'transfer': {
        'player': row['playerName'],
        'type': row['type'],
        'label': person.category == PersonCategory.manager
            ? transferCardLabel(row)
            : row['type'],
        'direction': event['direction'],
        'agreementDate': row['date'],
        'releaseDate': row['releaseDate'],
        'status': status,
        'from': team(row['fromTeamId'], row['fromLeagueId']),
        'to': team(row['toTeamId'], row['toLeagueId']),
        'fee': row['transferValue'],
        'weeklyWage': row['wage'] ?? row['weeklyWage'],
        'annualWage': row['yearlyWage'],
        if (row['endOfLoanDirection'] != null)
          'loanDirection': row['endOfLoanDirection'],
        if (person.category == PersonCategory.manager &&
            event['direction'] == 'arrival')
          'previousClubPerformance': previousPerformance(row),
        if (exchange != null) 'exchangePlayer': exchange['playerName'],
        if (exchange != null &&
            isIncomingTeamTransfer(
              Map<String, Object?>.from(exchange),
              person.teamId,
            ))
          'exchangePreviousClubPerformance': previousPerformance(exchange),
      },
      if (person.category == PersonCategory.manager)
        'playerClubHistory': TwitterClubPlayerHistory.build(
          performances,
          summary,
        ),
      'recentPlayerPerformances': [
        for (final p in performances.take(5))
          {
            for (final key in [
              'date',
              'playerTeamId',
              'seasonId',
              'avgRating',
              'goalsCount',
              'assistsCount',
            ])
              key: p[key],
          },
      ],
      ...summary.brief(),
      'socialMemory': social
          .map(TwitterGenerationService._socialMemory)
          .toList(),
    };
  }
}
