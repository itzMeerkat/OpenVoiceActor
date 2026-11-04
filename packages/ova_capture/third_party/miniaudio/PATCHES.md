# Local changes to miniaudio

Source: miniaudio 0.11.26, https://github.com/mackron/miniaudio/tree/0.11.26

Search `miniaudio.h` for `OVA PATCH`.

## Raw capture

miniaudio has no option for WASAPI's raw stream mode, which asks Windows to bypass audio effects on the capture path. `ma_device_init_internal__wasapi` now calls `SetClientProperties` with `MA_AUDCLNT_STREAMOPTIONS_RAW` for capture devices, and stores whether the call succeeded in `g_ova_raw_capture_applied`, which `src/ova_capture.c` defines before including this header.

Success means Windows accepted the request. It doesn't prove that a device's own hardware or driver isn't processing the signal.

Consider proposing this upstream as a config option so the patch can be dropped.
