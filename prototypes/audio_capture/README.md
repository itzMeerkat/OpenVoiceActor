# Audio Capture Prototype

Windows test bench for [the audio prototype plan](../../docs/audio-prototype-plan.md). Results are recorded in that plan.

- [`packages/ova_capture`](../../packages/ova_capture): the capture engine (C, using miniaudio through FFI), its Dart interface and tests. It moved there when the real app started, and is shared with it.
- `lib/main.dart`: a Flutter test bench for manual checks.

## Run the test bench

```bash
flutter run -d windows
```

Takes are saved to `Documents\OpenVoiceActorPrototype`.

## Run the tests

From the repo's `packages/ova_capture`. None of these touch the microphone.

```bash
dart test
```

The ZIP64 test also writes 10 GB of temporary files:

```bash
dart test --run-skipped
```

## Command-line checks

From the repo's `packages/ova_capture`:

```bash
dart run bin/capture_cli.dart devices
```

```bash
dart run bin/capture_cli.dart record take.wav 5 --exclusive
```

```bash
dart run bin/capture_cli.dart analyze take.wav
```

## Compare with the `record` package

Records from the default mic and writes `baseline_report.txt` to the given folder:

```bash
build/windows/x64/runner/Debug/audio_capture_proto.exe --baseline-test=C:/some/folder
```
