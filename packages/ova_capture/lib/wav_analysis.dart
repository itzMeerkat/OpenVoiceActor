import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// What a WAV file really contains, measured rather than taken from its header.
class WavReport {
  WavReport({
    required this.formatTag,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.frames,
    required this.peak,
    required this.rmsDb,
    required this.effectiveBits,
    required this.dominantHz,
    required this.maxJump,
  });

  final int formatTag;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int frames;

  /// Largest absolute sample on channel 0, where full scale is 1.0.
  final double peak;
  final double rmsDb;

  /// Bits of real resolution, or null for silence. A padded 16-bit signal in a
  /// 24-bit file measures 16.
  final int? effectiveBits;

  /// Frequency from zero crossings on channel 0. Only meaningful for test tones.
  final double dominantHz;

  /// Largest sample-to-sample change on channel 0. A splice shows up as a spike.
  final double maxJump;

  bool get isFloat => formatTag == 3;
  double get seconds => frames / sampleRate;

  @override
  String toString() =>
      '${isFloat ? 'float' : 'int'} $bitsPerSample-bit, $sampleRate Hz, '
      '$channels ch, ${seconds.toStringAsFixed(2)} s, '
      'peak ${peak.toStringAsFixed(4)}, RMS ${rmsDb.toStringAsFixed(1)} dBFS, '
      'effective bits ${effectiveBits ?? 'n/a (silence)'}';
}

WavReport analyzeWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
    throw FormatException('Not a WAV file: $path');
  }

  int? tag, channels, rate, bits;
  int? dataStart, dataBytes;
  var cursor = 12;
  while (cursor + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, cursor, cursor + 4);
    final size = data.getUint32(cursor + 4, Endian.little);
    if (id == 'fmt ') {
      tag = data.getUint16(cursor + 8, Endian.little);
      channels = data.getUint16(cursor + 10, Endian.little);
      rate = data.getUint32(cursor + 12, Endian.little);
      bits = data.getUint16(cursor + 22, Endian.little);
    } else if (id == 'data') {
      dataStart = cursor + 8;
      dataBytes = min(size, bytes.length - dataStart);
      break;
    }
    cursor += 8 + size + (size & 1);
  }
  if (tag == null || dataStart == null) {
    throw FormatException('WAV file is missing fmt or data: $path');
  }

  final sampleBytes = bits! ~/ 8;
  final frameBytes = sampleBytes * channels!;
  final frames = dataBytes! ~/ frameBytes;

  double read(int frame) {
    final at = dataStart! + frame * frameBytes;
    if (tag == 3) return data.getFloat32(at, Endian.little);
    switch (bits) {
      case 8:
        return (bytes[at] - 128) / 128.0;
      case 16:
        return data.getInt16(at, Endian.little) / 32768.0;
      case 24:
        final raw = bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
        return (raw >= 0x800000 ? raw - 0x1000000 : raw) / 8388608.0;
      default:
        return data.getInt32(at, Endian.little) / 2147483648.0;
    }
  }

  var peak = 0.0, energy = 0.0, maxJump = 0.0, previous = 0.0;
  var crossings = 0;
  var maxBits = 0;
  final storedBits = tag == 3 ? 32 : bits;
  for (var f = 0; f < frames; f++) {
    final v = read(f);
    peak = max(peak, v.abs());
    energy += v * v;
    if (f > 0) {
      maxJump = max(maxJump, (v - previous).abs());
      if (previous < 0 && v >= 0) crossings++;
    }
    previous = v;
    if (v != 0) maxBits = max(maxBits, _bitsNeeded(v, storedBits));
  }

  return WavReport(
    formatTag: tag,
    channels: channels,
    sampleRate: rate!,
    bitsPerSample: bits,
    frames: frames,
    peak: peak,
    rmsDb: frames == 0 || energy == 0
        ? double.negativeInfinity
        : 10 * log(energy / frames) / ln10,
    effectiveBits: maxBits == 0 ? null : maxBits,
    dominantHz: frames == 0 ? 0 : crossings * rate / frames,
    maxJump: maxJump,
  );
}

/// The fewest bits of full-scale resolution that represent [v] exactly.
int _bitsNeeded(double v, int limit) {
  for (var b = 8; b < limit; b++) {
    final scaled = v * pow(2.0, b - 1);
    if (scaled == scaled.roundToDouble()) return b;
  }
  return limit;
}
