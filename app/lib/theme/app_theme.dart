import 'package:flutter/material.dart';

/// Responsive Breakpoints für Handy (Hochformat), Tablet, Desktop
class Responsive {
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 400;
  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;
  static bool isMedium(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 900;

  /// Handy: kürzeste Seite < 600 (gilt für Hoch- und Querformat)
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600;

  /// Horizontales Padding: 16 auf Handy, 20 tablet, 24 desktop
  static double horizontalPadding(BuildContext context) =>
      isCompact(context) ? 16 : (isNarrow(context) ? 18 : 24);

  /// Gibt Wert für narrow/wide zurück
  static T value<T>(BuildContext context, {required T narrow, required T wide}) =>
      isNarrow(context) ? narrow : wide;

  /// Spalten für Grid: 2 auf Handy, 3 auf Tablet+
  static int shortcutColumns(BuildContext context) =>
      isCompact(context) ? 2 : (isNarrow(context) ? 2 : 3);
}

/// RettBase Brand-Farben (Design-Skill): #4EA8DE, #1D3557, #BEE3F8, #EAF6FF
class AppTheme {
  static const Color primary = Color(0xFF4EA8DE);       // Primary Blue (Brand)
  static const Color primaryHover = Color(0xFF3D8CC4);
  static const Color skyBlue = Color(0xFFBEE3F8);       // Sky Blue – Container, Labels
  static const Color iceBlue = Color(0xFFEAF6FF);      // Ice Blue – Surface
  static const Color navy = Color(0xFF1D3557);        // Brand Navy
  static const Color navyLight = Color(0xFF243D5C);   // Login-Gradient, Form-Fill
  static const Color navyDark = Color(0xFF152840);    // Login-Gradient
  static const Color headerBg = navy;
  static const Color surfaceBg = iceBlue;
  static const Color textPrimary = navy;
  static const Color textSecondary = Color(0xFF5A6B7A); // Navy-nah für Konsistenz
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFFD1E5F0);       // Hellblau passend zu Ice Blue
  static const Color errorBg = Color(0xFFFFF5F5);
  static const Color errorBorder = Color(0xFFFFCCCC);
  static const Color error = Color(0xFFB71C1C);         // SnackBar, Fehler-Hintergründe
  static const Color errorVivid = Color(0xFFFF5252);  // Input-Border bei Fehler
  static const Color errorLight = Color(0xFFFF8A80);    // Fehler-Text/Icon auf dunklem Grund

  /// ROT als Ausnahme – Löschen, gefährliche Aktionen. Diese Buttons bleiben rot!
  /// Nicht durch primary ersetzen. Z.B.: „Menü leeren“, „Löschen“, „Abbrechen“ (destruktiv).
  static const Color dangerButton = Color(0xFFB71C1C);
  /// Grau für sekundäre Header-Buttons (z.B. „Neuer Menüpunkt“)
  static const Color headerButtonSecondary = Color(0xFF6C757D);

  /// Einheitlicher Modul-Header: Weißer Hintergrund, hellblaue Chevron + Titel links,
  /// optionale Aktionen rechts. Design wie Menü-Verwaltung.
  static PreferredSizeWidget buildModuleAppBar({
    String? title,
    Widget? titleWidget,
    VoidCallback? onBack,
    IconData leadingIcon = Icons.arrow_back,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: primary,
      elevation: 1,
      scrolledUnderElevation: 1,
      leading: onBack != null
          ? IconButton(
              icon: Icon(leadingIcon),
              onPressed: onBack,
              color: primary,
            )
          : null,
      title: titleWidget ??
          (title != null
              ? Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                )
              : null),
      actions: actions,
      bottom: bottom,
      iconTheme: IconThemeData(color: primary),
      titleTextStyle: TextStyle(
        color: primary,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
    );
  }

  /// Sekundärer Header-Button (grau, abgerundet)
  static Widget headerSecondaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: headerButtonSecondary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  /// Primärer Header-Button (hellblau, abgerundet)
  static Widget headerPrimaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        brightness: Brightness.light,
        surface: surfaceBg,
      ).copyWith(
        error: error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: surfaceBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: headerBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}
