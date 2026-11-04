import 'package:flutter/material.dart';

import 'tokens.dart';

/// Restyles Material so its buttons, inputs and dialogs match the app, while
/// keeping their behavior, focus handling and accessibility.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: Palette.accent,
    onPrimary: Colors.white,
    primaryContainer: Palette.accentSoft,
    onPrimaryContainer: Palette.accentInk,
    secondary: Palette.ink,
    onSecondary: Colors.white,
    secondaryContainer: Palette.surfaceSoft,
    onSecondaryContainer: Palette.ink,
    surface: Palette.surface,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.inkSoft,
    surfaceContainerLowest: Palette.surface,
    surfaceContainerLow: Palette.surface,
    surfaceContainer: Palette.surface,
    surfaceContainerHigh: Palette.surface,
    surfaceContainerHighest: Palette.surfaceSoft,
    surfaceTint: Colors.transparent,
    outline: Palette.lineStrong,
    outlineVariant: Palette.line,
    error: Palette.danger,
    onError: Colors.white,
    errorContainer: Palette.dangerSoft,
    onErrorContainer: Palette.dangerInk,
  );

  const text = TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: -0.3,
    ),
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: Palette.inkSoft),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
  );

  const buttonPadding = EdgeInsets.symmetric(
    horizontal: Space.l + 2,
    vertical: Space.m,
  );
  const buttonShape = StadiumBorder();
  // Underline borders keep the floating label inside the filled box.
  final softBorder = UnderlineInputBorder(
    borderRadius: BorderRadius.circular(Corners.m),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.page,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.page,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: Space.s,
      foregroundColor: Palette.ink,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Palette.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
        disabledBackgroundColor: Palette.surfaceSoft,
        disabledForegroundColor: Palette.inkFaint,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
        foregroundColor: Palette.ink,
        side: const BorderSide(color: Palette.lineStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.m,
          vertical: Space.s + 2,
        ),
        shape: buttonShape,
        textStyle: text.labelLarge,
        foregroundColor: Palette.accent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Palette.inkSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surfaceSoft,
      border: softBorder,
      enabledBorder: softBorder,
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(Corners.m),
        borderSide: const BorderSide(color: Palette.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.m + 2,
        vertical: Space.m + 2,
      ),
      labelStyle: const TextStyle(color: Palette.inkSoft),
      floatingLabelStyle: const TextStyle(color: Palette.accent),
      hintStyle: const TextStyle(color: Palette.inkFaint),
    ),
    cardTheme: CardThemeData(
      color: Palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.l),
        side: const BorderSide(color: Palette.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: const Color(0x33000000),
      // Narrow insets, so a dialog on a phone keeps room for its text.
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.xl),
      ),
      titleTextStyle: text.titleLarge!.copyWith(color: Palette.ink),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.page,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Palette.page,
      dragHandleColor: Palette.lineStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corners.xl)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.accentSoft,
      height: 64,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Palette.accent
              : Palette.inkSoft,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? Palette.accent
              : Palette.inkSoft,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Palette.accent,
      foregroundColor: Colors.white,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 4,
      shape: StadiumBorder(),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.m),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.m),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Palette.ink,
        borderRadius: BorderRadius.circular(Corners.s),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Space.m),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.accent,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.accent
            : Palette.lineStrong,
      ),
    ),
  );
}
