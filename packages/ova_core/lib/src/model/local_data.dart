/// Data each app keeps for itself and never exchanges (spec section 9).
library;

import 'project.dart';
import 'submission.dart';

/// The two ways of using the app. One person can be both, on separate projects.
enum AppRole { owner, actor }

/// App-wide settings, stored once per install.
class AppSettings {
  AppSettings({
    required this.actorId,
    this.displayName = '',
    this.creditName = '',
    this.inputDeviceName,
    this.exclusiveMode = false,
    this.inputChannel = 0,
    this.role = AppRole.owner,
    Json? extra,
  }) : extra = extra ?? {};

  factory AppSettings.fromJson(Json json) => AppSettings(
    actorId: json['actorId'] as String,
    displayName: json['displayName'] as String? ?? '',
    creditName: json['creditName'] as String? ?? '',
    inputDeviceName: json['inputDeviceName'] as String?,
    exclusiveMode: json['exclusiveMode'] as bool? ?? false,
    inputChannel: json['inputChannel'] as int? ?? 0,
    role: json['role'] == AppRole.actor.name ? AppRole.actor : AppRole.owner,
    extra: unknownFields(json, const {
      'actorId',
      'displayName',
      'creditName',
      'inputDeviceName',
      'exclusiveMode',
      'inputChannel',
      'role',
    }),
  );

  final String actorId;
  String displayName;
  String creditName;
  String? inputDeviceName;
  bool exclusiveMode;
  int inputChannel;
  AppRole role;
  final Json extra;

  Json toJson() => {
    ...extra,
    'actorId': actorId,
    'displayName': displayName,
    'creditName': creditName,
    'inputDeviceName': ?inputDeviceName,
    'exclusiveMode': exclusiveMode,
    'inputChannel': inputChannel,
    'role': role.name,
  };
}

/// A take being recorded. Saved before capture starts, so a crash can still
/// tie the recovered audio back to its line.
class PendingTake {
  PendingTake({
    required this.id,
    required this.lineId,
    required this.language,
    required this.recordedAt,
    required this.spokenText,
    required this.textVersion,
    this.characterId,
    this.inputDeviceName,
  });

  factory PendingTake.fromJson(Json json) => PendingTake(
    id: json['id'] as String,
    lineId: json['lineId'] as String,
    language: json['language'] as String,
    characterId: json['characterId'] as String?,
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    spokenText: json['spokenText'] as String,
    textVersion: json['textVersion'] as int,
    inputDeviceName: json['inputDeviceName'] as String?,
  );

  final String id;
  final String lineId;
  final String language;
  final String? characterId;
  final DateTime recordedAt;
  final String spokenText;
  final int textVersion;
  final String? inputDeviceName;

  Json toJson() => {
    'id': id,
    'lineId': lineId,
    'language': language,
    'characterId': ?characterId,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'spokenText': spokenText,
    'textVersion': textVersion,
    'inputDeviceName': ?inputDeviceName,
  };
}

/// An actor's local work on one project.
class ActorSession {
  ActorSession({
    List<Take>? takes,
    List<PendingTake>? pending,
    Set<String>? exportedTakeIds,
    this.termsAcceptance,
  }) : takes = takes ?? [],
       pending = pending ?? [],
       exportedTakeIds = exportedTakeIds ?? {};

  factory ActorSession.fromJson(Json json) => ActorSession(
    takes: [
      for (final t in json['takes'] as List? ?? const [])
        Take.fromJson(t as Json),
    ],
    pending: [
      for (final p in json['pending'] as List? ?? const [])
        PendingTake.fromJson(p as Json),
    ],
    exportedTakeIds: {
      for (final id in json['exportedTakeIds'] as List? ?? const [])
        id as String,
    },
    termsAcceptance: json['termsAcceptance'] == null
        ? null
        : UsageTermsAcceptance.fromJson(json['termsAcceptance'] as Json),
  );

  final List<Take> takes;
  final List<PendingTake> pending;
  final Set<String> exportedTakeIds;
  UsageTermsAcceptance? termsAcceptance;

  Json toJson() => {
    'takes': [for (final t in takes) t.toJson()],
    'pending': [for (final p in pending) p.toJson()],
    'exportedTakeIds': exportedTakeIds.toList(),
    'termsAcceptance': ?termsAcceptance?.toJson(),
  };
}

/// A take an initiator imported, with who sent it.
class ReviewTake {
  ReviewTake({
    required this.take,
    required this.actor,
    required this.submissionId,
  });

  factory ReviewTake.fromJson(Json json) => ReviewTake(
    take: Take.fromJson(json['take'] as Json),
    actor: ActorInfo.fromJson(json['actor'] as Json),
    submissionId: json['submissionId'] as String,
  );

  final Take take;
  final ActorInfo actor;
  final String submissionId;

  Json toJson() => {
    'take': take.toJson(),
    'actor': actor.toJson(),
    'submissionId': submissionId,
  };
}

/// The initiator's final choice for a line and language. [approvedTextVersion]
/// is the line's version at that moment, so a later text change that needs new
/// recording undoes the approval without losing the choice.
class TakeSelection {
  TakeSelection({
    required this.lineId,
    required this.language,
    required this.takeId,
    required this.approvedTextVersion,
  });

  factory TakeSelection.fromJson(Json json) => TakeSelection(
    lineId: json['lineId'] as String,
    language: json['language'] as String,
    takeId: json['takeId'] as String,
    approvedTextVersion: json['approvedTextVersion'] as int,
  );

  final String lineId;
  final String language;
  final String takeId;
  final int approvedTextVersion;

  Json toJson() => {
    'lineId': lineId,
    'language': language,
    'takeId': takeId,
    'approvedTextVersion': approvedTextVersion,
  };
}

/// An initiator's local review state on one project.
class ReviewData {
  ReviewData({List<ReviewTake>? takes, List<TakeSelection>? selections})
    : takes = takes ?? [],
      selections = selections ?? [];

  factory ReviewData.fromJson(Json json) => ReviewData(
    takes: [
      for (final t in json['takes'] as List? ?? const [])
        ReviewTake.fromJson(t as Json),
    ],
    selections: [
      for (final s in json['selections'] as List? ?? const [])
        TakeSelection.fromJson(s as Json),
    ],
  );

  final List<ReviewTake> takes;
  final List<TakeSelection> selections;

  TakeSelection? selectionFor(String lineId, String language) => selections
      .where((s) => s.lineId == lineId && s.language == language)
      .firstOrNull;

  Json toJson() => {
    'takes': [for (final t in takes) t.toJson()],
    'selections': [for (final s in selections) s.toJson()],
  };
}
