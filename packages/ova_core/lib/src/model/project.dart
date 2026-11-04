/// The contents of `project.json`. See docs/format-spec.md section 3.
///
/// Every class keeps JSON fields it doesn't know in [extra] and writes them
/// back, because the spec requires readers to preserve them.
library;

typedef Json = Map<String, dynamic>;

Json unknownFields(Json json, Set<String> known) => {
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

class LineText {
  LineText(this.value, this.version);

  factory LineText.fromJson(Json json) =>
      LineText(json['value'] as String, json['version'] as int);

  String value;
  int version;

  Json toJson() => {'value': value, 'version': version};
}

class Line {
  Line({
    required this.id,
    required this.characterId,
    required this.order,
    this.sceneId,
    this.direction,
    this.emotion,
    this.pronunciation,
    this.retired = false,
    Map<String, LineText>? text,
    Json? extra,
  }) : text = text ?? {},
       extra = extra ?? {};

  factory Line.fromJson(Json json) => Line(
    id: json['id'] as String,
    characterId: json['characterId'] as String,
    sceneId: json['sceneId'] as String?,
    order: json['order'] as int? ?? 0,
    direction: json['direction'] as String?,
    emotion: json['emotion'] as String?,
    pronunciation: json['pronunciation'] as String?,
    retired: json['retired'] as bool? ?? false,
    text: {
      for (final entry in (json['text'] as Json? ?? {}).entries)
        entry.key: LineText.fromJson(entry.value as Json),
    },
    extra: unknownFields(json, const {
      'id',
      'characterId',
      'sceneId',
      'order',
      'direction',
      'emotion',
      'pronunciation',
      'retired',
      'text',
    }),
  );

  final String id;
  String characterId;
  String? sceneId;
  int order;
  String? direction;
  String? emotion;
  String? pronunciation;
  bool retired;
  final Map<String, LineText> text;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'characterId': characterId,
    'sceneId': ?sceneId,
    'order': order,
    'direction': ?direction,
    'emotion': ?emotion,
    'pronunciation': ?pronunciation,
    'retired': retired,
    'text': {for (final entry in text.entries) entry.key: entry.value.toJson()},
  };
}

class Character {
  Character({
    required this.id,
    required this.name,
    this.description,
    Json? extra,
  }) : extra = extra ?? {};

  factory Character.fromJson(Json json) => Character(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    extra: unknownFields(json, const {'id', 'name', 'description'}),
  );

  final String id;
  String name;
  String? description;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'description': ?description,
  };
}

class Scene {
  Scene({
    required this.id,
    required this.title,
    required this.order,
    this.context,
    Json? extra,
  }) : extra = extra ?? {};

  factory Scene.fromJson(Json json) => Scene(
    id: json['id'] as String,
    title: json['title'] as String,
    order: json['order'] as int? ?? 0,
    context: json['context'] as String?,
    extra: unknownFields(json, const {'id', 'title', 'order', 'context'}),
  );

  final String id;
  String title;
  int order;
  String? context;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'context': ?context,
    'order': order,
  };
}

class RetakeRequest {
  RetakeRequest({
    required this.id,
    required this.lineId,
    required this.language,
    required this.actorId,
    required this.createdAt,
    this.sourceTakeId,
    this.note,
    Json? extra,
  }) : extra = extra ?? {};

  factory RetakeRequest.fromJson(Json json) => RetakeRequest(
    id: json['id'] as String,
    lineId: json['lineId'] as String,
    language: json['language'] as String,
    actorId: json['actorId'] as String,
    sourceTakeId: json['sourceTakeId'] as String?,
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    extra: unknownFields(json, const {
      'id',
      'lineId',
      'language',
      'actorId',
      'sourceTakeId',
      'note',
      'createdAt',
    }),
  );

  final String id;
  final String lineId;
  final String language;
  final String actorId;
  final String? sourceTakeId;
  final String? note;
  final DateTime createdAt;
  final Json extra;

  Json toJson() => {
    ...extra,
    'id': id,
    'lineId': lineId,
    'language': language,
    'actorId': actorId,
    'sourceTakeId': ?sourceTakeId,
    'note': ?note,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class AudioRequest {
  AudioRequest({this.minSampleRateHz, this.minBitDepth, Json? extra})
    : extra = extra ?? {};

  factory AudioRequest.fromJson(Json json) => AudioRequest(
    minSampleRateHz: json['minSampleRateHz'] as int?,
    minBitDepth: json['minBitDepth'] as int?,
    extra: unknownFields(json, const {'minSampleRateHz', 'minBitDepth'}),
  );

  int? minSampleRateHz;
  int? minBitDepth;
  final Json extra;

  Json toJson() => {
    ...extra,
    'minSampleRateHz': ?minSampleRateHz,
    'minBitDepth': ?minBitDepth,
  };
}

class UsageTerms {
  UsageTerms({required this.version, required this.text, Json? extra})
    : extra = extra ?? {};

  factory UsageTerms.fromJson(Json json) => UsageTerms(
    version: json['version'] as int,
    text: json['text'] as String,
    extra: unknownFields(json, const {'version', 'text'}),
  );

  int version;
  String text;
  final Json extra;

  Json toJson() => {...extra, 'version': version, 'text': text};
}

class Project {
  Project({
    required this.id,
    required this.title,
    required this.sourceLanguage,
    required this.languages,
    this.revision = 0,
    this.description,
    this.audioRequest,
    this.usageTerms,
    List<Character>? characters,
    List<Scene>? scenes,
    List<Line>? lines,
    List<RetakeRequest>? retakeRequests,
    Json? extra,
  }) : characters = characters ?? [],
       scenes = scenes ?? [],
       lines = lines ?? [],
       retakeRequests = retakeRequests ?? [],
       extra = extra ?? {};

  factory Project.fromJson(Json json) => Project(
    id: json['id'] as String,
    title: json['title'] as String,
    revision: json['revision'] as int,
    description: json['description'] as String?,
    sourceLanguage: json['sourceLanguage'] as String,
    languages: [for (final l in json['languages'] as List) l as String],
    audioRequest: json['audioRequest'] == null
        ? null
        : AudioRequest.fromJson(json['audioRequest'] as Json),
    usageTerms: json['usageTerms'] == null
        ? null
        : UsageTerms.fromJson(json['usageTerms'] as Json),
    characters: [
      for (final c in json['characters'] as List? ?? const [])
        Character.fromJson(c as Json),
    ],
    scenes: [
      for (final s in json['scenes'] as List? ?? const [])
        Scene.fromJson(s as Json),
    ],
    lines: [
      for (final l in json['lines'] as List? ?? const [])
        Line.fromJson(l as Json),
    ],
    retakeRequests: [
      for (final r in json['retakeRequests'] as List? ?? const [])
        RetakeRequest.fromJson(r as Json),
    ],
    extra: unknownFields(json, const {
      'id',
      'title',
      'revision',
      'description',
      'sourceLanguage',
      'languages',
      'audioRequest',
      'usageTerms',
      'characters',
      'scenes',
      'lines',
      'retakeRequests',
    }),
  );

  final String id;
  String title;
  int revision;
  String? description;
  String sourceLanguage;
  final List<String> languages;
  AudioRequest? audioRequest;
  UsageTerms? usageTerms;
  final List<Character> characters;
  final List<Scene> scenes;
  final List<Line> lines;
  final List<RetakeRequest> retakeRequests;
  final Json extra;

  Line? lineById(String id) => lines.where((l) => l.id == id).firstOrNull;
  Scene? sceneById(String? id) => scenes.where((s) => s.id == id).firstOrNull;
  Character? characterById(String? id) =>
      characters.where((c) => c.id == id).firstOrNull;

  /// Lines in script order: by scene, then by line order. Lines without a scene
  /// come last. Unknown scene ids are treated as no scene.
  List<Line> orderedLines({bool includeRetired = false}) {
    final sceneOrder = {for (final s in scenes) s.id: s.order};
    const noScene = 1 << 62;
    final indexed = lines.indexed
        .where((e) => includeRetired || !e.$2.retired)
        .toList();
    indexed.sort((a, b) {
      final bySceneOrder = (sceneOrder[a.$2.sceneId] ?? noScene).compareTo(
        sceneOrder[b.$2.sceneId] ?? noScene,
      );
      if (bySceneOrder != 0) return bySceneOrder;
      final bySceneId = (a.$2.sceneId ?? '').compareTo(b.$2.sceneId ?? '');
      if (bySceneId != 0) return bySceneId;
      final byOrder = a.$2.order.compareTo(b.$2.order);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  Json toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'revision': revision,
    'description': ?description,
    'sourceLanguage': sourceLanguage,
    'languages': languages,
    'audioRequest': ?audioRequest?.toJson(),
    'usageTerms': ?usageTerms?.toJson(),
    'characters': [for (final c in characters) c.toJson()],
    'scenes': [for (final s in scenes) s.toJson()],
    'lines': [for (final l in lines) l.toJson()],
    'retakeRequests': [for (final r in retakeRequests) r.toJson()],
  };
}

/// The next sequential id such as `L000123`. Skips every id in use, and retired
/// lines stay in the project, so an id is never reused.
String nextSequentialId(String prefix, Iterable<String> used) {
  final usedSet = used.toSet();
  final pattern = RegExp('^$prefix(\\d+)\$');
  var highest = 0;
  for (final id in usedSet) {
    final match = pattern.firstMatch(id);
    if (match == null) continue;
    final n = int.tryParse(match.group(1)!);
    if (n != null && n > highest) highest = n;
  }
  return '$prefix${(highest + 1).toString().padLeft(6, '0')}';
}

final _languageTag = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$');

/// A light check for BCP 47 tags such as `en` or `zh-Hans`.
bool isValidLanguageTag(String tag) => _languageTag.hasMatch(tag);
