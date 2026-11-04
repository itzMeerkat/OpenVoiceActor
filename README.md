# OpenVoiceActor

Voice acting projects for small teams and indie games that work with friends or amateur actors. The initiator defines the lines and sends a file to actors. Actors record takes and send a file back. It runs fully offline, with no server.

**Status:** first version in progress. It runs on Windows only. Phone and tablet layouts exist, but no mobile build or audio engine does yet.

## Run it

```bash
cd app
flutter run -d windows
```

Projects and takes are stored in `%LOCALAPPDATA%\OpenVoiceActor`.

## How the code is laid out

Logic and UI are kept apart, so screens can change freely. The separation is enforced by dependencies: `ova_core` doesn't depend on Flutter, so it can't import UI code.

| Folder | What it holds | Depends on |
|---|---|---|
| [`app/`](app) | Flutter screens only. They render controller state and call controller methods. | `ova_core`, `ova_capture` |
| [`packages/ova_core/`](packages/ova_core) | All logic: data model, file format, CSV import, storage, line status and controllers. | Plain Dart |
| [`packages/ova_capture/`](packages/ova_capture) | The Windows audio engine (miniaudio), implementing the audio interfaces `ova_core` defines. | `ova_core` |
| [`docs/`](docs) | The [format spec](docs/format-spec.md) and the [audio test plan](docs/audio-prototype-plan.md). | |
| [`prototypes/audio_capture/`](prototypes/audio_capture) | A bench for testing audio hardware. | `ova_capture` |

To change how something looks, edit `app/lib/ui`. Colors, spacing and shared widgets live in `app/lib/ui/design`. Each screen has a desktop and a compact layout, chosen by `isCompact` in `design/responsive.dart`. To change what it does, edit a controller in `ova_core` and test it there without opening a window.

Audio and file dialogs sit behind interfaces, so tests use stand-ins, and other platforms can be added behind the same interfaces.

## Run the tests

None of these use your microphone.

| What | From | Command |
|---|---|---|
| Logic | `packages/ova_core` | `dart test` |
| Audio engine, plus the flow with the real engine | `packages/ova_capture` | `dart test` |
| Screens | `app` | `flutter test` |
| The real app, driven through its screens | `app` | `flutter test integration_test -d windows` |
