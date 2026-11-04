import 'dart:io';
import 'dart:typed_data';

import 'wav_info.dart';

const _framesPerRead = 16384;

/// The loudest sample in each of [buckets] equal slices of a WAV file, from 0 to
/// 1, across all channels. Blocks on disk, so run it in an isolate.
List<double> readWavPeaks(String path, {int buckets = 160}) {
  final info = readWavInfo(path);
  final peaks = Float64List(buckets);
  if (info.frames == 0) return peaks;

  final sampleBytes = info.bytesPerFrame ~/ info.channels;
  final file = File(path).openSync();
  try {
    file.setPositionSync(info.dataOffset);
    var frame = 0;
    while (frame < info.frames) {
      final wanted = (info.frames - frame).clamp(0, _framesPerRead);
      final bytes = file.readSync(wanted * info.bytesPerFrame);
      final data = ByteData.sublistView(bytes);
      final framesRead = bytes.length ~/ info.bytesPerFrame;
      if (framesRead == 0) break;
      for (var f = 0; f < framesRead; f++, frame++) {
        final bucket = frame * buckets ~/ info.frames;
        final start = f * info.bytesPerFrame;
        for (var c = 0; c < info.channels; c++) {
          final level = _sampleLevel(
            data,
            start + c * sampleBytes,
            sampleBytes,
            info.isFloat,
          );
          if (level > peaks[bucket]) peaks[bucket] = level;
        }
      }
    }
  } finally {
    file.closeSync();
  }
  return peaks;
}

double _sampleLevel(ByteData data, int at, int bytes, bool isFloat) {
  if (isFloat) {
    return bytes == 8
        ? data.getFloat64(at, Endian.little).abs().clamp(0, 1).toDouble()
        : data.getFloat32(at, Endian.little).abs().clamp(0, 1).toDouble();
  }
  return switch (bytes) {
    1 => (data.getUint8(at) - 128).abs() / 128,
    2 => data.getInt16(at, Endian.little).abs() / 32768,
    3 =>
      ((data.getInt8(at + 2) << 16) |
                  (data.getUint8(at + 1) << 8) |
                  data.getUint8(at))
              .abs() /
          8388608,
    4 => data.getInt32(at, Endian.little).abs() / 2147483648,
    _ => 0,
  };
}
