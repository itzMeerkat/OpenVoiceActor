import 'dart:io';
import 'dart:typed_data';

import '../model/submission.dart';

const _formatPcm = 1;
const _formatFloat = 3;
const _formatExtensible = 0xFFFE;
const _maxChunks = 64;

/// What a WAV file's header says, checked against the size of the file.
class WavInfo {
  const WavInfo({
    required this.isFloat,
    required this.bitDepth,
    required this.sampleRateHz,
    required this.channels,
    required this.frames,
    required this.dataOffset,
    required this.bytesPerFrame,
  });

  final bool isFloat;
  final int bitDepth;
  final int sampleRateHz;
  final int channels;
  final int frames;

  /// Where the samples start in the file.
  final int dataOffset;
  final int bytesPerFrame;

  int get durationMs => frames * 1000 ~/ sampleRateHz;

  TakeAudio toTakeAudio() => TakeAudio(
    sampleFormat: isFloat ? 'float' : 'int',
    bitDepth: bitDepth,
    sampleRateHz: sampleRateHz,
    channels: channels,
    durationMs: durationMs,
  );

  /// True if a take's metadata describes this file, as spec section 4 requires.
  bool matches(TakeAudio audio) =>
      audio.container == 'wav' &&
      audio.sampleFormat == (isFloat ? 'float' : 'int') &&
      audio.bitDepth == bitDepth &&
      audio.sampleRateHz == sampleRateHz &&
      audio.channels == channels &&
      (audio.durationMs - durationMs).abs() <= 1;
}

/// Reads and validates a WAV header. Throws [FormatException] for anything
/// that isn't a sound uncompressed WAV file.
WavInfo readWavInfo(String path) {
  final file = File(path).openSync();
  try {
    final fileSize = file.lengthSync();
    final riff = file.readSync(12);
    if (riff.length < 12 ||
        String.fromCharCodes(riff, 0, 4) != 'RIFF' ||
        String.fromCharCodes(riff, 8, 12) != 'WAVE') {
      throw const FormatException('Not a WAV file');
    }

    int? tag, channels, rate, bits, blockAlign;
    var position = 12;
    for (var i = 0; i < _maxChunks; i++) {
      file.setPositionSync(position);
      final head = file.readSync(8);
      if (head.length < 8) break;
      final id = String.fromCharCodes(head, 0, 4);
      final size = ByteData.sublistView(head).getUint32(4, Endian.little);
      final body = position + 8;

      if (id == 'fmt ') {
        if (size < 16) throw const FormatException('Bad WAV format chunk');
        final fmt = ByteData.sublistView(file.readSync(size < 40 ? size : 40));
        if (fmt.lengthInBytes < 16) {
          throw const FormatException('Bad WAV format chunk');
        }
        tag = fmt.getUint16(0, Endian.little);
        channels = fmt.getUint16(2, Endian.little);
        rate = fmt.getUint32(4, Endian.little);
        blockAlign = fmt.getUint16(12, Endian.little);
        bits = fmt.getUint16(14, Endian.little);
        if (tag == _formatExtensible) {
          if (fmt.lengthInBytes < 26) {
            throw const FormatException('Bad extensible WAV format chunk');
          }
          tag = fmt.getUint16(24, Endian.little);
        }
      } else if (id == 'data') {
        if (tag == null) throw const FormatException('WAV has no format chunk');
        if (tag != _formatPcm && tag != _formatFloat) {
          throw const FormatException('WAV is not uncompressed');
        }
        if (channels! < 1 || rate! < 1 || bits! < 8 || blockAlign! < 1) {
          throw const FormatException('Bad WAV format values');
        }
        if (body + size > fileSize) {
          throw const FormatException('WAV is shorter than its header says');
        }
        return WavInfo(
          isFloat: tag == _formatFloat,
          bitDepth: bits,
          sampleRateHz: rate,
          channels: channels,
          frames: size ~/ blockAlign,
          dataOffset: body,
          bytesPerFrame: blockAlign,
        );
      }
      position = body + size + (size & 1);
    }
    throw const FormatException('WAV has no audio data');
  } finally {
    file.closeSync();
  }
}
