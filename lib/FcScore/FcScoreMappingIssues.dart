import 'FcScoreApi.dart';

class FcWorldMappingIssue {
  const FcWorldMappingIssue({
    required this.kind,
    required this.remoteIds,
    required this.message,
    this.restoreOwnClub = false,
    this.sourceProblem = false,
  });
  final String kind, message;
  final Set<String> remoteIds;
  final bool restoreOwnClub, sourceProblem;
}

class FcWorldMappingException extends FcScoreException {
  FcWorldMappingException(this.issues)
    : super(issues.map((i) => i.message).join('\n\n'));
  final List<FcWorldMappingIssue> issues;
}
