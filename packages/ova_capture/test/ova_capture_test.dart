import 'dart:io';

import 'package:ova_capture/ova_capture.dart';
import 'package:test/test.dart';

Future<void> runFor(Duration d) => Future<void>.delayed(d);

Future<void> waitForFrames(int frames) async {
  while (Capture.status().framesWritten < frames) {
    await runFor(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ova_capture_test'));
  tearDown(() {
    Capture.close();
    dir.deleteSync(recursive: true);
  });

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  group('WAV format', () {
    for (final (format, bits) in [
      (SampleFormat.s16, 16),
      (SampleFormat.s24, 24),
      (SampleFormat.s32, 32),
      (SampleFormat.f32, 32),
    ]) {
      for (final rate in [44100, 48000, 96000, 192000]) {
        test('${format.label} at $rate Hz', () async {
          Capture.openSynthetic(
            format: format,
            sampleRate: rate,
            channels: 1,
            speed: 10,
          );
          final path = pathOf('take.wav');
          Capture.startTake(path, preRollMs: 0);
          await waitForFrames(rate);
          final end = await Capture.stopTake(tailMs: 0);
          expect(end.lastTakeResult, TakeResult.ok);

          final wav = analyzeWav(path);
          expect(wav.bitsPerSample, bits);
          expect(wav.sampleRate, rate);
          expect(wav.channels, 1);
          expect(wav.isFloat, format == SampleFormat.f32);
          expect(wav.frames, end.framesWritten);
          expect(wav.peak, closeTo(0.5, 0.01));
          expect(wav.dominantHz, closeTo(440, 5));
          // Real resolution, not padding, for the integer formats.
          if (format != SampleFormat.f32) {
            expect(wav.effectiveBits, bits);
          }
          expect(File('$path.partial').existsSync(), isFalse);
        });
      }
    }
  });

  group('channels', () {
    test('selecting a channel gives clean mono of that channel', () async {
      Capture.openSynthetic(
        format: SampleFormat.s24,
        sampleRate: 48000,
        channels: 2,
        speed: 10,
      );
      for (final (channel, hz) in [(0, 440.0), (1, 550.0)]) {
        final path = pathOf('channel$channel.wav');
        Capture.startTake(path, selectedChannel: channel, preRollMs: 0);
        await waitForFrames(48000);
        await Capture.stopTake(tailMs: 0);
        final wav = analyzeWav(path);
        expect(wav.channels, 1);
        expect(wav.peak, closeTo(0.5, 0.01));
        expect(wav.dominantHz, closeTo(hz, 5));
      }
    });

    test('keeping all channels stores them interleaved', () async {
      Capture.openSynthetic(
        format: SampleFormat.s16,
        sampleRate: 48000,
        channels: 2,
        speed: 10,
      );
      final path = pathOf('stereo.wav');
      Capture.startTake(path, preRollMs: 0);
      await waitForFrames(48000);
      await Capture.stopTake(tailMs: 0);
      expect(analyzeWav(path).channels, 2);
    });

    test('an out-of-range channel is refused', () {
      Capture.openSynthetic(
        format: SampleFormat.s16,
        sampleRate: 48000,
        channels: 2,
      );
      expect(
        () => Capture.startTake(pathOf('x.wav'), selectedChannel: 2),
        throwsA(isA<CaptureException>()),
      );
    });
  });

  group('take boundaries', () {
    test('pre-roll joins the live audio with no splice', () async {
      Capture.openSynthetic(
        format: SampleFormat.f32,
        sampleRate: 48000,
        channels: 1,
      );
      await runFor(const Duration(milliseconds: 500));
      final path = pathOf('preroll.wav');
      Capture.startTake(path, preRollMs: 250);
      await waitForFrames(24000);
      await Capture.stopTake(tailMs: 100);
      final wav = analyzeWav(path);
      expect(wav.frames, greaterThanOrEqualTo(24000 + 4800));
      // A 440 Hz sine at 0.5 moves at most about 0.029 per sample at 48 kHz.
      expect(wav.maxJump, lessThan(0.03));
    });

    test('tail keeps recording after the stop request', () async {
      Capture.openSynthetic(
        format: SampleFormat.s16,
        sampleRate: 48000,
        channels: 1,
      );
      final path = pathOf('tail.wav');
      Capture.startTake(path, preRollMs: 0);
      await waitForFrames(4800);
      final before = Capture.status().framesWritten;
      final end = await Capture.stopTake(tailMs: 200);
      expect(end.framesWritten, greaterThanOrEqualTo(before + 9600));
    });

    test('a negative tail removes audio from the end', () async {
      Capture.openSynthetic(
        format: SampleFormat.s24,
        sampleRate: 48000,
        channels: 2,
      );
      final path = pathOf('trim.wav');
      Capture.startTake(path, selectedChannel: 1, preRollMs: 0);
      await waitForFrames(24000);
      final before = Capture.status().framesWritten;
      final end = await Capture.stopTake(tailMs: -200);
      expect(end.lastTakeResult, TakeResult.ok);
      // Nothing written after the stop can be more than a few blocks' worth.
      expect(end.framesWritten, lessThanOrEqualTo(before - 9600 + 4096 * 3));
      expect(end.framesWritten, greaterThanOrEqualTo(before - 9600));
      final wav = analyzeWav(path);
      expect(wav.frames, end.framesWritten);
      expect(File(path).lengthSync(), 44 + end.framesWritten * 3);
    });

    test('a take shorter than the trim ends up empty but valid', () async {
      Capture.openSynthetic(
        format: SampleFormat.s16,
        sampleRate: 48000,
        channels: 1,
      );
      final path = pathOf('short.wav');
      Capture.startTake(path, preRollMs: 0);
      await waitForFrames(480);
      final end = await Capture.stopTake(tailMs: -1000);
      expect(end.lastTakeResult, TakeResult.ok);
      expect(end.framesWritten, 0);
      expect(File(path).lengthSync(), 44);
    });
  });

  test('200 takes in a row all finish correctly', () async {
    Capture.openSynthetic(
      format: SampleFormat.s24,
      sampleRate: 48000,
      channels: 1,
      speed: 10,
    );
    for (var i = 0; i < 200; i++) {
      final path = pathOf('take_$i.wav');
      Capture.startTake(path, preRollMs: 10);
      await waitForFrames(2400);
      final end = await Capture.stopTake(tailMs: 5);
      expect(end.lastTakeResult, TakeResult.ok, reason: 'take $i');
      expect(analyzeWav(path).frames, end.framesWritten, reason: 'take $i');
    }
    expect(Capture.status().droppedFrames, 0);
  });

  test('a long take has no dropped frames or splices', () async {
    Capture.openSynthetic(
      format: SampleFormat.s24,
      sampleRate: 48000,
      channels: 1,
      speed: 100,
    );
    final path = pathOf('long.wav');
    Capture.startTake(path, preRollMs: 0);
    await waitForFrames(48000 * 600);
    final end = await Capture.stopTake(tailMs: 0);
    expect(end.droppedFrames, 0);
    final wav = analyzeWav(path);
    expect(wav.seconds, greaterThanOrEqualTo(600));
    expect(wav.maxJump, lessThan(0.03));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('non-ASCII paths work', () async {
    Capture.openSynthetic(
      format: SampleFormat.s16,
      sampleRate: 48000,
      channels: 1,
      speed: 10,
    );
    final path = pathOf('台词 ñ テスト.wav');
    Capture.startTake(path, preRollMs: 0);
    await waitForFrames(4800);
    final end = await Capture.stopTake(tailMs: 0);
    expect(end.lastTakeResult, TakeResult.ok);
    expect(File(path).existsSync(), isTrue);
  });

  test('losing the device saves what was recorded', () async {
    Capture.openSynthetic(
      format: SampleFormat.s24,
      sampleRate: 48000,
      channels: 1,
    );
    final path = pathOf('lost.wav');
    Capture.startTake(path, preRollMs: 0);
    await waitForFrames(4800);
    Capture.close();
    expect(Capture.status().lastTakeResult, TakeResult.deviceLost);
    expect(analyzeWav(path).frames, greaterThanOrEqualTo(4800));
  });

  test(
    'the device disappearing mid-take ends the take and blocks new ones',
    () async {
      Capture.openSynthetic(
        format: SampleFormat.s24,
        sampleRate: 48000,
        channels: 1,
      );
      final path = pathOf('unplugged.wav');
      Capture.startTake(path, preRollMs: 0);
      await waitForFrames(4800);
      Capture.testLoseDevice();
      final end = await Capture.waitForTakeEnd();
      expect(end.lastTakeResult, TakeResult.deviceLost);
      expect(end.deviceLost, isTrue);
      expect(analyzeWav(path).frames, greaterThanOrEqualTo(4800));
      expect(
        () => Capture.startTake(pathOf('next.wav')),
        throwsA(isA<CaptureException>()),
      );
    },
  );

  group('recovery', () {
    for (final format in [SampleFormat.s24, SampleFormat.f32]) {
      test('rebuilds a ${format.label} partial file with a torn frame', () {
        // Build the file by hand: a zero-length header plus 1.5 frames of data
        // past a whole number of frames, as a crash would leave it.
        final isFloat = format == SampleFormat.f32;
        final sampleBytes = isFloat ? 4 : 3;
        final header = _placeholderHeader(isFloat, sampleBytes, 48000);
        final path = pathOf('crashed.wav');
        File('$path.partial').writeAsBytesSync([
          ...header,
          ...List.filled(sampleBytes * 1000 + 1, 0),
        ]);
        expect(Capture.recoverPartial('$path.partial'), 1000);
        expect(File('$path.partial').existsSync(), isFalse);
        final wav = analyzeWav(path);
        expect(wav.frames, 1000);
        expect(wav.bitsPerSample, sampleBytes * 8);
      });
    }

    test('rejects a file that is not a WAV', () {
      final path = pathOf('junk.wav.partial');
      File(path).writeAsBytesSync(List.filled(100, 7));
      expect(
        () => Capture.recoverPartial(path),
        throwsA(isA<CaptureException>()),
      );
    });
  });
}

List<int> _placeholderHeader(bool isFloat, int sampleBytes, int rate) {
  List<int> u32(int v) => [v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255];
  List<int> u16(int v) => [v & 255, v >> 8 & 255];
  return [
    ...'RIFF'.codeUnits,
    ...u32(isFloat ? 50 : 36),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ...u32(isFloat ? 18 : 16),
    ...u16(isFloat ? 3 : 1),
    ...u16(1),
    ...u32(rate),
    ...u32(rate * sampleBytes),
    ...u16(sampleBytes),
    ...u16(sampleBytes * 8),
    if (isFloat) ...[...u16(0), ...'fact'.codeUnits, ...u32(4), ...u32(0)],
    ...'data'.codeUnits,
    ...u32(0),
  ];
}
