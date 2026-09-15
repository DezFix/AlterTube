import 'package:flutter/material.dart';

// Единая дизайн-система AlterTube v1.
// Светлая / тёмная / AMOLED-чёрная. Акцент — красный как у YouTube,
// но дальше экраны используют только эту палитру, а не Colors.red вразнобой.

class AppTheme {
  static const _seed = Colors.red;

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: Brightness.light,
    );
  }

  static ThemeData dark({bool amoled = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    final bg = amoled ? Colors.black : null;
    final surface = amoled ? Colors.black : null;
    return ThemeData(
      useMaterial3: true,
      colorScheme: amoled
          ? scheme.copyWith(surface: Colors.black)
          : scheme,
      scaffoldBackgroundColor: bg,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        color: surface,
      ),
      listTileTheme: const ListTileThemeData(dense: false),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
