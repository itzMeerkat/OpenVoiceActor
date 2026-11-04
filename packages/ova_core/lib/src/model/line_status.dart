/// Works out a line's status per language (spec section 9). These are plain
/// functions, so screens and tests share one definition.
library;

import 'local_data.dart';
import 'project.dart';
import 'submission.dart';

enum LineStatus {
  notRecorded('Not recorded'),

  /// Recorded by the actor and not exported yet. Actor side only.
  recorded('Recorded'),
  submitted('Submitted'),
  outdated('Outdated'),
  retakeRequested('Retake requested'),
  approved('Approved');

  const LineStatus(this.label);
  final String label;
}

/// How many lines are in each status.
class ProjectProgress {
  ProjectProgress(this.counts);

  final Map<LineStatus, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);
  int of(LineStatus status) => counts[status] ?? 0;
}

/// True when the line's text changed in a way that needs new recording.
bool isOutdated(Take take, Line? line) {
  final current = line?.text[take.language];
  return current != null && take.textVersion < current.version;
}

/// True if the wording shown when recording differs from the current text,
/// without the initiator having asked for new recording.
bool spokenTextDiffers(Take take, Line? line) {
  final current = line?.text[take.language];
  return current != null &&
      take.textVersion >= current.version &&
      take.spokenText != current.value;
}

/// A request stays open until that actor records the line again after it.
bool isRetakeOpen(
  RetakeRequest request,
  Iterable<(Take, String)> takesAndActors,
) {
  return !takesAndActors.any(
    (entry) =>
        entry.$2 == request.actorId &&
        entry.$1.lineId == request.lineId &&
        entry.$1.language == request.language &&
        entry.$1.recordedAt.isAfter(request.createdAt),
  );
}

LineStatus initiatorLineStatus(
  Project project,
  ReviewData review,
  Line line,
  String language,
) {
  final takes = review.takes
      .where((t) => t.take.lineId == line.id && t.take.language == language)
      .toList();
  final pairs = [for (final t in takes) (t.take, t.actor.id)];
  final hasOpenRetake = project.retakeRequests.any(
    (r) =>
        r.lineId == line.id && r.language == language && isRetakeOpen(r, pairs),
  );
  if (hasOpenRetake) return LineStatus.retakeRequested;

  final selection = review.selectionFor(line.id, language);
  final currentVersion = line.text[language]?.version;
  if (selection != null &&
      currentVersion != null &&
      selection.approvedTextVersion >= currentVersion) {
    return LineStatus.approved;
  }

  if (takes.isEmpty) return LineStatus.notRecorded;
  return takes.every((t) => isOutdated(t.take, line))
      ? LineStatus.outdated
      : LineStatus.submitted;
}

LineStatus actorLineStatus(
  Project project,
  ActorSession session,
  String actorId,
  Line line,
  String language,
) {
  final takes = session.takes
      .where((t) => t.lineId == line.id && t.language == language)
      .toList();
  final pairs = [for (final t in takes) (t, actorId)];
  final hasOpenRetake = project.retakeRequests.any(
    (r) =>
        r.actorId == actorId &&
        r.lineId == line.id &&
        r.language == language &&
        isRetakeOpen(r, pairs),
  );
  if (hasOpenRetake) return LineStatus.retakeRequested;

  if (takes.isEmpty) return LineStatus.notRecorded;
  final current = takes.where((t) => !isOutdated(t, line));
  if (current.isEmpty) return LineStatus.outdated;
  return current.any((t) => session.exportedTakeIds.contains(t.id))
      ? LineStatus.submitted
      : LineStatus.recorded;
}
