# OpenVoiceActor Format Specification

**Status:** Draft 0.1 (2026-11-03). Expect breaking changes until 1.0.

This format lets a project initiator send a voice acting project to actors and get their recordings back, with no server. It uses two file types:

| File | Extension | Made by | Contains |
|---|---|---|---|
| Project package | `.ovaproject` | Initiator | Script, characters, context, languages, retake requests |
| Submission package | `.ovasubmission` | Actor | Takes and their metadata |

```
Initiator                                   Actor
  CSV import
  Export .ovaproject  ───────────────────►  Import, record, mark favorites
  Import, compare, pick final takes  ◄────  Export .ovasubmission
  Export updated .ovaproject  ───────────►  See retakes and outdated lines
  Engine export
```

## 1. Core rules

1. **The manifest is the source of truth.** Audio filenames are never parsed for meaning. A renamed package still imports correctly as long as its contents are intact.
2. **Line IDs are permanent.** An ID is never reused or changed.
3. **Nothing is silently lost.** Importing never deletes takes. Removed lines are retired, not deleted.
4. **Audio is stored as captured.** Apps don't resample, normalize, or otherwise alter a take when recording or exporting a submission.

## 2. Packages

Both package types are ZIP files:

- Writers must support ZIP64, because submissions can exceed 4 GB.
- Audio entries should use the STORE method, because WAV compresses poorly and packing takes time.
- All paths are UTF-8, relative, and use `/`.

Every package has a `manifest.json` at its root:

```json
{
  "format": "openvoiceactor",
  "formatVersion": "0.1",
  "kind": "project",
  "createdBy": "OpenVoiceActor 0.1.0",
  "createdAt": "2026-11-03T10:00:00Z"
}
```

`kind` is `project` or `submission`. All timestamps are UTC in RFC 3339 format.

```
example.ovaproject            example.ovasubmission
├── manifest.json             ├── manifest.json
├── project.json              ├── submission.json
└── assets/   (optional)      └── audio/<takeId>.wav
```

## 3. Project file (`project.json`)

```json
{
  "id": "3f1c9a52-6a0e-4c58-9d0b-2f6d3f0b7a11",
  "title": "My Indie Game",
  "revision": 7,
  "description": "A cozy mystery set in a mountain village.",
  "sourceLanguage": "en",
  "languages": ["en", "zh-Hans"],
  "audioRequest": { "minSampleRateHz": 44100, "minBitDepth": 16 },
  "usageTerms": {
    "version": 1,
    "text": "Recordings may be used in My Indie Game and its marketing."
  },
  "characters": [
    {
      "id": "mira",
      "name": "Mira",
      "description": "Village doctor, 40s, dry humor."
    }
  ],
  "scenes": [
    {
      "id": "ch1_clinic",
      "title": "Chapter 1: The clinic",
      "context": "Night. Rain outside. Mira has just found the letter.",
      "order": 10
    }
  ],
  "lines": [
    {
      "id": "ch1_clinic_0010",
      "characterId": "mira",
      "sceneId": "ch1_clinic",
      "order": 10,
      "direction": "Quietly, to herself.",
      "emotion": "uneasy",
      "pronunciation": "Mira = MEE-rah",
      "retired": false,
      "text": {
        "en": { "value": "Who else knows about this?", "version": 2 },
        "zh-Hans": { "value": "还有谁知道这件事?", "version": 1 }
      }
    }
  ],
  "retakeRequests": [
    {
      "id": "a7d0e6f2-11c4-4c3b-8f55-0b6a3e2c9d10",
      "lineId": "ch1_clinic_0010",
      "language": "en",
      "actorId": "5b2e8c14-7d3f-4a91-b6e2-91c0d4f7a233",
      "sourceTakeId": "e2c4a8d6-3b1f-4e70-a9c5-7f1d2b6e8a40",
      "note": "More tired, less suspicious.",
      "createdAt": "2026-11-03T11:00:00Z"
    }
  ]
}
```

| Field | Rules |
|---|---|
| `revision` | Increases by at least 1 each time the initiator exports. |
| `languages` | BCP 47 tags. A line can lack text for some languages. Actors can't record a line in a language it has no text for. |
| `audioRequest` | Optional minimums. Below them the app warns the actor but doesn't block recording. |
| `usageTerms` | Optional. If present, the actor must accept it before exporting. `version` increases when the terms change. |
| `order` | Sort order within a scene. Use gaps so lines can be inserted later. |
| `direction`, `emotion`, `pronunciation` | Optional. Changing them does not make existing takes outdated. |
| `retired` | `true` hides the line from actors and keeps existing takes linked to it. |
| `text.*.version` | See section 5. |

`character.id`, `scene.id` and `line.id` are strings, unique within their type. They may contain any characters, because they're never used as file paths. Apps generate them when the initiator doesn't provide them (see section 8).

Version 0.1 has no character assignment. Actors can record any character, and can filter the script by character in the app.

Files in `assets/`, such as reference audio or images, are reserved for a later version. Readers must ignore them for now.

## 4. Submission file (`submission.json`)

```json
{
  "id": "0c9e7b34-52ad-4f16-8e21-6a3d9f4b1c77",
  "projectId": "3f1c9a52-6a0e-4c58-9d0b-2f6d3f0b7a11",
  "projectRevision": 7,
  "actor": {
    "id": "5b2e8c14-7d3f-4a91-b6e2-91c0d4f7a233",
    "displayName": "Alex",
    "creditName": "Alex Chen"
  },
  "usageTermsAcceptance": {
    "version": 1,
    "acceptedAt": "2026-11-03T12:00:00Z"
  },
  "takes": [
    {
      "id": "e2c4a8d6-3b1f-4e70-a9c5-7f1d2b6e8a40",
      "lineId": "ch1_clinic_0010",
      "language": "en",
      "characterId": "mira",
      "recordedAt": "2026-11-03T11:40:12Z",
      "favorite": true,
      "spokenText": "Who else knows about this?",
      "textVersion": 2,
      "file": "audio/e2c4a8d6-3b1f-4e70-a9c5-7f1d2b6e8a40.wav",
      "sha256": "7ac3...",
      "audio": {
        "container": "wav",
        "sampleFormat": "int",
        "bitDepth": 24,
        "sampleRateHz": 48000,
        "channels": 1,
        "durationMs": 2310
      },
      "capture": {
        "platform": "windows",
        "appVersion": "0.1.0",
        "inputDeviceName": "Scarlett Solo USB",
        "droppedFrames": 0,
        "clippedSamples": 0
      }
    }
  ]
}
```

| Field | Rules |
|---|---|
| `actor.id` | A UUID generated once per app install. |
| `usageTermsAcceptance` | Required if the project has `usageTerms`. `version` is the version of the terms the actor accepted. It records what the actor agreed to, and isn't proof of identity. |
| `spokenText` | The text shown when the take was recorded, so reviewers can see it even if the line changes. |
| `textVersion` | The line's text version when the take was recorded. See section 5. |
| `favorite` | The actor's suggestion. The initiator makes the final choice. |
| `audio` | Describes the actual file and must match its WAV header. `sampleFormat` is `int` or `float`. |
| `capture` | Optional diagnostics. `inputDeviceName` can be left out for privacy, and the app leaves it out unless the actor opts in. `droppedFrames` and `clippedSamples` report problems during recording. |

Exporting favorites only is the default. An actor can choose to include all takes. A submission can cover any part of the script, and later submissions add to earlier ones.

## 5. Text versions and outdated takes

Each line has a separate text `version` per language, an integer that starts at 1 and only increases. **The initiator decides whether a text change needs new recordings:**

- **Needs new recording:** the version increases.
- **Doesn't need new recording,** such as a typo in the displayed text: the text changes and the version stays the same.

A take is **outdated** when its `textVersion` is lower than the current version for that line and language. Outdated takes are kept and stay playable, but are clearly marked. An initiator can still select one.

If a take isn't outdated but its `spokenText` differs from the current text, apps should show the difference to the reviewer, so they can see the wording the actor read.

## 6. Import rules

**Actor importing a project**

| Situation | Result |
|---|---|
| New project `id` | Added as a new project. |
| Same `id`, higher `revision` | Updated. All local takes kept and re-checked for outdated text. |
| Same `id`, same `revision` | No change. |
| Same `id`, lower `revision` | Refused with a warning. |

**Initiator importing a submission**

| Situation | Result |
|---|---|
| `projectId` doesn't match | Refused. |
| Take `id` already imported | Skipped, so re-importing is safe. |
| Checksum or header mismatch | That take is rejected and reported. The others still import. |
| Unknown `lineId` | Kept as unassigned and reported, not discarded. |
| Older `projectRevision` | Accepted. Outdated status comes from each take's `textVersion`. |

**Compatibility**

- A reader must keep unknown JSON fields when rewriting a file.
- A reader must refuse a package with a higher major `formatVersion` than it supports. Before 1.0, a higher minor version is also refused.

**Untrusted input**

Packages may come from strangers, so readers must:

- Reject absolute paths and any path containing `..`.
- Never use `id` values to build file paths without validating them.
- Enforce limits on the JSON size and the number of entries.
- Check available disk space before extracting.
- Validate WAV headers before playback.

## 7. Audio files

Version 0.1 allows uncompressed WAV only, at any sample rate and bit depth the capture hardware provides. See [audio-prototype-plan.md](audio-prototype-plan.md) for how this gets captured.

The file must contain what the app actually captured, including its true rate and bit depth. Apps must not upsample or pad to make a recording look higher quality than it is.

## 8. CSV import

CSV import is an app feature rather than part of the interchange format, but it determines where line IDs come from. Files are UTF-8, with or without a BOM. Only `character` and `text` are required in the script file.

**Script file (one per project, in the source language):**

```csv
id,character,scene,order,text,direction,emotion,pronunciation
ch1_clinic_0010,Mira,ch1_clinic,10,Who else knows about this?,"Quietly, to herself.",uneasy,Mira = MEE-rah
```

**Translation file (one per language, with the language chosen at import):**

```csv
id,text
ch1_clinic_0010,还有谁知道这件事?
```

**Line IDs**

- `id` is optional, and duplicates are an error. If a game already has its own IDs, using them keeps audio mapped to the game without extra work.
- Without an `id`, the app generates a sequential one such as `L000123`. It skips any ID already in use, including retired lines, so an ID is never reused.
- Character and scene IDs are generated in the same way from their names when they first appear.
- The app can export the script and a translation template as CSV, with all IDs filled in. Translation rows require an `id`, so this template is how translators get them.

**Re-importing**

The app always shows a preview of the changes before applying them.

| Row | Matched by | Result |
|---|---|---|
| Has an `id` | `id` | Updates that line, or adds a new line if the ID is unknown. |
| No `id`, same character and text as an existing line | Character and exact text | Treated as that line, unchanged. If several lines match, they're paired in `order`, or file order if `order` is missing. |
| No `id`, no match | Nothing | Adds a new line with a generated ID. |

- An edited row without an `id` can't be recognized as an edit. It shows up as one new line plus one missing line, and its takes stay with the old line. Exporting the CSV with IDs first avoids this.
- For each line whose text changed, the initiator chooses whether it needs new recording (see section 5), with an option to apply one choice to all. "Needs new recording" is preselected, since shipping an old recording by mistake is worse than an extra review.
- Lines missing from a re-import aren't deleted. The app lists them and offers to retire them.
- Translation rows with an unknown `id` are reported and not imported.

## 9. Data outside this format

Each app keeps this locally, and it isn't exchanged:

- **Initiator:** the selected take per line and language, and review notes.
- **Actor:** local takes not yet exported, and app settings.

A line's status is worked out per line and language: `not_recorded`, `submitted`, `outdated`, `retake_requested` or `approved`. The actor's app also has `recorded`, for takes not exported yet. A retake request stays open until that actor records the line again after the request's `createdAt`. An approval lasts until the line's text version goes up.

## 10. Out of scope for 0.1

- Compressed audio such as FLAC
- Reference audio and images
- Audio post-processing
- Engine-specific export formats (the engine export is an app feature)
- Tamper-proof proof of human performance. These records are self-reported.
