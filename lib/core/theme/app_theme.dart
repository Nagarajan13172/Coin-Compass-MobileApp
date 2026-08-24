import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 themes built from the CoinCompass design tokens.
/// Radius 12 everywhere (`--radius: .75rem`), Inter as the type family.
class AppTheme {
  const AppTheme._();

  static const double radius = 12;
  static const String fontFamily = 'Inter';

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.primaryForeground,
      secondary: c.secondary,
      onSecondary: c.secondaryForeground,
      error: c.destructive,
      onError: Colors.white,
      surface: c.card,
      onSurface: c.cardForeground,
      surfaceContainerHighest: c.muted,
      outline: c.border,
      outlineVariant: c.border,
    );

    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(base.textTheme, c),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.foreground,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.secondary,
        hintStyle: TextStyle(color: c.mutedForeground, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: _inputBorder(c.input),
        enabledBorder: _inputBorder(c.input),
        disabledBorder: _inputBorder(c.input),
        focusedBorder: _inputBorder(c.ring, width: 1.6),
        errorBorder: _inputBorder(c.destructive),
        focusedErrorBorder: _inputBorder(c.destructive, width: 1.6),
        errorStyle: TextStyle(color: c.destructive, fontSize: 12.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.primaryForeground,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.5),
          disabledForegroundColor: c.primaryForeground.withValues(alpha: 0.8),
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.foreground,
          backgroundColor: c.card,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: c.border),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.foreground),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: c.border,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: c.secondary,
        selectedColor: c.primary,
        side: BorderSide(color: c.border),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.foreground,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : c.card,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.foreground,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.background,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.secondary,
        circularTrackColor: c.secondary,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.mutedForeground,
        textColor: c.foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.primary,
        unselectedLabelColor: c.mutedForeground,
        indicatorColor: c.primary,
        dividerColor: c.border,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base, AppColors c) {
    TextStyle s(
      double size,
      FontWeight weight, {
      Color? color,
      double? height,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? c.foreground,
        height: height,
      );
    }

    return base
        .copyWith(
          displayLarge: s(34, FontWeight.w700),
          displayMedium: s(30, FontWeight.w700),
          displaySmall: s(28, FontWeight.w700),
          headlineLarge: s(26, FontWeight.w700),
          headlineMedium: s(24, FontWeight.w700),
          headlineSmall: s(22, FontWeight.w700),
          titleLarge: s(19, FontWeight.w600),
          titleMedium: s(17, FontWeight.w600),
          titleSmall: s(15, FontWeight.w600),
          bodyLarge: s(15.5, FontWeight.w400, height: 1.45),
          bodyMedium: s(14, FontWeight.w400, height: 1.45),
          bodySmall: s(13, FontWeight.w400, color: c.mutedForeground),
          labelLarge: s(14, FontWeight.w600),
          labelMedium: s(12.5, FontWeight.w500, color: c.mutedForeground),
          labelSmall: s(11, FontWeight.w500, color: c.mutedForeground),
        )
        .apply(fontFamily: fontFamily);
  }
}
