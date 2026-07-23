import 'package:flutter/material.dart';

/// ===========================================================================
/// Color palette
/// ===========================================================================

const Color primaryColor = Color(0xFF5B8CFF);

final ColorScheme lightColorScheme = ColorScheme.fromSeed(
  seedColor: primaryColor,
  brightness: Brightness.light,
).copyWith(
  surface: const Color(0xFFF8F6F2),
  surfaceContainer: const Color(0xFFF1EEE9),
  surfaceContainerHighest: const Color(0xFFE8E3DC),
);

final ColorScheme darkColorScheme = ColorScheme.fromSeed(
  seedColor: primaryColor,
  brightness: Brightness.dark,
).copyWith(
  surface: const Color(0xFF10161E),
  surfaceContainer: const Color(0xFF18212C),
  surfaceContainerHighest: const Color(0xFF24303D),
);

/// ===========================================================================
/// LIGHT THEME
/// ===========================================================================

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: lightColorScheme,

  scaffoldBackgroundColor: const Color(0xFFF8F6F2),

  dividerTheme: DividerThemeData(
    color: lightColorScheme.outlineVariant,
  ),

  appBarTheme: AppBarThemeData(
    backgroundColor: Colors.transparent,
    foregroundColor: lightColorScheme.onSurface,
    elevation: 0,
    centerTitle: true,
    surfaceTintColor: Colors.transparent,
  ),

  bottomAppBarTheme: BottomAppBarThemeData(
    color: Colors.white.withValues(alpha: .96),
    surfaceTintColor: Colors.transparent,
  ),

  iconTheme: IconThemeData(
    color: lightColorScheme.onSurface,
  ),

  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: lightColorScheme.onSurface,
      disabledForegroundColor: Colors.blueGrey,
    ),
  ),

  cardTheme: CardThemeData(
    elevation: 1,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: primaryColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
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
      borderSide: BorderSide(
        color: primaryColor,
        width: 2,
      ),
    ),
  ),
);

/// ===========================================================================
/// DARK THEME
/// ===========================================================================

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: darkColorScheme,

  scaffoldBackgroundColor: const Color(0xFF10161E),

  dividerTheme: DividerThemeData(
    color: darkColorScheme.outlineVariant,
  ),

  appBarTheme: AppBarThemeData(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    surfaceTintColor: Colors.transparent,
  ),

  bottomAppBarTheme: const BottomAppBarThemeData(
    color: Color(0xFF181F28),
    surfaceTintColor: Colors.transparent,
  ),

  iconTheme: const IconThemeData(
    color: Colors.white,
  ),

  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.blueGrey,
    ),
  ),
  
  cardTheme: CardThemeData(
    elevation: 0,
    color: const Color(0xFF18212C),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF24303D),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF18212C),
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
      borderSide: BorderSide(
        color: primaryColor,
        width: 2,
      ),
    ),
  ),
);