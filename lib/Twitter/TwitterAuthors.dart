import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'TwitterModels.dart';
import 'TwitterStore.dart';

class TwitterAuthors {
  TwitterAuthors(
    this.personId,
    Iterable<TwitterAccount> accounts, {
    required this.careerTeamId,
    this.opponentTeamId,
    this.newPages = true,
  }) : _accounts = {for (final a in accounts) a.handle.toLowerCase(): a};

  final String personId, careerTeamId;
  final String? opponentTeamId;

  final bool newPages;
  final Map<String, TwitterAccount> _accounts;
  final Map<String, String> _aliases = {};
  final Set<String> _newIds = {};

  String audience(TwitterAccount a) {
    if (a.kind == TwitterAccountKind.journal) return 'neutral';
    if (a.supportedTeamId == null) return 'unknown';
    return a.supportedTeamId == careerTeamId ? 'career' : 'rival';
  }

  List<TwitterAccount> forPrompt(
    Random random, {
    Set<String> recentHandles = const {},
    Map<TwitterAccountKind, int> needed = const {},
  }) {
    final pool =
        _accounts.values
            .where(
              (a) =>
                  a.enabled &&
                  a.kind != TwitterAccountKind.user &&
                  a.kind != TwitterAccountKind.club &&
                  !TwitterStore.isLegacyExample(a),
            )
            .toList()
          ..shuffle(random);
    bool recent(TwitterAccount a) =>
        recentHandles.contains(a.handle.toLowerCase());
    final ordered = [...pool.where((a) => !recent(a)), ...pool.where(recent)];
    return [
      for (final kind in const [
        TwitterAccountKind.journal,
        TwitterAccountKind.fanPage,
        TwitterAccountKind.fan,
        TwitterAccountKind.rival,
      ])
        ...ordered.where((a) => a.kind == kind).take(_offer(needed[kind] ?? 0)),
    ];
  }

  static int _offer(int need) => need <= 0 ? 0 : min(20, need + 3);

  static Map<TwitterAccountKind, int> needs({
    Iterable<String> postKinds = const [],
    int replies = 0,
  }) {
    final result = <TwitterAccountKind, int>{};
    void add(TwitterAccountKind kind, int count) {
      if (count > 0) result[kind] = (result[kind] ?? 0) + count;
    }

    for (final name in postKinds) {
      add(TwitterAccountKind.values.byName(name), 1);
    }
    add(TwitterAccountKind.fan, replies);
    add(TwitterAccountKind.rival, (replies / 5).ceil());
    add(TwitterAccountKind.fanPage, (replies / 10).ceil());
    return result;
  }

  static int newAccountsAllowed(
    Map<TwitterAccountKind, int> needed,
    List<TwitterAccount> offered,
  ) {
    var missing = 0;
    for (final MapEntry(key: kind, value: count) in needed.entries) {
      missing += max(0, count - offered.where((a) => a.kind == kind).length);
    }
    return min(20, max(2, missing));
  }

  String? _support(
    Map<dynamic, dynamic> row,
    String handle,
    TwitterAccountKind kind,
  ) {
    if (kind == TwitterAccountKind.journal) return null;
    final other = 'other:$handle';
    return switch ('${row['supports'] ?? ''}'.trim().toLowerCase()) {
      'career' => careerTeamId,
      'opponent' => opponentTeamId ?? other,
      'other' => other,
      _ when kind == TwitterAccountKind.rival => opponentTeamId ?? other,
      _ => careerTeamId,
    };
  }

  void register(Object? value, {Object? affiliations}) {
    if (affiliations is List) {
      for (final row in affiliations.take(20)) {
        if (row is! Map) continue;
        final raw = _text(row, 'handle', 60);
        if (raw == null) continue;
        final handle = normalizeTwitterHandle(raw).toLowerCase();
        final a = _accounts[handle];
        if (a == null ||
            !a.enabled ||
            a.kind == TwitterAccountKind.club ||
            a.kind == TwitterAccountKind.user) {
          continue;
        }
        if (a.supportedTeamId == null && a.kind != TwitterAccountKind.journal) {
          _accounts[handle] = TwitterAccount.fromMap({
            ...a.toMap(),
            'supportedTeamId': _support(row, handle, a.kind),
          });
        }
      }
    }
    if (value is! List) return;
    for (final entry in value.take(20)) {
      if (entry is! Map) continue;
      final name = _text(entry, 'name', 60);
      final handle = normalizeTwitterHandle(_text(entry, 'handle', 60) ?? '');
      final kind = TwitterAccountKind.values
          .take(4)
          .where((k) => k.name == entry['kind'])
          .firstOrNull;
      if (name == null ||
          handle.isEmpty ||
          kind == null ||
          RegExp(
            r'^(torcedor|rival|usuário|usuario|fan|user)\s*0*\d+$',
            caseSensitive: false,
          ).hasMatch(name)) {
        continue;
      }
      final rawBio = entry['bio'];
      final bio = rawBio is String
          ? String.fromCharCodes(rawBio.trim().runes.take(180))
          : '';
      final previous = _accounts[handle.toLowerCase()];
      if (previous == null &&
          !newPages &&
          (kind == TwitterAccountKind.fanPage ||
              kind == TwitterAccountKind.journal)) {
        final support = _support(entry, handle.toLowerCase(), kind);
        final existing = _accounts.values
            .where(
              (a) =>
                  a.enabled &&
                  a.kind == kind &&
                  !TwitterStore.isLegacyExample(a) &&
                  (kind == TwitterAccountKind.journal ||
                      a.supportedTeamId == support),
            )
            .toList();
        if (existing.isNotEmpty) {
          _aliases[handle.toLowerCase()] =
              existing[handle.codeUnits.fold<int>(
                        0,
                        (a, b) => (a * 31 + b) & 0x7fffffff,
                      ) %
                      existing.length]
                  .handle
                  .toLowerCase();
          continue;
        }
      }
      if (previous != null) {
        if (!previous.enabled ||
            previous.kind != kind ||
            TwitterStore.isLegacyExample(previous)) {
          continue;
        }
        if (previous.supportedTeamId == null &&
            kind != TwitterAccountKind.journal) {
          _accounts[handle.toLowerCase()] = TwitterAccount.fromMap({
            ...previous.toMap(),
            'supportedTeamId': _support(entry, handle.toLowerCase(), kind),
          });
        }
        continue;
      }
      final random = Random(
        handle.codeUnits.fold<int>(0, (a, b) => a * 31 + b),
      );
      final (base, range) = switch (kind) {
        TwitterAccountKind.journal => (10000, 290000),
        TwitterAccountKind.fanPage => (1000, 79000),
        TwitterAccountKind.fan => (100, 5400),
        _ => (100, 3900),
      };
      final account = TwitterAccount(
        id: const Uuid().v4(),
        personId: personId,
        name: name,
        handle: handle,
        kind: kind,
        bio: bio,
        supportedTeamId: _support(entry, handle.toLowerCase(), kind),
        followers: base + random.nextInt(range),
      );
      _accounts[handle.toLowerCase()] = account;
      _newIds.add(account.id);
    }
  }

  TwitterAccount? author(Map<String, dynamic> row) {
    final value = row['author'];
    if (value is! String || value.trim().isEmpty) return null;
    final handle = normalizeTwitterHandle(value).toLowerCase();
    final a = _accounts[_aliases[handle] ?? handle];
    if (a == null ||
        !a.enabled ||
        a.kind == TwitterAccountKind.user ||
        a.kind == TwitterAccountKind.club ||
        TwitterStore.isLegacyExample(a)) {
      return null;
    }
    return a;
  }

  bool canReply(Map<String, dynamic> row) => switch (author(row)?.kind) {
    null || TwitterAccountKind.journal => false,
    _ => true,
  };

  Future<void> saveUsed(DatabaseExecutor txn, List<SocialRow> posts) async {
    final live = (await txn.query(
      'TwitterAccounts',
      where: 'personId = ?',
      whereArgs: [personId],
    )).map(TwitterAccount.fromMap);
    final byHandle = {for (final a in live) a.handle.toLowerCase(): a};
    final byId = {for (final a in _accounts.values) a.id: a};
    final remap = <String, String>{};
    for (final id in posts.map((r) => r['accountId'] as String).toSet()) {
      final proposed = byId[id]!;
      var current = byHandle[proposed.handle.toLowerCase()];
      if (current == null) {
        if (!_newIds.contains(id)) {
          throw const FormatException(
            'Uma conta foi removida durante a geração.',
          );
        }
        await txn.insert('TwitterAccounts', proposed.toMap());
        current = proposed;
        byHandle[proposed.handle.toLowerCase()] = current;
      }
      if (!current.enabled ||
          current.kind != proposed.kind ||
          current.kind == TwitterAccountKind.user ||
          current.kind == TwitterAccountKind.club ||
          TwitterStore.isLegacyExample(current) ||
          (current.supportedTeamId != null &&
              current.supportedTeamId != proposed.supportedTeamId)) {
        throw const FormatException(
          'Uma conta foi alterada durante a geração.',
        );
      }
      if (current.supportedTeamId == null && proposed.supportedTeamId != null) {
        await txn.update(
          'TwitterAccounts',
          {'supportedTeamId': proposed.supportedTeamId},
          where: 'id = ? AND personId = ?',
          whereArgs: [current.id, personId],
        );
        current = TwitterAccount.fromMap({
          ...current.toMap(),
          'supportedTeamId': proposed.supportedTeamId,
        });
      }
      remap[id] = current.id;
      _accounts[current.handle.toLowerCase()] = current;
    }
    for (final row in posts) {
      row['accountId'] = remap[row['accountId']];
    }
  }

  static String? _text(Map<dynamic, dynamic> row, String key, int max) {
    final value = row[key];
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().runes.length > max) {
      return null;
    }
    return value.trim();
  }
}
