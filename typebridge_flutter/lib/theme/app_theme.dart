import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TypeBridge 主题系统
/// 基于 MD3 动态色彩方案，使用蓝色系 seed color
class AppTheme {
  // Predefined theme colors for MD3 (Bilibili-style rich palette)
  static const List<Map<String, dynamic>> themeColors = [
    {'name': '默认绿', 'color': Color(0xFF4CAF50)},
    {'name': '粉红色', 'color': Color(0xFFE91E63)},
    {'name': '红色', 'color': Color(0xFFF44336)},
    {'name': '橙色', 'color': Color(0xFFFF9800)},
    {'name': '琥珀色', 'color': Color(0xFFFFC107)},
    {'name': '黄色', 'color': Color(0xFFFFEB3B)},
    {'name': '酸橙色', 'color': Color(0xFFCDDC39)},
    {'name': '浅绿色', 'color': Color(0xFF8BC34A)},
    {'name': '绿色', 'color': Color(0xFF2E7D32)},
    {'name': '青色', 'color': Color(0xFF00BCD4)},
    {'name': '蓝绿色', 'color': Color(0xFF009688)},
    {'name': '浅蓝色', 'color': Color(0xFF03A9F4)},
    {'name': '蓝色', 'color': Color(0xFF2196F3)},
    {'name': '靛蓝色', 'color': Color(0xFF3F51B5)},
    {'name': '紫色', 'color': Color(0xFF9C27B0)},
    {'name': '深紫色', 'color': Color(0xFF673AB7)},
    {'name': '蓝灰色', 'color': Color(0xFF607D8B)},
    {'name': '棕色', 'color': Color(0xFF795548)},
    {'name': '灰色', 'color': Color(0xFF9E9E9E)},
    {'name': '经典蓝', 'color': Color(0xFF2563EB)},
  ];

  static const defaultSeedColor = Color(0xFF4CAF50);

  /// Helper to get quadrant colors for a seed color (Primary, Teritary, Secondary, Surface)
  static List<Color> getQuadrantColors(Color seed, {bool isDark = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    return [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.surfaceContainerHigh,
    ];
  }

  static ThemeData lightTheme(
      {Color seedColor = defaultSeedColor, ColorScheme? colorScheme}) {
    final themeColorScheme = colorScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: themeColorScheme,
      scaffoldBackgroundColor: themeColorScheme.surface,
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: themeColorScheme.surface,
        surfaceTintColor: themeColorScheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: themeColorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: themeColorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: themeColorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorColor: themeColorScheme.primaryContainer,
        backgroundColor: themeColorScheme.surface,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: themeColorScheme.primary,
            );
          }
          return GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: themeColorScheme.onSurfaceVariant,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColorScheme.onPrimary;
          }
          return themeColorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColorScheme.primary;
          }
          return themeColorScheme.surfaceContainerHighest;
        }),
      ),
    );
  }

  static ThemeData darkTheme(
      {Color seedColor = defaultSeedColor, ColorScheme? colorScheme}) {
    final themeColorScheme = colorScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: themeColorScheme,
      scaffoldBackgroundColor: themeColorScheme.surface,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: themeColorScheme.surface,
        surfaceTintColor: themeColorScheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: themeColorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: themeColorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: themeColorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorColor: themeColorScheme.primaryContainer,
        backgroundColor: themeColorScheme.surface,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: themeColorScheme.primary,
            );
          }
          return GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: themeColorScheme.onSurfaceVariant,
          );
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColorScheme.onPrimary;
          }
          return themeColorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return themeColorScheme.primary;
          }
          return themeColorScheme.surfaceContainerHighest;
        }),
      ),
    );
  }
}
