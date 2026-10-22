enum TwitterAccountKind {
  journal('Jornais'),
  fanPage('Páginas de torcedores'),
  fan('Torcedores'),
  rival('Rivais'),
  club('Clubes'),
  user('Seu perfil');

  const TwitterAccountKind(this.label);
  final String label;
}

String normalizeTwitterHandle(String value, {bool club = false}) {
  var result = value.trim().replaceFirst(RegExp(r'^@+'), '');
  const accents = 'áàâãäÁÀÂÃÄéèêëÉÈÊËíìîïÍÌÎÏóòôõöÓÒÔÕÖúùûüÚÙÛÜçÇñÑ';
  const plain = 'aaaaaAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUcCnN';
  for (var i = 0; i < accents.length; i++) {
    result = result.replaceAll(accents[i], plain[i]);
  }
  if (club) {
    result = result.replaceAll(
      RegExp(
        r'\s+(FC|CF|SC|Futebol Clube|Football Club)$',
        caseSensitive: false,
      ),
      '',
    );
  }
  result = result.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  return result.length > 15 ? result.substring(0, 15) : result;
}

class TwitterAccount {
  const TwitterAccount({
    required this.id,
    required this.personId,
    required this.name,
    required this.handle,
    required this.kind,
    this.bio = '',
    this.avatarPath,
    this.teamId,
    this.leagueId,
    this.supportedTeamId,
    this.averageLikes,
    this.followers = 0,
    this.following = false,
    this.enabled = true,
  });
  final String id, personId, name, handle, bio;
  final TwitterAccountKind kind;
  final String? avatarPath, teamId, leagueId;
  final String? supportedTeamId;
  final int? averageLikes;
  final int followers;
  final bool following, enabled;

  factory TwitterAccount.fromMap(Map<String, Object?> row) => TwitterAccount(
    id: row['id'] as String,
    personId: row['personId'] as String,
    name: row['name'] as String,
    handle: row['handle'] as String,
    kind: TwitterAccountKind.values.firstWhere(
      (k) => k.name == row['category'],
      orElse: () => TwitterAccountKind.fan,
    ),
    bio: row['bio'] as String? ?? '',
    avatarPath: row['avatarPath'] as String?,
    teamId: row['teamId'] as String?,
    leagueId: row['leagueId'] as String?,
    supportedTeamId: row['supportedTeamId'] as String?,
    averageLikes: row['averageLikes'] as int?,
    followers: row['followers'] as int? ?? 0,
    following: row['following'] == 1,
    enabled: row['enabled'] != 0,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'personId': personId,
    'name': name,
    'handle': normalizeTwitterHandle(handle),
    'category': kind.name,
    'bio': bio,
    'avatarPath': avatarPath,
    'teamId': teamId,
    'leagueId': leagueId,
    'supportedTeamId': supportedTeamId,
    'averageLikes': averageLikes,
    'followers': followers,
    'following': following ? 1 : 0,
    'enabled': enabled ? 1 : 0,
  };
}

class TwitterPreferences {
  static const maxPosts = 100;
  const TwitterPreferences({
    this.enabled = true,
    this.triggerMode = 'everyMatch',
    this.matchInterval = 3,
    this.postCount = 4,
    this.replyCount = 2,
    this.allowProfanity = true,
    this.generateTransfers = true,
    this.generateOpponentPost = false,
    this.pagePosts = 1,
    this.journalPosts = 1,
    this.rivalPosts = 1,
    this.createPages = true,
  });

  final bool createPages;
  final bool enabled, allowProfanity, generateTransfers, generateOpponentPost;
  final String triggerMode;
  final int matchInterval, postCount, replyCount;

  final int pagePosts, journalPosts, rivalPosts;
  factory TwitterPreferences.fromMap(Map<String, Object?> r) =>
      TwitterPreferences(
        enabled: r['enabled'] != 0,
        triggerMode: r['triggerMode'] as String? ?? 'everyMatch',
        matchInterval: (r['matchInterval'] as int? ?? 3).clamp(1, 30),
        postCount: (r['postCount'] as int? ?? 4).clamp(1, maxPosts),
        replyCount: (r['replyCount'] as int? ?? 2) > 0 ? 2 : 0,
        allowProfanity: r['allowProfanity'] != 0,
        generateTransfers: r['generateTransfers'] != 0,
        generateOpponentPost: r['generateOpponentPost'] == 1,
        pagePosts: (r['pagePosts'] as int? ?? 1).clamp(0, maxPosts),
        journalPosts: (r['journalPosts'] as int? ?? 1).clamp(0, maxPosts),
        rivalPosts: (r['rivalPosts'] as int? ?? 1).clamp(0, maxPosts),
        createPages: r['createPages'] != 0,
      );
  Map<String, Object?> toMap(String personId) => {
    'personId': personId,
    'enabled': enabled ? 1 : 0,
    'triggerMode': triggerMode,
    'matchInterval': matchInterval,
    'postCount': postCount,
    'replyCount': replyCount,
    'allowProfanity': allowProfanity ? 1 : 0,
    'generateTransfers': generateTransfers ? 1 : 0,
    'generateOpponentPost': generateOpponentPost ? 1 : 0,
    'pagePosts': pagePosts,
    'journalPosts': journalPosts,
    'rivalPosts': rivalPosts,
    'createPages': createPages ? 1 : 0,
  };
}

String shortSocialCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} mi';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} mil';
  return '$value';
}

class TwitterGenerationSelection {
  const TwitterGenerationSelection({
    this.fans = 0,
    this.pages = 0,
    this.journals = 0,
    this.rivals = 0,
    this.clubPost = false,
    this.opponentPost = false,
  });
  final int fans, pages, journals, rivals;
  final bool clubPost, opponentPost;
  int get total => fans + pages + journals + rivals;
  bool get valid =>
      [fans, pages, journals, rivals].every((n) => n >= 0) &&
      total <= TwitterPreferences.maxPosts &&
      (total > 0 || clubPost || opponentPost);
  Map<String, Object?> toMap() => {
    'fans': fans,
    'pages': pages,
    'journals': journals,
    'rivals': rivals,
    'clubPost': clubPost,
    'opponentPost': opponentPost,
  };
  factory TwitterGenerationSelection.fromMap(Map r) =>
      TwitterGenerationSelection(
        fans: (r['fans'] as num?)?.toInt() ?? 0,
        pages: (r['pages'] as num?)?.toInt() ?? 0,
        journals: (r['journals'] as num?)?.toInt() ?? 0,
        rivals: (r['rivals'] as num?)?.toInt() ?? 0,
        clubPost: r['clubPost'] == true,
        opponentPost: r['opponentPost'] == true,
      );
}
