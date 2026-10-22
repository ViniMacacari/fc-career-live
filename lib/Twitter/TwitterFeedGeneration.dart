part of 'TwitterGenerationService.dart';

extension _FeedGeneration on TwitterGenerationService {
  Future<String> _queueConversation(
    Person person, {
    required String type,
    String? topic,
    DateTime? date,
    String? prefix,
    SocialRow? originalEvent,
    String? generationId,
    TwitterGenerationSelection? selection,
  }) async {
    final database = await _store.db;
    final settings = await _store.preferences(person.id);
    final selected =
        date ?? await TwitterFeedContext.publicationDate(database, person);
    final day = DateTime(selected.year, selected.month, selected.day);
    final id =
        generationId ??
        '${prefix ?? (type == 'feed' ? 'more' : 'club')}:${const Uuid().v4()}';
    final event =
        originalEvent ??
        <String, Object?>{
          'playerTeamId': person.teamId,
          'playerTeamLeagueId': person.leagueId,
          'feedContext': await TwitterFeedContext.load(database, person, day),
        };
    if (type == 'feed' && (event['feedContext'] as List).isEmpty) {
      event['fallbackEvent'] ??= await _freshFixture(person, day);
      if (event['fallbackEvent'] == null) {
        throw const FormatException(
          'Não há assuntos recentes para continuar. '
          'Publique um post ou registre um evento novo na carreira.',
        );
      }
    }
    final frozen = <String, Object?>{
      ...event,
      'id': id,
      'eventType': type,
      if (selection != null) 'selection': selection.toMap(),
      'date': day.toIso8601String(),
      'topic': topic ?? 'as notícias e conversas recentes do feed',
    };
    final now = DateTime.now().toIso8601String();
    await database.insert('TwitterGenerations', {
      'id': id,
      'personId': person.id,
      'fixtureId': '',
      'eventType': type,
      'topic': frozen['topic'],
      'eventDate': frozen['date'],
      'contextJson': jsonEncode(frozen),
      'status': 'queued',
      'postCount': type == 'clubTopic'
          ? 1
          : selection?.total ?? settings.postCount,
      'replyCount': settings.replyCount,
      'createdAt': now,
      'updatedAt': now,
    });
    _store.changed();
    return id;
  }

  Future<SocialRow?> _freshFixture(Person person, DateTime date) async {
    final cutoff = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).subtract(const Duration(milliseconds: 1));
    return (await (await _store.db).query(
      person.category == PersonCategory.manager
          ? 'ManagerFixtures'
          : 'PlayerFixtures',
      columns: [
        'id',
        'date',
        'playerTeamId',
        'playerTeamLeagueId',
        'oppositeTeamId',
        'oppositeTeamLeagueId',
        'playerTeamScore',
        'oppositeTeamScore',
      ],
      where: 'personId = ? AND julianday(date) >= julianday(?) AND julianday(date) <= julianday(?)',
      whereArgs: [
        person.id,
        TwitterFeedContext.windowStart(date).toIso8601String(),
        cutoff.toIso8601String(),
      ],
      orderBy: 'julianday(date) DESC, createdAt DESC',
      limit: 1,
    )).firstOrNull;
  }

  Future<Map<String, Object?>> _recentFeedContext(
    Person person,
    SocialRow event,
  ) async {
    final database = await _store.db;
    final catalog = await GameCatalog.load();
    final profile = person.category == PersonCategory.manager
        ? ManagerProfile.decode(
            (await database.query(
              'Persons',
              columns: ['managerProfile'],
              where: 'id = ?',
              whereArgs: [person.id],
            )).firstOrNull?['managerProfile'],
          )
        : null;
    String label(Object? id, Object? league) => catalog.teamLabel(
      person.fifaVersion,
      id.toString(),
      leagueId: league as String?,
    );
    final date = DateTime.parse(event['date'] as String);
    final fallback = event['fallbackEvent'] as Map?;
    return {
      'career': {
        'name': profile?.displayName ?? person.name,
        'date': TwitterCareerSummary.day(event['date']),
        'mode': person.category.name,
        'club': label(event['playerTeamId'], event['playerTeamLeagueId']),
      },
      'feedScope': {
        'from': TwitterCareerSummary.day(
          TwitterFeedContext.windowStart(date).toIso8601String(),
        ),
        'through': TwitterCareerSummary.day(event['date']),
        'maxRootPosts': TwitterFeedContext.recentRootLimit,
        'rule': 'Somente os assuntos desta janela; não completar com notícias antigas.',
      },
      'recentFeed': event['feedContext'],
      if (fallback != null && (event['feedContext'] as List).isEmpty)
        'freshEvent': {
          'date': fallback['date'],
          'club': label(
            fallback['playerTeamId'],
            fallback['playerTeamLeagueId'],
          ),
          'opponent': label(
            fallback['oppositeTeamId'],
            fallback['oppositeTeamLeagueId'],
          ),
          'clubGoals': fallback['playerTeamScore'],
          'opponentGoals': fallback['oppositeTeamScore'],
        },
    };
  }

  Future<void> _readyForConversation(Person person) async {
    if (isBusy(person.id)) {
      throw const FormatException('Já existe uma geração em andamento.');
    }
    await _store.initialize(person);
    if (!await _isReady()) {
      throw const FormatException(
        'Configure a chave de API e o modelo nas configurações de IA.',
      );
    }
  }
}
