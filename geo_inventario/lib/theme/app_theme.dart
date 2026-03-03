// Tema centralizado de la aplicación.
// Todos los colores, tipografías y estilos se definen aquí para mantener
// consistencia visual y facilitar cambios globales.
import 'package:flutter/material.dart';

/// Paleta de colores corporativa Geoflora.
/// Basada en la guía de marca oficial:
///   Pantone 7462 C → #005286  (azul profundo — primario)
///   Pantone 7460 C → #007DAD  (azul medio — gradientes)
///   Pantone 638 C  → #00AFD3  (cian — acento)
///   Pantone 184 C  → #EA516D  (rosa coral — brand accent)
///   Pantone 177 C  → #F08592  (rosa claro — brand accent light)
///   Pantone 7401 C → #FFE3AB  (champagne cálido — brand warm)
class AppColors {
  AppColors._();

  // ── Primario: Azul profundo Geoflora — Pantone 7462 C ─────────────────────
  static const Color primary = Color(0xFF005286);
  static const Color primaryDark = Color(0xFF003D66);
  static const Color primaryDarker = Color(0xFF002444);
  static const Color primaryLight = Color(0xFFCCE4F0);
  static const Color primaryLighter = Color(0xFFEBF5FA);

  // ── Azul medio — Pantone 7460 C ───────────────────────────────────────────
  static const Color midBlue = Color(0xFF007DAD);

  // ── Cian corporativo — Pantone 638 C ──────────────────────────────────────
  static const Color cyan = Color(0xFF00AFD3);
  static const Color cyanDark = Color(0xFF006E88);
  static const Color cyanLight = Color(0xFFDEF6FC);
  static const Color cyanLighter = Color(0xFFF0FBFE);

  // ── Rosa coral — Pantone 184 C ────────────────────────────────────────────
  static const Color brandPink = Color(0xFFEA516D);
  static const Color brandPinkDark = Color(0xFFC22649);
  static const Color brandPinkLight = Color(0xFFF08592); // Pantone 177 C
  static const Color brandPinkLighter = Color(0xFFFDE8EC);

  // ── Champagne cálido — Pantone 7401 C ─────────────────────────────────────
  static const Color brandWarm = Color(0xFFFFE3AB);
  static const Color brandWarmDark = Color(0xFFC8960A);
  static const Color brandWarmLight = Color(0xFFFFF8E8);

  // ── Acento: Verde naturaleza (semántica positiva) ─────────────────────────
  static const Color accent = Color(0xFF2E7D32);
  static const Color accentDark = Color(0xFF1F5B23);
  static const Color accentLight = Color(0xFFCDEDD1);
  static const Color accentLighter = Color(0xFFEAF8EC);

  // ── Superficies ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF0F4F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEAF2F7);
  static const Color surfaceBlue = Color(0xFFE0F3FA);

  // ── Textos ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF94A3B8);

  // ── Semánticos ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF3AA63F);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color successDark = Color(0xFF1B5E20);

  static const Color warning = Color(0xFFF06800);
  static const Color warningLight = Color(0xFFFFF7ED);
  static const Color warningDark = Color(0xFF92400E);

  static const Color error = Color(0xFFEC2A2A);
  static const Color errorLight = Color(0xFFFEECEC);
  static const Color errorDark = Color(0xFF8E1B1B);

  static const Color info = Color(0xFF0F5DBA);
  static const Color infoLight = Color(0xFFEAF2FF);
  static const Color infoDark = Color(0xFF0D3F85);

  // ── Bordes y divisores ─────────────────────────────────────────────────────
  static const Color border = Color(0xFFD7E0EA);
  static const Color borderLight = Color(0xFFEAF0F6);

  // ── Fondos oscuros / navy Geoflora ────────────────────────────────────────
  static const Color dark = Color(0xFF0D1B2E);
  static const Color darkMuted = Color(0xFF1A2C44);

  // ── Colores específicos para gráficas ─────────────────────────────────────
  static const Color chartPositive = Color(0xFF00A86B);
  static const Color chartNegative = Color(0xFFEA516D); // brand pink
  static const Color chartBalance = Color(0xFF005286);
  static const Color chartCutAverage = Color(0xFF007DAD); // brand mid-blue
  static const Color chartCutFinal = Color(0xFFF06800);

  // ── Paleta para gráficas (orden marca Geoflora) ───────────────────────────
  static const List<Color> chartPalette = [
    Color(0xFF005286), // azul profundo  — Pantone 7462 C
    Color(0xFF007DAD), // azul medio     — Pantone 7460 C
    Color(0xFF00AFD3), // cian           — Pantone 638 C
    Color(0xFFEA516D), // rosa coral     — Pantone 184 C
    Color(0xFFF08592), // rosa claro     — Pantone 177 C
    Color(0xFFFFE3AB), // champagne      — Pantone 7401 C
    Color(0xFF00A86B), // verde semántico
    Color(0xFF263238), // grafito
  ];

  // ── Medallas de ranking ────────────────────────────────────────────────────
  static const Color medalGold = Color(0xFFFFC107);
  static const Color medalSilver = Color(0xFF9E9E9E);
  static const Color medalBronze = Color(0xFF8D6E63);
}

/// Espaciados estándar reutilizables.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

/// Radios de borde estándar.
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

/// Sombras reutilizables.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];

  static List<BoxShadow> colored(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];
}

/// Gradientes reutilizables (solo para gráficos y elementos decorativos).
class AppGradients {
  AppGradients._();

  /// Gradiente corporativo: azul profundo → cian (refleja el logo Geoflora).
  static const LinearGradient primary = LinearGradient(
    colors: [AppColors.primary, AppColors.midBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente banner hero: navy → cian — identidad corporativa completa.
  static const LinearGradient hero = LinearGradient(
    colors: [AppColors.primary, AppColors.midBlue, AppColors.cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accent = LinearGradient(
    colors: [AppColors.cyan, AppColors.cyanDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successCard = LinearGradient(
    colors: [AppColors.success, AppColors.successDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient infoCard = LinearGradient(
    colors: [AppColors.info, AppColors.infoDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningCard = LinearGradient(
    colors: [AppColors.warning, AppColors.warningDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorCard = LinearGradient(
    colors: [AppColors.error, AppColors.errorDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente brand pink — Pantone 184 C → Pantone 177 C.
  static const LinearGradient brandPinkCard = LinearGradient(
    colors: [AppColors.brandPink, AppColors.brandPinkDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente champagne cálido — Pantone 7401 C (KPIs destacados).
  static const LinearGradient brandWarmCard = LinearGradient(
    colors: [AppColors.brandWarm, AppColors.brandWarmDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Tema principal de la aplicación.
class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.cyan,
        onSecondary: Colors.white,
        tertiary: AppColors.brandPink,
        onTertiary: Colors.white,
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.background,
        error: AppColors.error,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,

      // AppBar — azul corporativo profundo con texto blanco
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        shadowColor: Color(0x44000000),
      ),

      // Card
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        color: AppColors.surface,
        margin: EdgeInsets.zero,
      ),

      // ElevatedButton
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.textDisabled,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // InputDecoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: const TextStyle(color: AppColors.textDisabled, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        selectedColor: AppColors.primaryLight,
        labelStyle: const TextStyle(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),

      // TabBar — etiquetas blancas, indicador cian corporativo
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Color(0xAAFFFFFF),
        indicatorColor: AppColors.cyan,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        indicatorSize: TabBarIndicatorSize.tab,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        contentTextStyle: const TextStyle(fontSize: 14),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),
    );
  }
}

/// Widgets utilitarios compartidos del tema.
extension BuildContextTheme on BuildContext {
  void showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void showInfoSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.info,
      ),
    );
  }

  void showWarningSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }
}
