// Tema centralizado de la aplicación.
// Todos los colores, tipografías y estilos se definen aquí para mantener
// consistencia visual y facilitar cambios globales.
import 'package:flutter/material.dart';

/// Paleta de colores corporativa Geoflora.
/// Extraída directamente de logo_geoflora.png e icono.png.
/// Azul profundo #005286 (primario), Cian #00AFD4 (acento), Neutros claros.
class AppColors {
  AppColors._();

  // ── Primario: Azul corporativo Geoflora (#005286) ─────────────────────────
  static const Color primary = Color(0xFF005286);
  static const Color primaryDark = Color(0xFF003D66);
  static const Color primaryDarker = Color(0xFF002444);
  static const Color primaryLight = Color(0xFFCCE4F0);
  static const Color primaryLighter = Color(0xFFEBF5FA);

  // ── Cian corporativo Geoflora (#00AFD4) ───────────────────────────────────
  static const Color cyan = Color(0xFF00AFD4);
  static const Color cyanDark = Color(0xFF007A96);
  static const Color cyanLight = Color(0xFFE0F6FB);
  static const Color cyanLighter = Color(0xFFF0FBFE);

  // ── Azul medio (gradientes / hover) ───────────────────────────────────────
  static const Color midBlue = Color(0xFF057CB2);

  // ── Acento: Verde naturaleza (conservado para semántica) ──────────────────
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
  static const Color success = Color.fromARGB(255, 58, 166, 63);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color successDark = Color(0xFF1B5E20);

  static const Color warning = Color.fromARGB(255, 240, 104, 0);
  static const Color warningLight = Color(0xFFFFF7ED);
  static const Color warningDark = Color(0xFF92400E);

  static const Color error = Color.fromARGB(255, 236, 42, 42);
  static const Color errorLight = Color(0xFFFEECEC);
  static const Color errorDark = Color(0xFF8E1B1B);

  static const Color info = Color(0xFF0F5DBA);
  static const Color infoLight = Color(0xFFEAF2FF);
  static const Color infoDark = Color(0xFF0D3F85);

  // ── Bordes y divisores ─────────────────────────────────────────────────────
  static const Color border = Color(0xFFD7E0EA);
  static const Color borderLight = Color(0xFFEAF0F6);

  // ── Footer / fondos oscuros ────────────────────────────────────────────────
  static const Color dark = Color(0xFF0B1628);
  static const Color darkMuted = Color(0xFF1B2B42);

  // ── Colores específicos para gráficas ─────────────────────────────────────
  static const Color chartPositive = Color(0xFF00A86B);
  static const Color chartNegative = Color(0xFFE53935);
  static const Color chartBalance = Color(0xFF005286);
  static const Color chartCutAverage = Color(0xFF057CB2);
  static const Color chartCutFinal = Color(0xFFFF8F00);

  // ── Paleta para gráficas ───────────────────────────────────────────────────
  static const List<Color> chartPalette = [
    Color(0xFF005286), // azul corporativo
    Color(0xFF00AFD4), // cian corporativo
    Color(0xFF00A86B), // verde intenso
    Color(0xFFFF8F00), // naranja fuerte
    Color(0xFFE53935), // rojo intenso
    Color(0xFF057CB2), // azul medio
    Color(0xFF7CB342), // lima
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
    colors: [Color.fromARGB(255, 73, 198, 79), Color(0xFF1B5E20)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient infoCard = LinearGradient(
    colors: [Color.fromARGB(255, 33, 121, 228), Color(0xFF0D3F85)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningCard = LinearGradient(
    colors: [
      Color.fromARGB(255, 255, 147, 65),
      Color.fromARGB(255, 185, 77, 10)
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorCard = LinearGradient(
    colors: [Color.fromARGB(255, 227, 76, 76), Color(0xFF8E1B1B)],
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
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.background,
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
