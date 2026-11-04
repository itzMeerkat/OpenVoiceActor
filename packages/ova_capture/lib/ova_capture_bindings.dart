// Hand-written bindings for src/ova_capture.h. Keep the two in sync.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

const ovaMaxMeterChannels = 8;

final class OvaStatusNative extends ffi.Struct {
  @ffi.Int32()
  external int state;
  @ffi.Int32()
  external int lastTakeResult;
  @ffi.Int32()
  external int deviceLost;
  @ffi.Int32()
  external int inputChannels;
  @ffi.Array(ovaMaxMeterChannels)
  external ffi.Array<ffi.Float> peaks;
  @ffi.Int64()
  external int framesWritten;
  @ffi.Int64()
  external int droppedFrames;
  @ffi.Int64()
  external int clippedSamples;
}

final class OvaSessionFormatNative extends ffi.Struct {
  @ffi.Int32()
  external int format;
  @ffi.Int32()
  external int sampleRate;
  @ffi.Int32()
  external int channels;
  @ffi.Int32()
  external int exclusive;
  @ffi.Int32()
  external int deviceFormat;
  @ffi.Int32()
  external int deviceRate;
  @ffi.Int32()
  external int deviceChannels;
  @ffi.Int32()
  external int rawMode;
}

@ffi.Native<ffi.Int32 Function()>()
external int ova_devices_refresh();

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32)>()
external int ova_device_name(int index, ffi.Pointer<Utf8> out, int outSize);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int ova_device_format_count(int index);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Int32,
    ffi.Int32,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
  )
>()
external int ova_device_format(
  int index,
  int formatIndex,
  ffi.Pointer<ffi.Int32> format,
  ffi.Pointer<ffi.Int32> channels,
  ffi.Pointer<ffi.Int32> sampleRate,
  ffi.Pointer<ffi.Int32> exclusive,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)
>()
external int ova_open(
  int deviceIndex,
  int exclusive,
  int format,
  int sampleRate,
  int channels,
);

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>()
external int ova_open_synthetic(
  int format,
  int sampleRate,
  int channels,
  int speed,
);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<OvaSessionFormatNative>)>()
external int ova_session_info(ffi.Pointer<OvaSessionFormatNative> out);

@ffi.Native<ffi.Void Function()>()
external void ova_close();

@ffi.Native<ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Int32)>()
external int ova_record_start(
  ffi.Pointer<Utf8> path,
  int selectedChannel,
  int preRollMs,
);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int ova_record_stop(int tailMs);

@ffi.Native<ffi.Void Function(ffi.Pointer<OvaStatusNative>)>()
external void ova_get_status(ffi.Pointer<OvaStatusNative> out);

@ffi.Native<ffi.Void Function()>()
external void ova_test_lose_device();

@ffi.Native<ffi.Int64 Function(ffi.Pointer<Utf8>)>()
external int ova_recover_partial(ffi.Pointer<Utf8> path);

final class OvaPlayStateNative extends ffi.Struct {
  @ffi.Int32()
  external int state;
  @ffi.Int32()
  external int sampleRate;
  @ffi.Int64()
  external int positionFrames;
  @ffi.Int64()
  external int totalFrames;
}

@ffi.Native<ffi.Int32 Function(ffi.Pointer<Utf8>)>()
external int ova_play_start(ffi.Pointer<Utf8> path);

@ffi.Native<ffi.Void Function()>()
external void ova_play_stop();

@ffi.Native<ffi.Void Function(ffi.Pointer<OvaPlayStateNative>)>()
external void ova_play_status(ffi.Pointer<OvaPlayStateNative> out);

@ffi.Native<ffi.Int64 Function(ffi.Pointer<Utf8>)>()
external int ova_free_disk_bytes(ffi.Pointer<Utf8> path);
