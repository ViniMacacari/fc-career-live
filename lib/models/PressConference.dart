import 'dart:convert';

class PressQuestion {
  PressQuestion({
    required this.reporter,
    required this.outlet,
    required this.question,
    this.answer = '',
  });

  factory PressQuestion.fromMap(Map<String, dynamic> map) => PressQuestion(
    reporter: map['reporter']?.toString().trim() ?? '',
    outlet: map['outlet']?.toString().trim() ?? '',
    question: map['question']?.toString().trim() ?? '',
    answer: map['answer']?.toString() ?? '',
  );

  final String reporter, outlet, question;
  String answer;

  Map<String, Object?> toMap() => {
    'reporter': reporter,
    'outlet': outlet,
    'question': question,
    'answer': answer,
  };
}

enum PressConferenceStatus { declined, started, done }

class PressConference {
  PressConference({
    required this.status,
    this.questions = const [],
    this.headline,
    this.shared = false,
    this.updatedAt,
  });

  PressConference.declined()
    : this(status: PressConferenceStatus.declined, updatedAt: DateTime.now());

  final PressConferenceStatus status;
  final List<PressQuestion> questions;

  final String? headline;

  final bool shared;
  final DateTime? updatedAt;

  bool get done => status == PressConferenceStatus.done;

  static PressConference? decode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final status = PressConferenceStatus.values
          .where((s) => s.name == map['status'])
          .firstOrNull;
      if (status == null) return null;
      return PressConference(
        status: status,
        questions: [
          for (final item in map['questions'] as List? ?? const [])
            if (item is Map) PressQuestion.fromMap(Map.from(item)),
        ],
        headline: map['headline'] as String?,
        shared: map['shared'] == true,
        updatedAt: DateTime.tryParse('${map['updatedAt']}'),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'status': status.name,
    if (questions.isNotEmpty)
      'questions': [for (final q in questions) q.toMap()],
    'headline': ?headline,
    if (shared) 'shared': true,
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
  });

  PressConference copyWith({
    PressConferenceStatus? status,
    List<PressQuestion>? questions,
    String? headline,
    bool? shared,
  }) => PressConference(
    status: status ?? this.status,
    questions: questions ?? this.questions,
    headline: headline ?? this.headline,
    shared: shared ?? this.shared,
    updatedAt: DateTime.now(),
  );

  List<Map<String, String>> transcript() => [
    for (final q in questions)
      {
        if (q.reporter.isNotEmpty) 'reporter': q.reporter,
        if (q.outlet.isNotEmpty) 'outlet': q.outlet,
        'question': q.question,
        'answer': q.answer.trim().isEmpty
            ? '(o técnico não respondeu)'
            : q.answer.trim(),
      },
  ];
}
