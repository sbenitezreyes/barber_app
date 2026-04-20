import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

// ─────────────────────────────────────────────────────────────
//  PALETA "LA NAVAJA" — Luxury Underground Grooming
//  Negro obsidiana · Oro brass · Crema cálida
// ─────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Fondos
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF111116);
  static const surfaceElevated = Color(0xFF18181E);
  static const surfaceInput = Color(0xFF1E1E26);

  // Primario — oro / brass
  static const gold = Color(0xFFC9A84C);
  static const goldLight = Color(0xFFE4C87A);
  static const goldDark = Color(0xFF9A7E3A);
  static const goldSubtle = Color(0x1AC9A84C); // 10 % opacidad

  // Acento — teal (identidad de marca original)
  static const teal = Color(0xFF0CC4D0);
  static const tealSubtle = Color(0x1A0CC4D0);

  // Texto
  static const textPrimary = Color(0xFFF2EEE8); // blanco crema cálido
  static const textSecondary = Color(0xFF8A8590);
  static const textTertiary = Color(0xFF504C56);

  // Bordes
  static const borderSubtle = Color(0x0DFFFFFF); //  5 %
  static const borderMedium = Color(0x1AFFFFFF); // 10 %
  static const borderAccent = Color(0x33C9A84C); // gold 20 %

  // Estados
  static const success = Color(0xFF2ECF88);
  static const warning = Color(0xFFF5A623);
  static const error = Color(0xFFE55252);

  // Navegación / bottom bar
  static const navBackground = Color(0xFF111116);
  static const navIndicator = Color(0x26C9A84C); // gold 15 %
}

// ─────────────────────────────────────────────────────────────
//  TIPOGRAFÍA
//  Display  → Playfair Display (serif elegante — marca)
//  UI       → Figtree (grotesque limpio — interface)
// ─────────────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  // Display / títulos de marca
  static TextStyle display({
    double size = 32,
    FontWeight weight = FontWeight.w700,
  }) => TextStyle(
    fontFamily: 'Playfair Display',
    fontSize: size,
    fontWeight: weight,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  // UI general
  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: 'Figtree',
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.textPrimary,
    height: 1.4,
  );

  // Alias útiles
  static TextStyle get headline => display(size: 28, weight: FontWeight.w700);
  static TextStyle get title => ui(size: 18, weight: FontWeight.w600);
  static TextStyle get subtitle => ui(size: 15, weight: FontWeight.w500);
  static TextStyle get body => ui(size: 14);
  static TextStyle get caption => ui(size: 12, color: AppColors.textSecondary);
  static TextStyle get label =>
      ui(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary);
  static TextStyle get button => ui(size: 15, weight: FontWeight.w600);
  static TextStyle get price => const TextStyle(
    fontFamily: 'Figtree',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.gold,
    letterSpacing: 0.5,
  );
}

// ─────────────────────────────────────────────────────────────
//  DECORACIONES REUTILIZABLES
// ─────────────────────────────────────────────────────────────

class AppDecorations {
  AppDecorations._();

  static BoxDecoration card({Color? color, bool gold = false}) => BoxDecoration(
    color: color ?? AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: gold ? AppColors.borderAccent : AppColors.borderSubtle,
      width: 1,
    ),
  );

  static BoxDecoration surface({BorderRadius? radius}) => BoxDecoration(
    color: AppColors.surfaceElevated,
    borderRadius: radius ?? BorderRadius.circular(12),
    border: Border.all(color: AppColors.borderSubtle),
  );

  static BoxDecoration pill({Color? color}) => BoxDecoration(
    color: color ?? AppColors.gold,
    borderRadius: BorderRadius.circular(100),
  );

  // Gradiente de fondo para splash / hero sections
  static const BoxDecoration splashClient = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF0A0A0C), Color(0xFF141018), Color(0xFF0A0A0C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const BoxDecoration splashBarber = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF0A0A0C), Color(0xFF100E14), Color(0xFF0A0A0C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  BOTONES — estilos compartidos
// ─────────────────────────────────────────────────────────────

class AppButtonStyles {
  AppButtonStyles._();

  static ButtonStyle primary = ElevatedButton.styleFrom(
    backgroundColor: AppColors.gold,
    foregroundColor: AppColors.background,
    minimumSize: const Size(double.infinity, 52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    elevation: 0,
    textStyle: AppTextStyles.button,
  );

  static ButtonStyle secondary = OutlinedButton.styleFrom(
    foregroundColor: AppColors.textPrimary,
    minimumSize: const Size(double.infinity, 52),
    side: const BorderSide(color: AppColors.borderMedium),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    textStyle: AppTextStyles.button,
  );

  static ButtonStyle ghost = TextButton.styleFrom(
    foregroundColor: AppColors.gold,
    textStyle: AppTextStyles.button,
  );
}

// ─────────────────────────────────────────────────────────────
//  INPUTS — decoración de campos de texto
// ─────────────────────────────────────────────────────────────

InputDecorationTheme _buildInputTheme() => InputDecorationTheme(
  filled: true,
  fillColor: AppColors.surfaceInput,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.error),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.error, width: 1.5),
  ),
  labelStyle: AppTextStyles.ui(size: 14, color: AppColors.textSecondary),
  hintStyle: AppTextStyles.ui(size: 14, color: AppColors.textTertiary),
  prefixIconColor: WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? AppColors.gold
        : AppColors.textTertiary,
  ),
);

// ─────────────────────────────────────────────────────────────
//  THEME DATA PRINCIPAL
// ─────────────────────────────────────────────────────────────

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: AppColors.gold,
    onPrimary: AppColors.background,
    secondary: AppColors.teal,
    onSecondary: AppColors.background,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.error,
    onError: Colors.white,
    outline: AppColors.borderSubtle,
    surfaceContainerHighest: AppColors.surfaceElevated,
  );

  final base = ThemeData.dark().textTheme
      .apply(fontFamily: 'Figtree')
      .copyWith(
        displayLarge: AppTextStyles.display(size: 32),
        displayMedium: AppTextStyles.display(size: 28),
        displaySmall: AppTextStyles.display(size: 24),
        headlineLarge: AppTextStyles.display(size: 22),
        headlineMedium: AppTextStyles.display(size: 20),
        headlineSmall: AppTextStyles.display(size: 18),
        titleLarge: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
        titleMedium: AppTextStyles.ui(size: 16, weight: FontWeight.w600),
        titleSmall: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
        bodyLarge: AppTextStyles.ui(size: 16),
        bodyMedium: AppTextStyles.ui(size: 14),
        bodySmall: AppTextStyles.ui(size: 12),
        labelLarge: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
        labelMedium: AppTextStyles.ui(size: 12, weight: FontWeight.w600),
        labelSmall: AppTextStyles.ui(size: 11, weight: FontWeight.w600),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base,

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),

    // Bottom Navigation (Material 3 NavigationBar)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.navBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: AppColors.navIndicator,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      labelTextStyle: WidgetStateTextStyle.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return AppTextStyles.ui(
          size: 11,
          weight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? AppColors.gold : AppColors.textTertiary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(
          color: active ? AppColors.gold : AppColors.textTertiary,
          size: 22,
        );
      }),
    ),

    // Cards
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      margin: EdgeInsets.zero,
    ),

    // Inputs
    inputDecorationTheme: _buildInputTheme(),

    // Elevated Button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: AppButtonStyles.primary,
    ),

    // Outlined Button
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: AppButtonStyles.secondary,
    ),

    // Text Button
    textButtonTheme: TextButtonThemeData(style: AppButtonStyles.ghost),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),

    // Bottom Sheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: AppTextStyles.ui(size: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),

    // Tab Bar
    tabBarTheme: TabBarThemeData(
      labelStyle: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
      unselectedLabelStyle: AppTextStyles.ui(size: 14),
      labelColor: AppColors.background,
      unselectedLabelColor: AppColors.textSecondary,
      indicator: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(10),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
    ),

    // Progress Indicator
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gold,
    ),

    // Floating Action Button
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.gold,
      foregroundColor: AppColors.background,
      elevation: 4,
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceInput,
      selectedColor: AppColors.goldSubtle,
      side: const BorderSide(color: AppColors.borderSubtle),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: AppTextStyles.ui(size: 12),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
      contentTextStyle: AppTextStyles.ui(
        size: 14,
        color: AppColors.textSecondary,
      ),
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.gold
            : AppColors.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.goldSubtle
            : AppColors.surfaceInput,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    // Checkbox
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.gold
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(AppColors.background),
      side: const BorderSide(color: AppColors.borderMedium, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  CALENDARIO — estilos compartidos (table_calendar)
// ─────────────────────────────────────────────────────────────

class AppCalendarStyles {
  AppCalendarStyles._();

  static CalendarStyle get calendarStyle => CalendarStyle(
    outsideDaysVisible: false,
    todayDecoration: BoxDecoration(
      color: Colors.transparent,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.gold, width: 1.5),
    ),
    selectedDecoration: const BoxDecoration(
      color: AppColors.gold,
      shape: BoxShape.circle,
    ),
    markerDecoration: const BoxDecoration(
      color: AppColors.gold,
      shape: BoxShape.circle,
    ),
    weekendTextStyle: AppTextStyles.ui(
      size: 13,
      color: AppColors.textSecondary,
    ),
    defaultTextStyle: AppTextStyles.ui(size: 13),
    outsideTextStyle: AppTextStyles.ui(size: 13, color: AppColors.textTertiary),
    todayTextStyle: AppTextStyles.ui(
      size: 13,
      weight: FontWeight.w700,
      color: AppColors.gold,
    ),
    selectedTextStyle: AppTextStyles.ui(
      size: 13,
      weight: FontWeight.w700,
      color: AppColors.background,
    ),
    markerSize: 4,
    markersMaxCount: 3,
    cellMargin: const EdgeInsets.all(4),
  );

  static HeaderStyle get headerStyle => HeaderStyle(
    formatButtonVisible: false,
    titleCentered: true,
    titleTextStyle: AppTextStyles.display(size: 16),
    leftChevronIcon: const Icon(
      Icons.chevron_left,
      color: AppColors.gold,
      size: 20,
    ),
    rightChevronIcon: const Icon(
      Icons.chevron_right,
      color: AppColors.gold,
      size: 20,
    ),
    headerPadding: const EdgeInsets.symmetric(vertical: 8),
  );

  static DaysOfWeekStyle get daysOfWeekStyle => DaysOfWeekStyle(
    weekdayStyle: AppTextStyles.ui(
      size: 11,
      weight: FontWeight.w600,
      color: AppColors.textTertiary,
    ).copyWith(letterSpacing: 0.4),
    weekendStyle: AppTextStyles.ui(
      size: 11,
      weight: FontWeight.w600,
      color: AppColors.textTertiary,
    ).copyWith(letterSpacing: 0.4),
  );
}
