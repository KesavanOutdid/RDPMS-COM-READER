import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional light-themed desktop application design system.
/// Inspired by industry-standard CAN tools (PCAN-View, Vector CANalyzer, BusMaster).
class AppTheme {
  AppTheme._();

  // ── Brand & Accent Colors ──
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color accentCyan = Color(0xFF0D9488);
  static const Color accentOrange = Color(0xFFD97706);

  // ── Background Hierarchy ──
  static const Color bgDarkest = Color(0xFFEEF1F6);
  static const Color bgDark = Color(0xFFF1F3F8);
  static const Color bgMedium = Color(0xFFF5F7FA);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgInput = Color(0xFFFFFFFF);
  static const Color bgElevated = Color(0xFFFFFFFF);

  // ── Semantic Colors ──
  static const Color sentColor = Color(0xFFDC2626);
  static const Color receivedColor = Color(0xFF16A34A);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color warningColor = Color(0xFFD97706);
  static const Color successColor = Color(0xFF16A34A);
  static const Color infoColor = Color(0xFF2563EB);

  // ── Text Hierarchy ──
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textBright = Color(0xFF0F172A);

  // ── Borders & Dividers ──
  static const Color borderColor = Color(0xFFD1D5DB);
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderFocused = Color(0xFF2563EB);
  static const Color dividerColor = Color(0xFFE5E7EB);

  // ── Panel & Selection ──
  static const Color panelHeader = Color(0xFFF3F4F6);
  static const Color panelFill = Color(0xFFF9FAFB);
  static const Color selectionBlue = Color(0xFFDBEAFE);
  static const Color selectionBlueSoft = Color(0xFFEFF6FF);

  // ── Console Colors ──
  static const Color consoleBackground = Color(0xFFFFFFFF);
  static const Color consoleMeta = Color(0xFF16A34A);
  static const Color consoleRx = Color(0xFF16A34A);
  static const Color consoleTx = Color(0xFFDC2626);
  static const Color consoleText = Color(0xFF1E293B);

  // ── Shadow ──
  static const Color shadowDark = Color(0x1A000000);
  static const Color shadowMedium = Color(0x0D000000);

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme();

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
        headlineMedium: GoogleFonts.inter(
          color: textBright,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.inter(
          color: textBright,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.inter(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(color: textPrimary, fontSize: 13),
        bodyMedium: GoogleFonts.inter(color: textSecondary, fontSize: 12),
        bodySmall: GoogleFonts.inter(color: textMuted, fontSize: 11),
        labelLarge: GoogleFonts.inter(
          color: textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: borderColor),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
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
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: primaryColor, width: 1),
        ),
        hintStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: textMuted),
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 16),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderColor),
        trackColor: WidgetStateProperty.all(bgDark),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: borderColor),
        ),
        elevation: 24,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: textBright,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return bgInput;
        }),
        side: const BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(bgCard),
          elevation: WidgetStatePropertyAll(8),
        ),
      ),
    );
  }

  // ── Reusable Decorations ──

  static BoxDecoration get panelDecoration => BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor),
    boxShadow: const [
      BoxShadow(color: shadowMedium, blurRadius: 8, offset: Offset(0, 2)),
    ],
  );

  static BoxDecoration get panelDecorationFlat => BoxDecoration(
    color: bgCard,
    border: Border.all(color: borderColor),
  );

  static BoxDecoration get selectedTableRow => BoxDecoration(
    color: selectionBlue,
    border: Border.all(color: primaryColor),
  );

  static BoxDecoration get headerDecoration => const BoxDecoration(
    color: panelHeader,
    border: Border(bottom: BorderSide(color: borderColor)),
  );

  /// Subtle inner glow for focused panels.
  static BoxDecoration focusedPanel({Color? glowColor}) => BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: glowColor ?? borderFocused, width: 1),
    boxShadow: [
      BoxShadow(
        color: (glowColor ?? borderFocused).withValues(alpha: 0.1),
        blurRadius: 12,
        offset: const Offset(0, 0),
      ),
    ],
  );
}
