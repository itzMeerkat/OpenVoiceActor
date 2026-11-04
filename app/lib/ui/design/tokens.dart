/// The app's look in one place. Screens use these names rather than raw values,
/// so changing the look is mostly a matter of editing this file.
library;

import 'dart:ui';

abstract final class Palette {
  // The one strong color. Primary actions, selection and recording use it.
  static const accent = Color(0xFFCF3F16);
  static const accentHover = Color(0xFFB83511);
  static const accentSoft = Color(0xFFFDE9E1);
  static const accentInk = Color(0xFF8A2A0E);

  // Warm neutrals, so the page feels soft rather than clinical.
  static const page = Color(0xFFFAF6F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF3EDE5);
  static const line = Color(0xFFEAE3D9);
  static const lineStrong = Color(0xFFD5CBBE);
  static const ink = Color(0xFF2B2420);
  static const inkSoft = Color(0xFF6B6058);
  static const inkFaint = Color(0xFF8C8177);

  static const danger = Color(0xFFB4232F);
  static const dangerSoft = Color(0xFFFBE6E6);
  static const dangerInk = Color(0xFF8C1A24);

  static const success = Color(0xFF2C6B3F);
  static const successSoft = Color(0xFFE2F2E6);
  static const info = Color(0xFF2D5488);
  static const infoSoft = Color(0xFFE5EDF8);
  static const warning = Color(0xFF8A5B0A);
  static const warningSoft = Color(0xFFFBF0D6);

  // Level meter zones.
  static const meterGood = Color(0xFF3FA66F);
  static const meterHot = Color(0xFFE9A23B);
  static const meterClip = Color(0xFFD8343F);

  /// Soft tints with matching ink, one per character.
  static const characterTints = [
    (Color(0xFFFDE9E1), Color(0xFF8A2A0E)),
    (Color(0xFFE5EDF8), Color(0xFF2D5488)),
    (Color(0xFFE2F2E6), Color(0xFF2C6B3F)),
    (Color(0xFFF1E8F8), Color(0xFF5D3B85)),
    (Color(0xFFFBF0D6), Color(0xFF8A5B0A)),
    (Color(0xFFDFF3F2), Color(0xFF1F6663)),
    (Color(0xFFFBE6EF), Color(0xFF8E2B5B)),
  ];
}

abstract final class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Corners {
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 22.0;
  static const pill = 999.0;
}
