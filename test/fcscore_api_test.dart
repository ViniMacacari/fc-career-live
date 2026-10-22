import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcmanager/FcScore/FcScoreApi.dart';
import 'package:mcmanager/FcScore/FcScoreModels.dart';
import 'package:mcmanager/FcScore/FcScoreRepository.dart';
import 'package:mcmanager/utils/GameCatalog.dart';

import 'fcscore_fixture.dart';

void main() {
  test('LAN, USB, custom port, URL and IPv6 addresses', () {
    expect(
      fcScoreAddress('192.168.0.20').toString(),
      'http://192.168.0.20:38291/api',
    );
    expect(fcScoreAddress('127.0.0.1').port, 38291);
    expect(fcScoreAddress('http://192.168.0.20:40000/api/').port, 40000);
    expect(fcScoreAddress('[::1]', port: 1234).host, '::1');
    expect(fcScoreAddress('https://pc.local/api', port: 40000).scheme, 'https');
  });
  for (final invalid in [
    '',
    'file://192.168.0.1',
    'http://user:pass@pc',
    'http://pc/path',
    'pc?token=secret',
    'pc#x',
  ]) {
    test(
      'Reject address $invalid',
      () => expect(
        () => fcScoreAddress(invalid),
        throwsA(isA<FcScoreException>()),
      ),
    );
  }
  test('Reject invalid ports', () {
    for (final port in [0, -1, 65536]) {
      expect(
        () => fcScoreAddress('pc', port: port),
        throwsA(isA<FcScoreException>()),
      );
    }
  });
  test(
    'Connection checks health and game version, preserves Unicode',
    () async {
      final requests = <http.Request>[];
      final api = fakeApi(fcScoreAddress('pc'), requests: requests);
      expect((await api.connect())['gameVersion'], 'FC 26');
      final remote = await FcScoreRemoteCareer.load(api, 'save-A', 'FC 26');
      expect(remote.club['name'], 'São Paulo');
      expect(remote.gameVersion, 'FC26');
      expect(remote.competitions.length, 1);
      expect(requests.take(2).map((r) => r.url.path), [
        '/api/health',
        '/api/meta',
      ]);
      api.close();
    },
  );
  for (final status in [400, 404, 422, 503]) {
    test('HTTP $status becomes an actionable error', () async {
      final api = FcScoreApi(
        fcScoreAddress('pc'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'PERFORMANCE_DIR_UNAVAILABLE',
                'message': 'Reveja a consulta',
              },
            }),
            status,
          ),
        ),
      );
      await expectLater(
        api.connect(),
        throwsA(
          isA<FcScoreException>().having((e) => e.status, 'status', status),
        ),
      );
      api.close();
    });
  }
  test('Network failure, timeout and malformed JSON', () async {
    for (final client in [
      MockClient((_) async => throw http.ClientException('offline')),
      MockClient((_) => Completer<http.Response>().future),
      MockClient((_) async => http.Response('<html>wrong server</html>', 200)),
    ]) {
      final api = FcScoreApi(
        fcScoreAddress('pc'),
        client: client,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(api.connect(), throwsA(isA<FcScoreException>()));
      api.close();
    }
  });
  test('Select save before report and reject active-save race', () async {
    final requests = <http.Request>[];
    final api = fakeApi(fcScoreAddress('pc'), requests: requests);
    await api.report('save-A');
    expect(requests.map((r) => r.method), ['POST', 'GET']);
    expect(jsonDecode(requests.first.body), {'saveId': 'save-A'});
    api.close();
    final wrong = FcScoreApi(
      fcScoreAddress('pc'),
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.method == 'POST' ? {'id': 'save-A'} : apiReport(saveId: 'save-B'),
          ),
          200,
        ),
      ),
    );
    await expectLater(wrong.report('save-A'), throwsA(isA<FcScoreException>()));
    wrong.close();
  });
  test('Fixture query encodes independent filters and pagination', () async {
    final requests = <http.Request>[];
    final api = fakeApi(fcScoreAddress('pc'), requests: requests);
    await api.object(
      api.careerPath('save-A', 'fixtures'),
      query: {
        'status': 'played',
        'competitionId': '1528',
        'limit': '50',
        'offset': '50',
      },
    );
    expect(requests.single.url.queryParameters, {
      'status': 'played',
      'competitionId': '1528',
      'limit': '50',
      'offset': '50',
    });
    api.close();
  });
  test(
    'De-para uses exact ID or unique full name, never approximate names',
    () {
      final players = <Map<String, Object?>>[
        {'id': 'a', 'realPlayerId': '10', 'name': 'Pedro S.'},
        {'id': 'b', 'name': 'Marcos Antonio'},
      ];
      expect(fcSuggestPlayer(apiPlayer(10, 'Outra pessoa'), players), 'a');
      expect(fcSuggestPlayer(apiPlayer(11, 'Marcos Antônio'), players), 'b');
      expect(fcSuggestPlayer(apiPlayer(20, 'Pedro'), players), isNull);
      expect(fcSuggestPlayer(apiPlayer(20, 'Pedro S.'), players), isNull);
      expect(
        fcSuggestPlayer(apiPlayer(10, 'Pedro S.'), [
          ...players,
          {'id': 'duplicate', 'realPlayerId': '10', 'name': 'Outro nome'},
        ]),
        isNull,
      );
      expect(
        fcSuggestPlayer(apiPlayer(20, 'Marcos Antônio'), [
          ...players,
          {'id': 'c', 'name': 'Marcos Antonio'},
        ]),
        isNull,
      );
      expect(
        fcSuggestReference(
          {'id': 598, 'name': 'SPFC'},
          [const CatalogItem('598', 'São Paulo')],
        ),
        '598',
      );
    },
  );
  test(
    'Reference matching prefers an exact name over a colliding catalog ID',
    () {
      expect(
        fcSuggestReference(
          {'id': 598, 'name': 'São Paulo'},
          [
            const CatalogItem('598', 'Outro clube'),
            const CatalogItem('spfc', 'Sao Paulo'),
          ],
        ),
        'spfc',
      );
    },
  );
  test(
    'Canonical identity ignores capture time, server address and export batch',
    () {
      final a = FcScoreMatch.fromReport(apiReport());
      final b = FcScoreMatch.fromReport(
        apiReport(id: 'another-export', saveId: 'save-B'),
      );
      expect(a.remoteKey, b.remoteKey);
      expect(a.date, DateTime(2028, 6, 25));
      expect(
        a.remoteKey,
        FcScoreMatch.fromFixture(apiFixture(), 'save-A').remoteKey,
      );
    },
  );
}
