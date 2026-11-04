#include "ova_capture.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include <windows.h>

// Set by the local patch in miniaudio.h. See third_party/miniaudio/PATCHES.md.
static int g_ova_raw_capture_applied = 0;

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_MP3
#define MA_NO_FLAC
#define MA_NO_ENCODING
#define MA_NO_ENGINE
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_WASAPI
#include "../third_party/miniaudio/miniaudio.h"

#include <math.h>

#define OVA_RING_SECONDS 4
#define OVA_MAX_PRE_ROLL_MS 1000
#define OVA_WRITER_BLOCK_FRAMES 4096
#define OVA_FLUSH_INTERVAL_MS 2000
#define OVA_DEVICE_PERIOD_MS 20
#define OVA_DEVICE_PERIODS 4
// RIFF sizes are 32-bit. Stop a take before the header would overflow.
#define OVA_MAX_DATA_BYTES 0xFFF00000ull

#define WAV_TAG_PCM 1
#define WAV_TAG_FLOAT 3
#define WAV_HEADER_INT_BYTES 44
#define WAV_HEADER_FLOAT_BYTES 58

typedef enum {
  CMD_NONE = 0,
  CMD_START,
  CMD_STOP,
} writer_cmd;

typedef struct {
  ma_format format;
  ma_uint32 rate;
  ma_uint32 channels;  // Channels stored in the file.
  ma_uint32 bytes_per_sample;
} wav_format;

typedef struct {
  ma_bool32 open;
  ma_bool32 is_synthetic;

  ma_device device;
  ma_pcm_rb ring;
  ma_format format;
  ma_uint32 rate;
  ma_uint32 channels;
  ma_uint32 bytes_per_sample;
  ma_uint32 bytes_per_frame;

  HANDLE writer_thread;
  HANDLE synth_thread;
  volatile LONG quit;
  volatile LONG synth_speed;
  volatile LONG device_lost;
  volatile LONG expected_device_stop;

  // Rolling copy of the most recent audio, written at the start of a take.
  ma_uint8* pre_roll;
  ma_uint64 pre_roll_capacity_frames;
  ma_uint64 pre_roll_write_frame;  // Monotonic total, wraps by modulo.

  // Commands from the caller to the writer.
  writer_cmd cmd;
  HANDLE cmd_file;
  WCHAR cmd_final_path[MAX_PATH * 2];
  WCHAR cmd_partial_path[MAX_PATH * 2];
  ma_int32 cmd_selected_channel;
  ma_uint32 cmd_pre_roll_frames;
  ma_uint64 cmd_tail_frames;
  ma_uint64 cmd_trim_frames;

  // Writer-owned take state.
  HANDLE file;
  WCHAR final_path[MAX_PATH * 2];
  WCHAR partial_path[MAX_PATH * 2];
  ma_int32 selected_channel;
  ma_uint64 tail_remaining;
  ma_bool32 tail_active;
  ma_uint64 trim_frames;
  ma_uint64 data_bytes;
  DWORD last_flush_ms;
  ma_uint8* convert_buffer;

  // Published under lock.
  LONG state;
  LONG last_take_result;
  ma_int64 frames_written;
  ma_int64 clipped_samples;
  float peaks[OVA_MAX_METER_CHANNELS];

  volatile LONG64 dropped_frames;
} session;

static ma_context g_context;
static ma_bool32 g_context_ready = MA_FALSE;
static ma_device_info* g_devices = NULL;
static ma_uint32 g_device_count = 0;
static session g_session;
static CRITICAL_SECTION g_lock;
static LONG g_lock_ready = 0;

static ma_uint32 bytes_per_sample(ma_format format) {
  return ma_get_bytes_per_sample(format);
}

static ma_bool32 utf8_to_wide(const char* in, WCHAR* out, int out_chars) {
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, in, -1, out,
                             out_chars) > 0;
}

static ma_result ensure_context(void) {
  if (g_context_ready) return MA_SUCCESS;
  ma_backend backends[] = {ma_backend_wasapi};
  ma_result result = ma_context_init(backends, 1, NULL, &g_context);
  if (result == MA_SUCCESS) g_context_ready = MA_TRUE;
  return result;
}

int32_t ova_devices_refresh(void) {
  if (ensure_context() != MA_SUCCESS) return OVA_ERR_DEVICE;
  ma_uint32 count = 0;
  ma_device_info* infos = NULL;
  if (ma_context_get_devices(&g_context, NULL, NULL, &infos, &count) !=
      MA_SUCCESS) {
    return OVA_ERR_DEVICE;
  }
  g_devices = infos;
  g_device_count = count;
  return (int32_t)count;
}

static ma_bool32 valid_device(int32_t index) {
  return g_devices != NULL && index >= 0 && (ma_uint32)index < g_device_count;
}

int32_t ova_device_name(int32_t index, char* out, int32_t out_size) {
  if (!valid_device(index) || out == NULL || out_size <= 0) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  strncpy_s(out, (size_t)out_size, g_devices[index].name, _TRUNCATE);
  return g_devices[index].isDefault ? 1 : 0;
}

static ma_result device_detail(int32_t index, ma_device_info* out) {
  return ma_context_get_device_info(&g_context, ma_device_type_capture,
                                    &g_devices[index].id, out);
}

int32_t ova_device_format_count(int32_t index) {
  if (!valid_device(index)) return OVA_ERR_BAD_ARGUMENT;
  ma_device_info info;
  if (device_detail(index, &info) != MA_SUCCESS) return OVA_ERR_DEVICE;
  return (int32_t)info.nativeDataFormatCount;
}

int32_t ova_device_format(int32_t index, int32_t format_index, int32_t* format,
                          int32_t* channels, int32_t* sample_rate,
                          int32_t* exclusive) {
  if (!valid_device(index)) return OVA_ERR_BAD_ARGUMENT;
  ma_device_info info;
  if (device_detail(index, &info) != MA_SUCCESS) return OVA_ERR_DEVICE;
  if (format_index < 0 || (ma_uint32)format_index >= info.nativeDataFormatCount) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  *format = (int32_t)info.nativeDataFormats[format_index].format;
  *channels = (int32_t)info.nativeDataFormats[format_index].channels;
  *sample_rate = (int32_t)info.nativeDataFormats[format_index].sampleRate;
  *exclusive =
      (info.nativeDataFormats[format_index].flags &
       MA_DATA_FORMAT_FLAG_EXCLUSIVE_MODE) != 0;
  return OVA_OK;
}

// Pushes interleaved frames into the ring. Runs on the audio thread, so it only
// copies and counts: no allocation, locks or file access.
static void ring_push(session* s, const void* frames, ma_uint32 count) {
  const ma_uint8* src = (const ma_uint8*)frames;
  ma_uint32 remaining = count;
  while (remaining > 0) {
    ma_uint32 chunk = remaining;
    void* dst = NULL;
    if (ma_pcm_rb_acquire_write(&s->ring, &chunk, &dst) != MA_SUCCESS ||
        chunk == 0) {
      break;
    }
    memcpy(dst, src, (size_t)chunk * s->bytes_per_frame);
    ma_pcm_rb_commit_write(&s->ring, chunk);
    src += (size_t)chunk * s->bytes_per_frame;
    remaining -= chunk;
  }
  if (remaining > 0) InterlockedAdd64(&s->dropped_frames, remaining);
}

static void data_callback(ma_device* device, void* output, const void* input,
                          ma_uint32 frame_count) {
  (void)output;
  ring_push((session*)device->pUserData, input, frame_count);
}

static void notification_callback(const ma_device_notification* notification) {
  session* s = (session*)notification->pDevice->pUserData;
  switch (notification->type) {
    case ma_device_notification_type_stopped:
      if (!s->expected_device_stop) InterlockedExchange(&s->device_lost, 1);
      break;
    case ma_device_notification_type_rerouted:
    case ma_device_notification_type_interruption_began:
      InterlockedExchange(&s->device_lost, 1);
      break;
    default:
      break;
  }
}

static void put_u16(ma_uint8* p, ma_uint16 v) {
  p[0] = (ma_uint8)v;
  p[1] = (ma_uint8)(v >> 8);
}

static void put_u32(ma_uint8* p, ma_uint32 v) {
  p[0] = (ma_uint8)v;
  p[1] = (ma_uint8)(v >> 8);
  p[2] = (ma_uint8)(v >> 16);
  p[3] = (ma_uint8)(v >> 24);
}

static ma_uint32 get_u32(const ma_uint8* p) {
  return (ma_uint32)p[0] | ((ma_uint32)p[1] << 8) | ((ma_uint32)p[2] << 16) |
         ((ma_uint32)p[3] << 24);
}

static ma_uint16 get_u16(const ma_uint8* p) {
  return (ma_uint16)(p[0] | (p[1] << 8));
}

// Int data uses the classic 44-byte layout; float adds cbSize and a fact chunk,
// as the WAV spec requires for non-PCM data.
static DWORD build_wav_header(ma_uint8* h, const wav_format* wav,
                              ma_uint32 data_bytes) {
  const ma_bool32 is_float = wav->format == ma_format_f32;
  const DWORD header_bytes =
      is_float ? WAV_HEADER_FLOAT_BYTES : WAV_HEADER_INT_BYTES;
  const ma_uint32 block_align = wav->channels * wav->bytes_per_sample;
  ma_uint8* p = h;

  memcpy(p, "RIFF", 4);
  put_u32(p + 4, header_bytes - 8 + data_bytes);
  memcpy(p + 8, "WAVE", 4);
  p += 12;

  memcpy(p, "fmt ", 4);
  put_u32(p + 4, is_float ? 18 : 16);
  put_u16(p + 8, is_float ? WAV_TAG_FLOAT : WAV_TAG_PCM);
  put_u16(p + 10, (ma_uint16)wav->channels);
  put_u32(p + 12, wav->rate);
  put_u32(p + 16, wav->rate * block_align);
  put_u16(p + 20, (ma_uint16)block_align);
  put_u16(p + 22, (ma_uint16)(wav->bytes_per_sample * 8));
  p += 24;

  if (is_float) {
    put_u16(p, 0);
    p += 2;
    memcpy(p, "fact", 4);
    put_u32(p + 4, 4);
    put_u32(p + 8, data_bytes / block_align);
    p += 12;
  }

  memcpy(p, "data", 4);
  put_u32(p + 4, data_bytes);
  return header_bytes;
}

static ma_bool32 write_all(HANDLE file, const void* data, DWORD size) {
  DWORD written = 0;
  return WriteFile(file, data, size, &written, NULL) && written == size;
}

static wav_format take_format(const session* s) {
  wav_format wav;
  wav.format = s->format;
  wav.rate = s->rate;
  wav.channels = s->selected_channel >= 0 ? 1 : s->channels;
  wav.bytes_per_sample = s->bytes_per_sample;
  return wav;
}

// Absolute value relative to full scale, without converting the stored samples.
static float sample_level(const ma_uint8* p, ma_format format, ma_bool32* clip) {
  float level = 0.0f;
  switch (format) {
    case ma_format_u8: {
      int v = (int)p[0] - 128;
      *clip = v == 127 || v == -128;
      level = (float)abs(v) / 128.0f;
      break;
    }
    case ma_format_s16: {
      ma_int16 v = (ma_int16)get_u16(p);
      *clip = v == 32767 || v == -32768;
      level = (float)fabs((double)v) / 32768.0f;
      break;
    }
    case ma_format_s24: {
      ma_int32 v = (ma_int32)(((ma_uint32)p[0] << 8) | ((ma_uint32)p[1] << 16) |
                              ((ma_uint32)p[2] << 24)) >>
                   8;
      *clip = v == 8388607 || v == -8388608;
      level = (float)(fabs((double)v) / 8388608.0);
      break;
    }
    case ma_format_s32: {
      ma_int32 v = (ma_int32)get_u32(p);
      *clip = v == 2147483647 || v == (-2147483647 - 1);
      level = (float)(fabs((double)v) / 2147483648.0);
      break;
    }
    case ma_format_f32: {
      float v;
      memcpy(&v, p, sizeof(v));
      level = (float)fabs((double)v);
      *clip = level >= 1.0f;
      break;
    }
    default:
      *clip = MA_FALSE;
      break;
  }
  return level;
}

static void meter_frames(session* s, const ma_uint8* frames, ma_uint32 count,
                         ma_bool32 count_clips) {
  float peaks[OVA_MAX_METER_CHANNELS] = {0};
  ma_int64 clips = 0;
  const ma_uint32 meter_channels =
      s->channels < OVA_MAX_METER_CHANNELS ? s->channels : OVA_MAX_METER_CHANNELS;
  for (ma_uint32 f = 0; f < count; f++) {
    const ma_uint8* frame = frames + (size_t)f * s->bytes_per_frame;
    for (ma_uint32 c = 0; c < s->channels; c++) {
      ma_bool32 clip = MA_FALSE;
      float level = sample_level(frame + (size_t)c * s->bytes_per_sample,
                                 s->format, &clip);
      if (c < meter_channels && level > peaks[c]) peaks[c] = level;
      if (clip && count_clips &&
          (s->selected_channel < 0 || (ma_int32)c == s->selected_channel)) {
        clips++;
      }
    }
  }
  EnterCriticalSection(&g_lock);
  for (ma_uint32 c = 0; c < meter_channels; c++) {
    if (peaks[c] > s->peaks[c]) s->peaks[c] = peaks[c];
  }
  s->clipped_samples += clips;
  LeaveCriticalSection(&g_lock);
}

static void pre_roll_store(session* s, const ma_uint8* frames, ma_uint32 count) {
  if (s->pre_roll_capacity_frames == 0) return;
  for (ma_uint32 f = 0; f < count; f++) {
    const ma_uint64 slot = s->pre_roll_write_frame % s->pre_roll_capacity_frames;
    memcpy(s->pre_roll + slot * s->bytes_per_frame,
           frames + (size_t)f * s->bytes_per_frame, s->bytes_per_frame);
    s->pre_roll_write_frame++;
  }
}

// Writes frames to the take, reducing to the selected channel if there is one.
// Returns false on a disk error. *limit_hit is set if the WAV size cap is reached.
static ma_bool32 write_frames(session* s, const ma_uint8* frames, ma_uint32 count,
                              ma_bool32* limit_hit) {
  const ma_uint32 out_channels = s->selected_channel >= 0 ? 1 : s->channels;
  const ma_uint32 out_frame_bytes = out_channels * s->bytes_per_sample;
  ma_uint64 room = OVA_MAX_DATA_BYTES - s->data_bytes;
  if ((ma_uint64)count * out_frame_bytes > room) {
    count = (ma_uint32)(room / out_frame_bytes);
    *limit_hit = MA_TRUE;
  }
  if (count == 0) return MA_TRUE;

  const void* out = frames;
  if (s->selected_channel >= 0 && s->channels > 1) {
    for (ma_uint32 f = 0; f < count; f++) {
      memcpy(s->convert_buffer + (size_t)f * s->bytes_per_sample,
             frames + (size_t)f * s->bytes_per_frame +
                 (size_t)s->selected_channel * s->bytes_per_sample,
             s->bytes_per_sample);
    }
    out = s->convert_buffer;
  }
  if (!write_all(s->file, out, count * out_frame_bytes)) return MA_FALSE;
  s->data_bytes += (ma_uint64)count * out_frame_bytes;

  EnterCriticalSection(&g_lock);
  s->frames_written += count;
  LeaveCriticalSection(&g_lock);
  return MA_TRUE;
}

// Writes pre-roll in blocks small enough for the convert buffer.
static ma_bool32 write_pre_roll(session* s, ma_uint32 frames) {
  ma_bool32 limit_hit = MA_FALSE;
  const ma_uint64 available =
      s->pre_roll_write_frame < s->pre_roll_capacity_frames
          ? s->pre_roll_write_frame
          : s->pre_roll_capacity_frames;
  ma_uint64 remaining = frames < available ? frames : available;
  ma_uint64 cursor = s->pre_roll_write_frame - remaining;
  while (remaining > 0) {
    const ma_uint64 slot = cursor % s->pre_roll_capacity_frames;
    ma_uint64 chunk = s->pre_roll_capacity_frames - slot;
    if (chunk > remaining) chunk = remaining;
    if (chunk > OVA_WRITER_BLOCK_FRAMES) chunk = OVA_WRITER_BLOCK_FRAMES;
    if (!write_frames(s, s->pre_roll + slot * s->bytes_per_frame, (ma_uint32)chunk,
                      &limit_hit)) {
      return MA_FALSE;
    }
    cursor += chunk;
    remaining -= chunk;
  }
  return MA_TRUE;
}

static void finish_take(session* s, LONG result) {
  if (s->file != INVALID_HANDLE_VALUE) {
    wav_format wav = take_format(s);
    // Only a stop asks for a trim. A take that ended by itself keeps everything.
    if (result == OVA_TAKE_OK && s->trim_frames > 0) {
      const ma_uint64 frame_bytes = (ma_uint64)wav.channels * wav.bytes_per_sample;
      ma_uint64 trim_bytes = s->trim_frames * frame_bytes;
      if (trim_bytes > s->data_bytes) trim_bytes = s->data_bytes;
      s->data_bytes -= trim_bytes;
      EnterCriticalSection(&g_lock);
      s->frames_written -= (ma_int64)(trim_bytes / frame_bytes);
      LeaveCriticalSection(&g_lock);
    }
    ma_uint8 header[WAV_HEADER_FLOAT_BYTES];
    const ma_uint32 data_bytes = (ma_uint32)s->data_bytes;
    const DWORD header_bytes = build_wav_header(header, &wav, data_bytes);
    LARGE_INTEGER end;
    end.QuadPart = (LONGLONG)header_bytes + (LONGLONG)s->data_bytes;
    LARGE_INTEGER zero;
    zero.QuadPart = 0;
    ma_bool32 ok = SetFilePointerEx(s->file, end, NULL, FILE_BEGIN) &&
                   SetEndOfFile(s->file) &&
                   SetFilePointerEx(s->file, zero, NULL, FILE_BEGIN) &&
                   write_all(s->file, header, header_bytes) &&
                   FlushFileBuffers(s->file);
    CloseHandle(s->file);
    s->file = INVALID_HANDLE_VALUE;
    if (ok) {
      ok = MoveFileExW(s->partial_path, s->final_path,
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
    }
    if (!ok) result = OVA_TAKE_DISK_ERROR;
  }
  EnterCriticalSection(&g_lock);
  s->last_take_result = result;
  s->state = s->open ? OVA_STATE_ARMED : OVA_STATE_CLOSED;
  LeaveCriticalSection(&g_lock);
  s->tail_active = MA_FALSE;
}

// Applies a pending start or stop.
static void handle_command(session* s) {
  EnterCriticalSection(&g_lock);
  const writer_cmd cmd = s->cmd;
  s->cmd = CMD_NONE;
  if (cmd == CMD_START) {
    s->file = s->cmd_file;
    s->cmd_file = INVALID_HANDLE_VALUE;
    memcpy(s->final_path, s->cmd_final_path, sizeof(s->final_path));
    memcpy(s->partial_path, s->cmd_partial_path, sizeof(s->partial_path));
    s->selected_channel = s->cmd_selected_channel;
    s->data_bytes = 0;
    s->frames_written = 0;
    s->clipped_samples = 0;
    s->tail_active = MA_FALSE;
    s->trim_frames = 0;
    s->last_flush_ms = GetTickCount();
    s->last_take_result = OVA_TAKE_NONE;
  } else if (cmd == CMD_STOP) {
    s->tail_remaining = s->cmd_tail_frames;
    s->trim_frames = s->cmd_trim_frames;
    s->tail_active = MA_TRUE;
  }
  LeaveCriticalSection(&g_lock);

  if (cmd == CMD_START && !write_pre_roll(s, s->cmd_pre_roll_frames)) {
    finish_take(s, OVA_TAKE_DISK_ERROR);
  }
}

static DWORD WINAPI writer_main(LPVOID param) {
  session* s = (session*)param;
  for (;;) {
    const ma_bool32 quitting = InterlockedCompareExchange(&s->quit, 0, 0) != 0;

    handle_command(s);

    ma_uint32 frames = OVA_WRITER_BLOCK_FRAMES;
    void* block = NULL;
    ma_bool32 got_audio = MA_FALSE;
    if (ma_pcm_rb_acquire_read(&s->ring, &frames, &block) == MA_SUCCESS &&
        frames > 0) {
      got_audio = MA_TRUE;
      const ma_bool32 recording = s->file != INVALID_HANDLE_VALUE;
      meter_frames(s, (const ma_uint8*)block, frames, recording);
      if (recording) {
        ma_uint32 to_write = frames;
        if (s->tail_active && to_write > s->tail_remaining) {
          to_write = (ma_uint32)s->tail_remaining;
        }
        ma_bool32 limit_hit = MA_FALSE;
        if (!write_frames(s, (const ma_uint8*)block, to_write, &limit_hit)) {
          finish_take(s, OVA_TAKE_DISK_ERROR);
        } else if (limit_hit) {
          finish_take(s, OVA_TAKE_SIZE_LIMIT);
        } else if (s->tail_active) {
          s->tail_remaining -= to_write;
          if (s->tail_remaining == 0) finish_take(s, OVA_TAKE_OK);
        }
        const DWORD now = GetTickCount();
        if (s->file != INVALID_HANDLE_VALUE &&
            now - s->last_flush_ms >= OVA_FLUSH_INTERVAL_MS) {
          FlushFileBuffers(s->file);
          s->last_flush_ms = now;
        }
      }
      pre_roll_store(s, (const ma_uint8*)block, frames);
      ma_pcm_rb_commit_read(&s->ring, frames);
    }

    if (got_audio) continue;

    // The ring is drained, so nothing more can arrive from a lost device.
    if (s->file != INVALID_HANDLE_VALUE &&
        InterlockedCompareExchange(&s->device_lost, 0, 0) != 0) {
      finish_take(s, OVA_TAKE_DEVICE_LOST);
    }
    if (quitting) {
      if (s->file != INVALID_HANDLE_VALUE) finish_take(s, OVA_TAKE_DEVICE_LOST);
      return 0;
    }
    Sleep(5);
  }
}

static void write_synth_sample(ma_uint8* out, ma_format format, double value) {
  switch (format) {
    case ma_format_u8:
      out[0] = (ma_uint8)(128 + (int)(value * 127.0));
      break;
    case ma_format_s16:
      put_u16(out, (ma_uint16)(ma_int16)(value * 32767.0));
      break;
    case ma_format_s24: {
      ma_int32 v = (ma_int32)(value * 8388607.0);
      out[0] = (ma_uint8)v;
      out[1] = (ma_uint8)(v >> 8);
      out[2] = (ma_uint8)(v >> 16);
      break;
    }
    case ma_format_s32:
      put_u32(out, (ma_uint32)(ma_int32)(value * 2147483647.0));
      break;
    case ma_format_f32: {
      float v = (float)value;
      memcpy(out, &v, sizeof(v));
      break;
    }
    default:
      break;
  }
}

static DWORD WINAPI synth_main(LPVOID param) {
  session* s = (session*)param;
  const ma_uint32 block_frames = s->rate / 100;
  ma_uint8* block = (ma_uint8*)ma_malloc(
      (size_t)block_frames * s->bytes_per_frame, NULL);
  if (block == NULL) return 1;
  const double two_pi = 6.283185307179586;
  ma_uint64 frame = 0;
  while (InterlockedCompareExchange(&s->quit, 0, 0) == 0 &&
         InterlockedCompareExchange(&s->device_lost, 0, 0) == 0) {
    for (ma_uint32 f = 0; f < block_frames; f++, frame++) {
      for (ma_uint32 c = 0; c < s->channels; c++) {
        const double hz = 440.0 + 110.0 * c;
        write_synth_sample(block + (size_t)f * s->bytes_per_frame +
                               (size_t)c * s->bytes_per_sample,
                           s->format,
                           0.5 * sin(two_pi * hz * (double)frame / s->rate));
      }
    }
    // Faster than real time waits for room instead of counting as dropped.
    while (s->synth_speed > 1 &&
           ma_pcm_rb_available_write(&s->ring) < block_frames &&
           InterlockedCompareExchange(&s->quit, 0, 0) == 0) {
      Sleep(1);
    }
    ring_push(s, block, block_frames);
    const LONG speed = InterlockedCompareExchange(&s->synth_speed, 0, 0);
    if (speed <= 1) {
      Sleep(10);
    } else if (speed < 100) {
      Sleep((DWORD)(10 / speed));
    }
  }
  ma_free(block, NULL);
  return 0;
}

static void ensure_lock(void) {
  if (InterlockedCompareExchange(&g_lock_ready, 1, 0) == 0) {
    InitializeCriticalSection(&g_lock);
  }
}

// Allocates everything that depends on the final format, then starts the writer.
static int32_t session_start_writer(session* s) {
  s->bytes_per_sample = bytes_per_sample(s->format);
  s->bytes_per_frame = s->bytes_per_sample * s->channels;
  if (s->bytes_per_frame == 0) return OVA_ERR_DEVICE;

  if (ma_pcm_rb_init(s->format, s->channels, s->rate * OVA_RING_SECONDS, NULL,
                     NULL, &s->ring) != MA_SUCCESS) {
    return OVA_ERR_DEVICE;
  }
  s->pre_roll_capacity_frames = (ma_uint64)s->rate * OVA_MAX_PRE_ROLL_MS / 1000;
  s->pre_roll = (ma_uint8*)ma_malloc(
      (size_t)s->pre_roll_capacity_frames * s->bytes_per_frame, NULL);
  s->convert_buffer = (ma_uint8*)ma_malloc(
      (size_t)OVA_WRITER_BLOCK_FRAMES * s->bytes_per_sample, NULL);
  if (s->pre_roll == NULL || s->convert_buffer == NULL) {
    return OVA_ERR_DEVICE;
  }
  s->file = INVALID_HANDLE_VALUE;
  s->cmd_file = INVALID_HANDLE_VALUE;
  s->selected_channel = -1;
  s->state = OVA_STATE_ARMED;
  s->writer_thread = CreateThread(NULL, 0, writer_main, s, 0, NULL);
  return s->writer_thread != NULL ? OVA_OK : OVA_ERR_DEVICE;
}

static void session_reset(session* s) {
  memset(s, 0, sizeof(*s));
  s->file = INVALID_HANDLE_VALUE;
  s->cmd_file = INVALID_HANDLE_VALUE;
}

int32_t ova_open(int32_t device_index, int32_t exclusive, int32_t format,
                 int32_t sample_rate, int32_t channels) {
  ensure_lock();
  session* s = &g_session;
  if (s->open) return OVA_ERR_BAD_STATE;
  if (ensure_context() != MA_SUCCESS) return OVA_ERR_DEVICE;
  if (device_index != -1 && !valid_device(device_index)) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  session_reset(s);

  ma_device_config config = ma_device_config_init(ma_device_type_capture);
  config.capture.pDeviceID =
      device_index >= 0 ? &g_devices[device_index].id : NULL;
  config.capture.format = (ma_format)format;
  config.capture.channels = (ma_uint32)channels;
  config.capture.shareMode =
      exclusive ? ma_share_mode_exclusive : ma_share_mode_shared;
  config.sampleRate = (ma_uint32)sample_rate;
  config.periodSizeInMilliseconds = OVA_DEVICE_PERIOD_MS;
  config.periods = OVA_DEVICE_PERIODS;
  config.dataCallback = data_callback;
  config.notificationCallback = notification_callback;
  config.pUserData = s;
  config.noFixedSizedCallback = MA_TRUE;
  // No resampling inside WASAPI, and a take must never move to another device
  // because the Windows default changed.
  config.wasapi.noAutoConvertSRC = MA_TRUE;
  config.wasapi.noAutoStreamRouting = MA_TRUE;
  config.wasapi.usage = ma_wasapi_usage_pro_audio;

  if (ma_device_init(&g_context, &config, &s->device) != MA_SUCCESS) {
    return OVA_ERR_DEVICE;
  }
  s->format = s->device.capture.format;
  s->rate = s->device.sampleRate;
  s->channels = s->device.capture.channels;

  int32_t result = session_start_writer(s);
  if (result != OVA_OK) {
    ma_device_uninit(&s->device);
    return result;
  }
  s->open = MA_TRUE;
  if (ma_device_start(&s->device) != MA_SUCCESS) {
    ova_close();
    return OVA_ERR_DEVICE;
  }
  return OVA_OK;
}

int32_t ova_open_synthetic(int32_t format, int32_t sample_rate, int32_t channels,
                           int32_t speed) {
  ensure_lock();
  session* s = &g_session;
  if (s->open) return OVA_ERR_BAD_STATE;
  if (format < OVA_FORMAT_U8 || format > OVA_FORMAT_F32 || sample_rate <= 0 ||
      channels <= 0) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  session_reset(s);
  s->is_synthetic = MA_TRUE;
  s->format = (ma_format)format;
  s->rate = (ma_uint32)sample_rate;
  s->channels = (ma_uint32)channels;
  s->synth_speed = speed < 1 ? 1 : speed;

  int32_t result = session_start_writer(s);
  if (result != OVA_OK) return result;
  s->open = MA_TRUE;
  s->synth_thread = CreateThread(NULL, 0, synth_main, s, 0, NULL);
  if (s->synth_thread == NULL) {
    ova_close();
    return OVA_ERR_DEVICE;
  }
  return OVA_OK;
}

int32_t ova_session_info(ova_session_format* out) {
  session* s = &g_session;
  if (!s->open) return OVA_ERR_BAD_STATE;
  out->format = (int32_t)s->format;
  out->sample_rate = (int32_t)s->rate;
  out->channels = (int32_t)s->channels;
  out->raw_mode = !s->is_synthetic && g_ova_raw_capture_applied;
  if (s->is_synthetic) {
    out->exclusive = 0;
    out->device_format = (int32_t)s->format;
    out->device_rate = (int32_t)s->rate;
    out->device_channels = (int32_t)s->channels;
  } else {
    out->exclusive = s->device.capture.shareMode == ma_share_mode_exclusive;
    out->device_format = (int32_t)s->device.capture.internalFormat;
    out->device_rate = (int32_t)s->device.capture.internalSampleRate;
    out->device_channels = (int32_t)s->device.capture.internalChannels;
  }
  return OVA_OK;
}

void ova_close(void) {
  session* s = &g_session;
  if (!s->open) return;
  s->expected_device_stop = 1;
  if (s->synth_thread != NULL) {
    InterlockedExchange(&s->quit, 1);
    WaitForSingleObject(s->synth_thread, INFINITE);
    CloseHandle(s->synth_thread);
  } else {
    ma_device_uninit(&s->device);
  }
  // Any take still open is saved by the writer before it exits.
  s->open = MA_FALSE;
  InterlockedExchange(&s->quit, 1);
  WaitForSingleObject(s->writer_thread, INFINITE);
  CloseHandle(s->writer_thread);

  EnterCriticalSection(&g_lock);
  s->state = OVA_STATE_CLOSED;
  if (s->cmd_file != INVALID_HANDLE_VALUE) {
    CloseHandle(s->cmd_file);
    s->cmd_file = INVALID_HANDLE_VALUE;
    DeleteFileW(s->cmd_partial_path);
  }
  LeaveCriticalSection(&g_lock);

  ma_pcm_rb_uninit(&s->ring);
  ma_free(s->pre_roll, NULL);
  ma_free(s->convert_buffer, NULL);
  s->pre_roll = NULL;
  s->convert_buffer = NULL;
}

int32_t ova_record_start(const char* wav_path_utf8, int32_t selected_channel,
                         int32_t pre_roll_ms) {
  session* s = &g_session;
  if (!s->open || wav_path_utf8 == NULL) return OVA_ERR_BAD_ARGUMENT;
  if (selected_channel < -1 || selected_channel >= (int32_t)s->channels) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  if (pre_roll_ms < 0 || pre_roll_ms > OVA_MAX_PRE_ROLL_MS) {
    return OVA_ERR_BAD_ARGUMENT;
  }

  WCHAR final_path[MAX_PATH * 2];
  WCHAR partial_path[MAX_PATH * 2];
  if (!utf8_to_wide(wav_path_utf8, final_path, MAX_PATH * 2 - 16)) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  swprintf_s(partial_path, MAX_PATH * 2, L"%s.partial", final_path);

  EnterCriticalSection(&g_lock);
  const LONG state = s->state;
  const ma_bool32 pending = s->cmd != CMD_NONE;
  LeaveCriticalSection(&g_lock);
  if (state != OVA_STATE_ARMED || pending ||
      InterlockedCompareExchange(&s->device_lost, 0, 0) != 0) {
    return OVA_ERR_BAD_STATE;
  }

  HANDLE file =
      CreateFileW(partial_path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) return OVA_ERR_FILE;

  // A placeholder header with zero data bytes makes a crash detectable and
  // lets ova_recover_partial rebuild it from the file size.
  wav_format wav;
  wav.format = s->format;
  wav.rate = s->rate;
  wav.channels = selected_channel >= 0 ? 1 : s->channels;
  wav.bytes_per_sample = s->bytes_per_sample;
  ma_uint8 header[WAV_HEADER_FLOAT_BYTES];
  const DWORD header_bytes = build_wav_header(header, &wav, 0);
  if (!write_all(file, header, header_bytes)) {
    CloseHandle(file);
    DeleteFileW(partial_path);
    return OVA_ERR_FILE;
  }

  EnterCriticalSection(&g_lock);
  s->cmd = CMD_START;
  s->cmd_file = file;
  wcscpy_s(s->cmd_final_path, MAX_PATH * 2, final_path);
  wcscpy_s(s->cmd_partial_path, MAX_PATH * 2, partial_path);
  s->cmd_selected_channel = selected_channel;
  s->cmd_pre_roll_frames = (ma_uint32)((ma_uint64)s->rate * pre_roll_ms / 1000);
  s->state = OVA_STATE_RECORDING;
  s->last_take_result = OVA_TAKE_NONE;
  s->frames_written = 0;
  s->clipped_samples = 0;
  LeaveCriticalSection(&g_lock);
  return OVA_OK;
}

int32_t ova_record_stop(int32_t tail_ms) {
  session* s = &g_session;
  if (!s->open) return OVA_ERR_BAD_ARGUMENT;
  int32_t result = OVA_OK;
  EnterCriticalSection(&g_lock);
  // cmd must be clear: a start the writer hasn't picked up yet can't be stopped.
  if (s->state != OVA_STATE_RECORDING || s->cmd != CMD_NONE) {
    result = OVA_ERR_BAD_STATE;
  } else {
    s->cmd = CMD_STOP;
    s->cmd_tail_frames = tail_ms > 0 ? (ma_uint64)s->rate * tail_ms / 1000 : 0;
    s->cmd_trim_frames = tail_ms < 0 ? (ma_uint64)s->rate * -(ma_int64)tail_ms / 1000 : 0;
    s->state = OVA_STATE_STOPPING;
  }
  LeaveCriticalSection(&g_lock);
  return result;
}

void ova_get_status(ova_status* out) {
  session* s = &g_session;
  memset(out, 0, sizeof(*out));
  ensure_lock();
  EnterCriticalSection(&g_lock);
  out->state = s->state;
  out->last_take_result = s->last_take_result;
  out->frames_written = s->frames_written;
  out->clipped_samples = s->clipped_samples;
  out->input_channels = (int32_t)s->channels;
  memcpy(out->peaks, s->peaks, sizeof(out->peaks));
  memset(s->peaks, 0, sizeof(s->peaks));
  LeaveCriticalSection(&g_lock);
  out->device_lost = (int32_t)InterlockedCompareExchange(&s->device_lost, 0, 0);
  out->dropped_frames = InterlockedCompareExchange64(&s->dropped_frames, 0, 0);
}

void ova_test_lose_device(void) {
  InterlockedExchange(&g_session.device_lost, 1);
}

int64_t ova_recover_partial(const char* partial_path_utf8) {
  WCHAR partial_path[MAX_PATH * 2];
  if (partial_path_utf8 == NULL ||
      !utf8_to_wide(partial_path_utf8, partial_path, MAX_PATH * 2)) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  WCHAR final_path[MAX_PATH * 2];
  wcscpy_s(final_path, MAX_PATH * 2, partial_path);
  const size_t len = wcslen(final_path);
  const size_t suffix_len = wcslen(L".partial");
  if (len <= suffix_len ||
      _wcsicmp(final_path + len - suffix_len, L".partial") != 0) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  final_path[len - suffix_len] = L'\0';

  HANDLE file = CreateFileW(partial_path, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) return OVA_ERR_FILE;

  ma_uint8 h[WAV_HEADER_FLOAT_BYTES];
  DWORD read = 0;
  LARGE_INTEGER size;
  if (!GetFileSizeEx(file, &size) ||
      !ReadFile(file, h, sizeof(h), &read, NULL) ||
      read < WAV_HEADER_INT_BYTES || memcmp(h, "RIFF", 4) != 0 ||
      memcmp(h + 8, "WAVE", 4) != 0 || memcmp(h + 12, "fmt ", 4) != 0) {
    CloseHandle(file);
    return OVA_ERR_NOT_WAV;
  }

  wav_format wav;
  const ma_uint16 tag = get_u16(h + 20);
  const ma_uint16 bits = get_u16(h + 34);
  wav.channels = get_u16(h + 22);
  wav.rate = get_u32(h + 24);
  wav.bytes_per_sample = bits / 8;
  if (tag == WAV_TAG_FLOAT) {
    wav.format = ma_format_f32;
  } else {
    wav.format = bits == 8    ? ma_format_u8
                 : bits == 16 ? ma_format_s16
                 : bits == 24 ? ma_format_s24
                              : ma_format_s32;
  }
  const DWORD header_bytes =
      tag == WAV_TAG_FLOAT ? WAV_HEADER_FLOAT_BYTES : WAV_HEADER_INT_BYTES;
  const ma_uint32 block_align = wav.channels * wav.bytes_per_sample;
  if (block_align == 0 || (ma_uint64)size.QuadPart < header_bytes) {
    CloseHandle(file);
    return OVA_ERR_NOT_WAV;
  }

  // A crash can leave a torn final frame, so keep only whole frames.
  ma_uint64 data = (ma_uint64)size.QuadPart - header_bytes;
  if (data > OVA_MAX_DATA_BYTES) data = OVA_MAX_DATA_BYTES;
  data -= data % block_align;

  ma_uint8 header[WAV_HEADER_FLOAT_BYTES];
  build_wav_header(header, &wav, (ma_uint32)data);
  LARGE_INTEGER offset;
  offset.QuadPart = (LONGLONG)(header_bytes + data);
  LARGE_INTEGER zero;
  zero.QuadPart = 0;
  const ma_bool32 ok = SetFilePointerEx(file, offset, NULL, FILE_BEGIN) &&
                       SetEndOfFile(file) &&
                       SetFilePointerEx(file, zero, NULL, FILE_BEGIN) &&
                       write_all(file, header, header_bytes) &&
                       FlushFileBuffers(file);
  CloseHandle(file);
  if (!ok || !MoveFileExW(partial_path, final_path,
                          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return OVA_ERR_FILE;
  }
  return (int64_t)(data / block_align);
}

// Playback. One file at a time on the default output, separate from capture.

typedef struct {
  ma_bool32 open;
  ma_decoder decoder;
  ma_device device;
  volatile LONG finished;
  volatile LONG64 position_frames;
  ma_uint64 total_frames;
  ma_uint32 rate;
} player;

static player g_player;

static void player_callback(ma_device* device, void* output, const void* input,
                            ma_uint32 frame_count) {
  (void)input;
  player* p = (player*)device->pUserData;
  ma_uint64 read = 0;
  ma_decoder_read_pcm_frames(&p->decoder, output, frame_count, &read);
  InterlockedExchangeAdd64(&p->position_frames, (LONG64)read);
  if (read < frame_count) InterlockedExchange(&p->finished, 1);
}

void ova_play_stop(void) {
  if (!g_player.open) return;
  ma_device_uninit(&g_player.device);
  ma_decoder_uninit(&g_player.decoder);
  g_player.open = MA_FALSE;
}

int32_t ova_play_start(const char* wav_path_utf8) {
  ova_play_stop();
  WCHAR path[MAX_PATH * 2];
  if (wav_path_utf8 == NULL || !utf8_to_wide(wav_path_utf8, path, MAX_PATH * 2)) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  if (ensure_context() != MA_SUCCESS) return OVA_ERR_DEVICE;

  player* p = &g_player;
  if (ma_decoder_init_file_w(path, NULL, &p->decoder) != MA_SUCCESS) {
    return OVA_ERR_FILE;
  }
  ma_uint64 total = 0;
  ma_decoder_get_length_in_pcm_frames(&p->decoder, &total);
  p->total_frames = total;
  p->rate = p->decoder.outputSampleRate;
  p->finished = 0;
  p->position_frames = 0;

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = p->decoder.outputFormat;
  config.playback.channels = p->decoder.outputChannels;
  config.sampleRate = p->decoder.outputSampleRate;
  config.dataCallback = player_callback;
  config.pUserData = p;
  if (ma_device_init(&g_context, &config, &p->device) != MA_SUCCESS) {
    ma_decoder_uninit(&p->decoder);
    return OVA_ERR_DEVICE;
  }
  if (ma_device_start(&p->device) != MA_SUCCESS) {
    ma_device_uninit(&p->device);
    ma_decoder_uninit(&p->decoder);
    return OVA_ERR_DEVICE;
  }
  p->open = MA_TRUE;
  return OVA_OK;
}

void ova_play_status(ova_play_state* out) {
  memset(out, 0, sizeof(*out));
  player* p = &g_player;
  if (!p->open) return;
  const ma_bool32 done = InterlockedCompareExchange(&p->finished, 0, 0) != 0 ||
                         !ma_device_is_started(&p->device);
  out->state = done ? OVA_PLAY_FINISHED : OVA_PLAY_PLAYING;
  out->position_frames = InterlockedCompareExchange64(&p->position_frames, 0, 0);
  out->total_frames = (int64_t)p->total_frames;
  out->sample_rate = (int32_t)p->rate;
}

int64_t ova_free_disk_bytes(const char* path_utf8) {
  WCHAR path[MAX_PATH * 2];
  if (path_utf8 == NULL || !utf8_to_wide(path_utf8, path, MAX_PATH * 2)) {
    return OVA_ERR_BAD_ARGUMENT;
  }
  ULARGE_INTEGER available;
  if (!GetDiskFreeSpaceExW(path, &available, NULL, NULL)) return OVA_ERR_FILE;
  return (int64_t)available.QuadPart;
}
