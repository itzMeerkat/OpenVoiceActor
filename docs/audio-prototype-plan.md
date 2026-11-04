# Audio Capture Prototype Plan

**Status:** Prototype built, hardware checks still open (2026-11-03). The engine now lives in [packages/ova_capture](../packages/ova_capture), and the test bench in [prototypes/audio_capture](../prototypes/audio_capture/README.md). **Windows only for now.** Other platforms get their own run of this plan when they're added.

## Results so far

**Decision: use the miniaudio wrapper.** `record` 7.1.2 wrote 16-bit files, and when asked for 96 kHz on a 48 kHz mic it produced a 96 kHz file, which the capture policy forbids. It has no setting for bit depth.

Tested on one device, an Anker PowerConf C200 webcam mic (16-bit, 48 kHz). Synthetic means a generated signal through the same ring buffer and writer, with no real device.

| # | Check | Result | Tested with |
|---|---|---|---|
| 1 | Format | Pass, confirmed with `ffprobe` | Mic, plus synthetic 16/24/32-bit int and 32-bit float at 44.1–192 kHz |
| 2 | True bit depth | Pass for the app's own files. **24-bit hardware not tested** | Synthetic, mic at 16-bit |
| 3 | Sample rate | Pass on a generated tone. **No external test tone yet** | Synthetic |
| 4 | No processing | Partial: see below | Mic |
| 5 | Reliability | Pass on synthetic 10 minutes. **No long real-device take yet** | Synthetic |
| 6 | Long sessions | Pass, 200 takes | Synthetic |
| 7 | Crash recovery | Pass, process force-killed mid-take and 2.38 s recovered | Synthetic source |
| 8 | Interruptions | **Not tested on hardware** | Logic only, with a simulated device loss |
| 9 | Device changes | **Not tested on hardware** | Logic only, with a simulated device loss |
| 10 | Input channels | Pass on synthetic. **No real two-channel interface yet** | Synthetic |
| 11 | Start and stop | Audio joins cleanly with no splice. **Not checked by ear** | Synthetic |
| 12 | Metering | **UI not clicked through.** App launches and native levels are reported | Launch only |
| 13 | Packaging | Pass with `archive` 4.6.0: 5 GiB archive, 182 MiB peak memory, listed correctly by `tar` | Generated files |

**Windows effects (check 4):** miniaudio has no raw mode option, so it's added with a [small local patch](../packages/ova_capture/third_party/miniaudio/PATCHES.md). In one before-and-after comparison in shared mode, the file measured full 32-bit float resolution without raw mode and exactly 16 bits with it, matching this mic's true depth. That suggests raw mode bypassed some processing, but it's a single comparison on one device, and processing inside a device can't be detected this way.

**Shared or exclusive:** with raw mode on, both gave 16-bit-exact audio on this mic. Shared mode doesn't lock other apps out of the device, so it's the likely default, as long as a 24-bit interface confirms it there too.

Still open: run the bold items above with a 24-bit interface and a USB mic. **Deferred** (2026-11-03): no 24-bit device is available yet, so the app is being built first. Until this runs, 24-bit capture is proven only with generated audio.

## Goal

The app must never be the weakest link in the recording chain. It captures what the input device provides, in its best available format, with no hidden processing. Post-processing comes later and works on copies of the takes.

## The problem with the obvious choice

The [`record`](https://pub.dev/packages/record) package (7.1.2) is the usual Flutter option, but it may not meet this goal:

- Its encoder list has `wav` and `pcm16bits`, and nothing for 24-bit or float.
- `RecordConfig` has no bit depth setting. Its docs don't state the WAV bit depth, so 16-bit is a strong suspicion rather than a confirmed fact.
- Its docs don't state sample rate limits per platform.

[`audio_io`](https://pub.dev/packages/audio_io) doesn't fit either, because its public stream is fixed at 48 kHz mono.

## Approach to test

Compare two options:

- **A. `record` (baseline):** the least work. Measure what it actually writes.
- **B. A thin FFI wrapper around [miniaudio](https://miniaud.io) (expected choice):** a C library covering WASAPI on Windows, AAudio on Android and Core Audio on Apple platforms. It should support 24-bit and float formats and selectable rates, but this is from memory and has to be confirmed here.

Design for B:

```
Device → miniaudio callback → ring buffer → native writer thread → take.wav.partial
                                   │
                                   └→ peak level (Dart polls for the meter)
```

Samples never pass through Dart, so garbage collection pauses and UI work can't cause dropouts. Dart only sends start and stop commands and reads levels and status.

## Capture policy

1. Ask the device for its native format. Prefer the highest bit depth and the current device rate.
2. Never upsample, and never pad bit depth to look better.
3. Default to the device's current rate instead of the highest it offers. Most mics and interfaces are set to 44.1 or 48 kHz, and forcing a change can make the OS resample.
4. Let the actor choose both the input device and the input channel. A mic on input 1 of a two-channel interface should become a clean mono take, because averaging both channels lowers the level and adds noise from the unused input.
5. Turn off gain control, noise suppression and echo cancellation wherever the platform allows it.
6. Save the true captured format in the take metadata.

On Windows, compare WASAPI shared and exclusive modes:

- Does shared mode hide the true bit depth?
- Does exclusive mode cause too many problems when other apps hold the device?

ASIO is out of scope for now. If WASAPI can't deliver a good result on professional interfaces, reconsider it.

## Storage impact

For 15,000 seconds of mono audio (1,000 lines × 3 takes × 5 seconds):

| Format | Size |
|---|---|
| 48 kHz, 16-bit | 1.4 GB |
| 48 kHz, 24-bit | 2.2 GB |
| 96 kHz, 24-bit | 4.3 GB |
| 96 kHz, 32-bit float | 5.8 GB |

This is why exporting favorites only is the default, and why submissions need ZIP64.

## Test matrix

| Device | Requirement |
|---|---|
| Built-in or default mic | Required |
| USB mic | Required |
| Audio interface, 24-bit or higher | Required |
| Bluetooth headset | Should warn about low quality |

## Checks

| # | Check | Pass condition |
|---|---|---|
| 1 | Format | The WAV header matches the requested and reported format, confirmed with `ffprobe` |
| 2 | True bit depth | 24-bit files contain real low-order data, not padded 16-bit |
| 3 | Sample rate | A test tone stays at the correct pitch, and the file has no resampling surprises |
| 4 | No processing | Gain doesn't ride up on quiet speech, and room noise isn't gated out |
| 5 | Reliability | A 10-minute take has no dropouts and no overrun reports |
| 6 | Long sessions | 200 short takes in a row all finish correctly |
| 7 | Crash recovery | After killing the app mid-take, earlier takes are intact and the partial take can be recovered |
| 8 | Interruptions | Sleep, or another app taking the device, stops the take cleanly and saves what was recorded |
| 9 | Device changes | Unplugging a USB mic gives a clear message and no corrupt file |
| 10 | Input channels | Selecting either channel of a two-channel interface gives clean mono |
| 11 | Start and stop | The first and last syllables aren't clipped |
| 12 | Metering | The meter shows clipping accurately and no sample passes through Dart |
| 13 | Packaging | A ZIP64 submission over 4 GB writes and reads back, without loading it all into memory |

Check 13 tests whether Dart ZIP packages can stream ZIP64 archives. If they can't, the native layer takes this on as well.

## Decision

- **Use `record`** only if checks 1 and 2 show true 24-bit capture and it passes everything else. This seems unlikely.
- **Otherwise use the miniaudio wrapper,** behind a small Dart interface so the app doesn't depend on it directly. That interface also makes adding other platforms later easier.

## Out of scope

Recording UI, project handling, post-processing, and platforms other than Windows.
