import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Classic desktop-inspired theme tuned for dense serial monitor workflows.
class AppTheme {
  AppTheme._();

  static const Color primaryColor = Color(0xFF2D73C7);
  static const Color primaryDark = Color(0xFF1F5DA7);
  static const Color accentCyan = Color(0xFF3B89E0);

  static const Color bgDarkest = Color(0xFFE9EDF3);
  static const Color bgDark = Color(0xFFDDE4EC);
  static const Color bgMedium = Color(0xFFC9D3DE);
  static const Color bgCard = Color(0xFFF7F9FC);
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgInput = Color(0xFFFFFFFF);

  static const Color sentColor = Color(0xFF2A56E8);
  static const Color receivedColor = Color(0xFF2E8E2F);
  static const Color errorColor = Color(0xFFC83B3B);
  static const Color warningColor = Color(0xFFBF7A1A);

  static const Color textPrimary = Color(0xFF1B2733);
  static const Color textSecondary = Color(0xFF4E5E70);
  static const Color textMuted = Color(0xFF7B8793);

  static const Color borderColor = Color(0xFFAEB9C6);
  static const Color borderLight = Color(0xFFD7DEE8);
  static const Color dividerColor = Color(0xFFC4CCD8);

  static const Color panelHeader = Color(0xFFE7EDF4);
  static const Color panelFill = Color(0xFFF4F7FA);
  static const Color selectionBlue = Color(0xFF3B95F2);
  static const Color selectionBlueSoft = Color(0xFFCEE5FF);
  static const Color consoleBackground = Color(0xFFFFFFFF);
  static const Color consoleMeta = Color(0xFF2E8E2F);
  static const Color consoleRx = Color(0xFFFF4A39);
  static const Color consoleTx = Color(0xFF2A56E8);
  static const Color consoleText = Color(0xFF267C28);

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.openSansTextTheme();

    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentCyan,
        surface: bgSurface,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: bgDarkest,
      textTheme: baseTextTheme.copyWith(
        headlineMedium: GoogleFonts.openSans(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.openSans(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.openSans(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.openSans(color: textPrimary, fontSize: 14),
        bodyMedium: GoogleFonts.openSans(color: textSecondary, fontSize: 13),
        bodySmall: GoogleFonts.openSans(color: textMuted, fontSize: 12),
        labelLarge: GoogleFonts.openSans(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: borderColor),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: GoogleFonts.openSans(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.openSans(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: bgInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(color: primaryColor, width: 1.2),
        ),
        hintStyle: GoogleFonts.robotoMono(fontSize: 12, color: textMuted),
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 18),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderColor),
        trackColor: WidgetStateProperty.all(bgDark),
        thickness: WidgetStateProperty.all(10),
        radius: Radius.zero,
      ),
    );
  }

  static BoxDecoration get panelDecoration => BoxDecoration(
    color: bgCard,
    border: Border.all(color: borderColor),
    boxShadow: const [
      BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
  );

  static BoxDecoration get selectedTableRow => BoxDecoration(
    color: selectionBlue,
    border: Border.all(color: primaryDark),
  );
}
