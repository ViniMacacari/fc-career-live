import 'dart:convert';

import '../../Twitter/TwitterCareerSummary.dart';
import '../../Twitter/TwitterGenerationService.dart';
import '../../Twitter/TwitterModels.dart';
import '../../Twitter/TwitterStore.dart';
import '../../models/Person.dart';
import '../../models/PressConference.dart';
import '../GameCatalog.dart';
import '../SqlService.dart';
import 'AIModelService.dart';

class PressConferenceService {
  PressConferenceService._();

  static const questionCount = 3;

  static Future<PressConference> start(
    Person person,
    Map<String, Object?> fixture,
  ) async {
    final context = await TwitterGenerationService.instance.compactContext(
      person,
      fixture,
    );
    final career = context['career'] as Map;
    final coach = career['name'] as String;
    final previous = await _previous(person, fixture);
    final outlets = [
      for (final account in await TwitterStore.instance.accounts(person.id))
        if (account.kind == TwitterAccountKind.journal) account.name,
    ].take(8).toList();
    final config = await AIConfiguration.load();
    final response = await AIModelService.complete(
      _system(coach, config),
      jsonEncode({
        'task':
            'Escreva exatamente $questionCount perguntas, cada uma de um '
            'jornalista diferente, para o técnico na coletiva depois desta '
            'partida.',
        'coach': coach,
        'coachProfile': career['coachProfile'],
        'context': context,
        if (previous.isNotEmpty) 'previousPressConferences': previous,
        if (outlets.isNotEmpty) 'outlets': outlets,
        'format': {
          'questions': [
            {
              'reporter': 'nome e sobrenome do jornalista',
              'outlet': 'veículo',
              'question': 'pergunta, até 240 caracteres',
            },
          ],
        },
      }),
    );
    return PressConference(
      status: PressConferenceStatus.started,
      questions: _parse(response.text),
      headline: _headline(context['match']),
    );
  }

  static String _system(String coach, AIConfiguration config) => [
    'Você organiza a coletiva de imprensa depois de uma partida de um modo '
        'carreira de futebol. É um jogo: clubes e jogadores podem ter nomes '
        'reais, mas a história é fictícia.',
    'Escreva perguntas como jornalistas esportivos fazem numa coletiva de '
        'verdade: diretas, curtas e específicas sobre o que aconteceu nesta '
        'partida e sobre o momento do clube. Cite jogadores, lances, números, '
        'sequência, tabela e escolhas do técnico quando estiverem no contexto. '
        'Cada jornalista tem um ângulo próprio; não repita o assunto de outra '
        'pergunta.',
    'O tom acompanha o contexto. Depois de derrota, eliminação, sequência '
        'ruim ou atuação fraca, as perguntas incomodam: cobrança, pressão, '
        'decisões discutíveis, jogadores que foram mal. Depois de vitória, '
        'perguntas sobre destaques, ambição e próximos desafios, sem bajulação.',
    'Use só fatos do contexto: não invente resultados, lesões, transferências '
        'nem declarações. Se houver previousPressConferences, um jornalista '
        'pode retomar algo que o técnico disse e confrontar com o que '
        'aconteceu depois. Se houver outlets, são veículos que já cobrem o '
        'clube; use-os quando fizer sentido.',
    'O técnico é $coach.',
    if (config.instructions.trim().isNotEmpty)
      'Instruções gerais do usuário (siga quando se aplicarem a uma coletiva): '
          '${config.instructions.trim()}',
    'Escreva em ${config.language}. Responda só com JSON.',
  ].join('\n\n');

  static Future<List<Map<String, Object?>>> _previous(
    Person person,
    Map<String, Object?> fixture,
  ) async {
    final rows = await SqlService.instance.getPreviousPressConferences(
      person.id,
      date: fixture['date'] as String,
      excludeFixtureId: fixture['id'] as String,
    );
    if (rows.isEmpty) return const [];
    final catalog = await GameCatalog.load();
    return [
      for (final row in rows)
        if (PressConference.decode(row['pressConference']) case final press?)
          {
            'date': TwitterCareerSummary.day(row['date']),
            'match':
                '${row['playerTeamScore'] ?? 0}x${row['oppositeTeamScore'] ?? 0} '
                'contra ${catalog.teamLabel(person.fifaVersion, '${row['oppositeTeamId']}', leagueId: row['oppositeTeamLeagueId']?.toString())}',
            'transcript': press.transcript(),
          },
    ];
  }

  static String? _headline(Object? match) {
    if (match is! Map) return null;
    final penalties = match['penalties'] == null
        ? ''
        : ' (${match['penalties']} pên.)';
    return [
      '${match['team']} ${match['score']}$penalties ${match['opponent']}',
      if (match['competition'] != null) '${match['competition']}',
    ].join(' · ');
  }

  static List<PressQuestion> _parse(String text) {
    final start = text.indexOf('{'), end = text.lastIndexOf('}');
    if (start < 0 || end < start) {
      throw const FormatException(
        'O modelo não retornou JSON. Tente outro modelo.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw const FormatException(
        'O modelo retornou um JSON inválido. Tente novamente.',
      );
    }
    final items = decoded is Map ? decoded['questions'] : null;
    final questions = [
      if (items is List)
        for (final item in items)
          if (item is Map)
            PressQuestion.fromMap(Map<String, dynamic>.from(item)),
    ].where((q) => q.question.isNotEmpty).take(questionCount).toList();
    if (questions.isEmpty) {
      throw const FormatException(
        'O modelo não retornou as perguntas. Tente novamente.',
      );
    }
    return questions;
  }
}
