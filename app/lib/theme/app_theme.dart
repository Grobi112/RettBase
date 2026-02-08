import 'package:flutter/material.dart';

/// Design wie Web-App (rettbase CSS): #1e1f26, #0ea5e9, #f4f5f7, Segoe-UI-Stil
class AppTheme {
  static const Color primary = Color(0xFF0EA5E9);
  static const Color primaryHover = Color(0xFF0B93D0);
  static const Color headerBg = Color(0xFF1E1F26);
  static const Color surfaceBg = Color(0xFFF4F5F7);
  static const Color textPrimary = Color(0xFF1E1F26);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color errorBg = Color(0xFFFFF5F5);
  static const Color errorBorder = Color(0xFFFFCCCC);
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
        shadowColor: Colors.black.withOpacity(0.12),
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
