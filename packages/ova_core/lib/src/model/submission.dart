/// The contents of `submission.json`. See docs/format-spec.md section 4.
library;

import 'project.dart';

class ActorInfo {
  ActorInfo({
    required this.id,
    required this.displayName,
    this.creditName,
    Json? extra,
  }) : extra = extra ?? {};

  factory ActorInfo.fromJson(Json json) => ActorInfo(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    creditName: json['creditName'] as String?,
    extra: unknownFields(json, const {'id', 'displayName', 'creditName'}),
  );

  final String id;
  final String displayName;
  final String? creditName;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'displayName': displayName,
    'creditName': ?creditName,
  };
}

class TakeAudio {
  TakeAudio({
    required this.sampleFormat,
    required this.bitDepth,
    required this.sampleRateHz,
    required this.channels,
    required this.durationMs,
    this.container = 'wav',
    Json? extra,
  }) : extra = extra ?? {};

  factory TakeAudio.fromJson(Json json) => TakeAudio(
    container: json['container'] as String,
    sampleFormat: json['sampleFormat'] as String,
    bitDepth: json['bitDepth'] as int,
    sampleRateHz: json['sampleRateHz'] as int,
    channels: json['channels'] as int,
    durationMs: json['durationMs'] as int,
    extra: unknownFields(json, const {
      'container',
      'sampleFormat',
      'bitDepth',
      'sampleRateHz',
      'channels',
      'durationMs',
    }),
  );

  final String container;
  final String sampleFormat;
  final int bitDepth;
  final int sampleRateHz;
  final int channels;
  final int durationMs;
  final Json extra;

  /// Short form for screens, such as `24-bit 48 kHz mono`.
  String get label {
    final khz = sampleRateHz / 1000;
    final rate = khz == khz.roundToDouble()
        ? khz.toInt().toString()
        : khz.toStringAsFixed(1);
    final kind = sampleFormat == 'float' ? '-bit float' : '-bit';
    final layout = channels == 1 ? 'mono' : '$channels ch';
    return '$bitDepth$kind $rate kHz $layout';
  }

  Json toJson() => {
    ...extra,
    'container': container,
    'sampleFormat': sampleFormat,
    'bitDepth': bitDepth,
    'sampleRateHz': sampleRateHz,
    'channels': channels,
    'durationMs': durationMs,
  };
}

class TakeCapture {
  TakeCapture({
    this.platform,
    this.appVersion,
    this.inputDeviceName,
    this.droppedFrames,
    this.clippedSamples,
    Json? extra,
  }) : extra = extra ?? {};

  factory TakeCapture.fromJson(Json json) => TakeCapture(
    platform: json['platform'] as String?,
    appVersion: json['appVersion'] as String?,
    inputDeviceName: json['inputDeviceName'] as String?,
    droppedFrames: json['droppedFrames'] as int?,
    clippedSamples: json['clippedSamples'] as int?,
    extra: unknownFields(json, const {
      'platform',
      'appVersion',
      'inputDeviceName',
      'droppedFrames',
      'clippedSamples',
    }),
  );

  final String? platform;
  final String? appVersion;
  final String? inputDeviceName;
  final int? droppedFrames;
  final int? clippedSamples;
  final Json extra;

  TakeCapture withoutDeviceName() => TakeCapture(
    platform: platform,
    appVersion: appVersion,
    droppedFrames: droppedFrames,
    clippedSamples: clippedSamples,
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'platform': ?platform,
    'appVersion': ?appVersion,
    'inputDeviceName': ?inputDeviceName,
    'droppedFrames': ?droppedFrames,
    'clippedSamples': ?clippedSamples,
  };
}

class Take {
  Take({
    required this.id,
    required this.lineId,
    required this.language,
    required this.recordedAt,
    required this.spokenText,
    required this.textVersion,
    required this.file,
    required this.sha256,
    required this.audio,
    this.characterId,
    this.favorite = false,
    this.capture,
    Json? extra,
  }) : extra = extra ?? {};

  factory Take.fromJson(Json json) => Take(
    id: json['id'] as String,
    lineId: json['lineId'] as String,
    language: json['language'] as String,
    characterId: json['characterId'] as String?,
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    favorite: json['favorite'] as bool? ?? false,
    spokenText: json['spokenText'] as String,
    textVersion: json['textVersion'] as int,
    file: json['file'] as String,
    sha256: json['sha256'] as String,
    audio: TakeAudio.fromJson(json['audio'] as Json),
    capture: json['capture'] == null
        ? null
        : TakeCapture.fromJson(json['capture'] as Json),
    extra: unknownFields(json, const {
      'id',
      'lineId',
      'language',
      'characterId',
      'recordedAt',
      'favorite',
      'spokenText',
      'textVersion',
      'file',
      'sha256',
      'audio',
      'capture',
    }),
  );

  final String id;
  final String lineId;
  final String language;
  final String? characterId;
  final DateTime recordedAt;
  bool favorite;
  final String spokenText;
  final int textVersion;
  final String file;
  final String sha256;
  final TakeAudio audio;
  final TakeCapture? capture;
  final Json extra;

  /// True if the take lost audio or hit full scale while recording.
  bool get hasCaptureProblem =>
      (capture?.droppedFrames ?? 0) > 0 || (capture?.clippedSamples ?? 0) > 0;

  Take copyForExport({required bool includeDeviceName}) => Take(
    id: id,
    lineId: lineId,
    language: language,
    characterId: characterId,
    recordedAt: recordedAt,
    favorite: favorite,
    spokenText: spokenText,
    textVersion: textVersion,
    file: file,
    sha256: sha256,
    audio: audio,
    capture: includeDeviceName ? capture : capture?.withoutDeviceName(),
    extra: extra,
  );

  Json toJson() => {
    ...extra,
    'id': id,
    'lineId': lineId,
    'language': language,
    'characterId': ?characterId,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'favorite': favorite,
    'spokenText': spokenText,
    'textVersion': textVersion,
    'file': file,
    'sha256': sha256,
    'audio': audio.toJson(),
    'capture': ?capture?.toJson(),
  };
}

class UsageTermsAcceptance {
  UsageTermsAcceptance({required this.version, required this.acceptedAt});

  factory UsageTermsAcceptance.fromJson(Json json) => UsageTermsAcceptance(
    version: json['version'] as int,
    acceptedAt: DateTime.parse(json['acceptedAt'] as String),
  );

  final int version;
  final DateTime acceptedAt;

  Json toJson() => {
    'version': version,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
  };
}

class Submission {
  Submission({
    required this.id,
    required this.projectId,
    required this.projectRevision,
    required this.actor,
    required this.takes,
    this.usageTermsAcceptance,
    Json? extra,
  }) : extra = extra ?? {};

  factory Submission.fromJson(Json json) => Submission(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    projectRevision: json['projectRevision'] as int,
    actor: ActorInfo.fromJson(json['actor'] as Json),
    usageTermsAcceptance: json['usageTermsAcceptance'] == null
        ? null
        : UsageTermsAcceptance.fromJson(json['usageTermsAcceptance'] as Json),
    takes: [
      for (final t in json['takes'] as List? ?? const [])
        Take.fromJson(t as Json),
    ],
    extra: unknownFields(json, const {
      'id',
      'projectId',
      'projectRevision',
      'actor',
      'usageTermsAcceptance',
      'takes',
    }),
  );

  final String id;
  final String projectId;
  final int projectRevision;
  final ActorInfo actor;
  final UsageTermsAcceptance? usageTermsAcceptance;
  final List<Take> takes;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'projectId': projectId,
    'projectRevision': projectRevision,
    'actor': actor.toJson(),
    'usageTermsAcceptance': ?usageTermsAcceptance?.toJson(),
    'takes': [for (final t in takes) t.toJson()],
  };
}
