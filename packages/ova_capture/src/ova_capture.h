// Native capture engine for the OpenVoiceActor audio prototype.
//
// One capture session at a time. Samples never pass through Dart: the device
// callback fills a ring buffer and a native writer thread drains it to disk.
// All functions are non-blocking enough to call from the UI isolate, except
// ova_recover_partial and ova_close, which may wait on disk or the device.
#pragma once

#include <stdint.h>

#if _WIN32
#define OVA_EXPORT __declspec(dllexport)
#else
#define OVA_EXPORT __attribute__((visibility("default")))
#endif

#define OVA_MAX_METER_CHANNELS 8

// Values match ma_format so they can be passed straight through.
#define OVA_FORMAT_NATIVE 0
#define OVA_FORMAT_U8 1
#define OVA_FORMAT_S16 2
#define OVA_FORMAT_S24 3
#define OVA_FORMAT_S32 4
#define OVA_FORMAT_F32 5

#define OVA_STATE_CLOSED 0
#define OVA_STATE_ARMED 1
#define OVA_STATE_RECORDING 2
#define OVA_STATE_STOPPING 3

#define OVA_TAKE_NONE 0
#define OVA_TAKE_OK 1
#define OVA_TAKE_DEVICE_LOST 2
#define OVA_TAKE_SIZE_LIMIT 3
#define OVA_TAKE_DISK_ERROR 4

#define OVA_OK 0
#define OVA_ERR_BAD_ARGUMENT -1
#define OVA_ERR_BAD_STATE -2
#define OVA_ERR_DEVICE -3
#define OVA_ERR_FILE -4
#define OVA_ERR_NOT_WAV -5

typedef struct ova_status {
  int32_t state;
  int32_t last_take_result;  // OVA_TAKE_*; set when a take finishes.
  int32_t device_lost;       // The device stopped without being asked to.
  int32_t input_channels;
  // Peak per input channel since the last status read, 0..1 (float can exceed 1).
  float peaks[OVA_MAX_METER_CHANNELS];
  int64_t frames_written;   // Frames in the current or last take.
  int64_t dropped_frames;   // Frames lost because the ring buffer was full.
  int64_t clipped_samples;  // Full-scale samples on stored channels this take.
} ova_status;

typedef struct ova_session_format {
  int32_t format;
  int32_t sample_rate;
  int32_t channels;       // Channels delivered by the device.
  int32_t exclusive;      // 1 if the device opened in exclusive mode.
  int32_t device_format;  // The format WASAPI actually negotiated.
  int32_t device_rate;
  int32_t device_channels;
  int32_t raw_mode;  // 1 if Windows accepted the raw (no effects) request.
} ova_session_format;

// Device listing. ova_devices_refresh returns the device count or an error.
OVA_EXPORT int32_t ova_devices_refresh(void);
// Copies the UTF-8 name, always null terminated. Returns 1 if default device.
OVA_EXPORT int32_t ova_device_name(int32_t index, char* out, int32_t out_size);
OVA_EXPORT int32_t ova_device_format_count(int32_t index);
// Returns 0 and fills the fields, or an error.
OVA_EXPORT int32_t ova_device_format(int32_t index, int32_t format_index,
                                     int32_t* format, int32_t* channels,
                                     int32_t* sample_rate, int32_t* exclusive);

// Opens a device and starts metering without writing anything. Pass 0 for
// format, sample_rate and channels to take what the device natively offers.
OVA_EXPORT int32_t ova_open(int32_t device_index, int32_t exclusive,
                            int32_t format, int32_t sample_rate,
                            int32_t channels);
// Same session, fed by a generated sine (440 Hz plus channel index * 110 Hz)
// instead of a device, so tests run without hardware. speed multiplies real time.
OVA_EXPORT int32_t ova_open_synthetic(int32_t format, int32_t sample_rate,
                                      int32_t channels, int32_t speed);
OVA_EXPORT int32_t ova_session_info(ova_session_format* out);
OVA_EXPORT void ova_close(void);

// Starts a take at "<wav_path>.partial". selected_channel keeps one input as a
// mono file; -1 keeps all inputs. pre_roll_ms of audio already metered is
// included so the first syllable isn't clipped.
OVA_EXPORT int32_t ova_record_start(const char* wav_path_utf8,
                                    int32_t selected_channel,
                                    int32_t pre_roll_ms);
// Finishes the take tail_ms from now and renames it to wav_path. A negative
// tail_ms instead ends it now and removes that much from the end, which is how
// the sound of pressing stop is kept out. Returns at once; poll ova_get_status
// until state is ARMED or CLOSED.
OVA_EXPORT int32_t ova_record_stop(int32_t tail_ms);

OVA_EXPORT void ova_get_status(ova_status* out);

// Test hook: forces the session to behave as if its device disappeared.
OVA_EXPORT void ova_test_lose_device(void);

// Repairs the header of a .partial file left by a crash and renames it to the
// path without the suffix. Returns frames recovered, or an error.
OVA_EXPORT int64_t ova_recover_partial(const char* partial_path_utf8);

#define OVA_PLAY_IDLE 0
#define OVA_PLAY_PLAYING 1
#define OVA_PLAY_FINISHED 2

typedef struct ova_play_state {
  int32_t state;  // OVA_PLAY_*
  int32_t sample_rate;
  int64_t position_frames;
  int64_t total_frames;
} ova_play_state;

// Plays a WAV file on the default output. Replaces whatever is playing. Poll
// ova_play_status, and call ova_play_stop once it reports finished.
OVA_EXPORT int32_t ova_play_start(const char* wav_path_utf8);
OVA_EXPORT void ova_play_stop(void);
OVA_EXPORT void ova_play_status(ova_play_state* out);

// Bytes free on the disk holding an existing folder, or an error.
OVA_EXPORT int64_t ova_free_disk_bytes(const char* path_utf8);
