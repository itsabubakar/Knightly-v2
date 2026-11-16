import 'package:material_ui/material_ui.dart';

/// Knightly's "Flare" palette: warm surfaces and a vivid orange accent.
abstract final class Flare() {
  /// The accent: buttons, highlights, progress.
  static const orange = Color(0xFFFE7201);

  /// The accent in light mode, a little darker so that white text on it stays readable.
  static const orangeDeep = Color(0xFFE86400);

  /// A soft orange for tinted backgrounds (selected chips, highlighted cards).
  static const peach = Color(0xFFFEC18A);

  static const green = Color(0xFF30B469);
  static const red = Color(0xFFDF5555);

  // Dark mode: warm charcoal surfaces, from darkest to lightest.
  static const darkLowest = Color(0xFF110D0A);
  static const darkSurface = Color(0xFF17120F);
  static const darkLow = Color(0xFF1E1814);
  static const darkContainer = Color(0xFF251E19);
  static const darkHigh = Color(0xFF2D251F);
  static const darkHighest = Color(0xFF372D26);
  static const darkOnSurface = Color(0xFFF6EEE7);
  static const darkOnSurfaceVariant = Color(0xFFC9B9AC);
  static const darkOutline = Color(0xFF6A5748);
  static const darkOutlineVariant = Color(0xFF3E332B);

  // Light mode: cream surfaces.
  static const lightLowest = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFEF4EB);
  static const lightLow = Color(0xFFFDF8F4);
  static const lightContainer = Color(0xFFFCEFE4);
  static const lightHigh = Color(0xFFFCE9DA);
  static const lightHighest = Color(0xFFF7DDC9);
  static const lightOnSurface = Color(0xFF1C1A22);
  static const lightOnSurfaceVariant = Color(0xFF5E5650);
  static const lightOutline = Color(0xFFA8968A);
  static const lightOutlineVariant = Color(0xFFE6D5C8);

  /// Corner radius of Knightly's cards and buttons.
  static const radius = BorderRadius.all(Radius.circular(16.0));
}

/// The Flare [ColorScheme] for [brightness]: the Material roles generated from the orange accent,
/// with Knightly's own surfaces.
ColorScheme makeFlareColorScheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final generated = ColorScheme.fromSeed(seedColor: Flare.orange, brightness: brightness);
  return generated.copyWith(
    primary: isDark ? Flare.orange : Flare.orangeDeep,
    onPrimary: Colors.white,
    tertiary: Flare.green,
    onTertiary: Colors.white,
    error: Flare.red,
    onError: Colors.white,
    surface: isDark ? Flare.darkSurface : Flare.lightSurface,
    surfaceDim: isDark ? Flare.darkLowest : Flare.lightHigh,
    surfaceBright: isDark ? Flare.darkHighest : Flare.lightLowest,
    surfaceContainerLowest: isDark ? Flare.darkLowest : Flare.lightLowest,
    surfaceContainerLow: isDark ? Flare.darkLow : Flare.lightLow,
    surfaceContainer: isDark ? Flare.darkContainer : Flare.lightContainer,
    surfaceContainerHigh: isDark ? Flare.darkHigh : Flare.lightHigh,
    surfaceContainerHighest: isDark ? Flare.darkHighest : Flare.lightHighest,
    onSurface: isDark ? Flare.darkOnSurface : Flare.lightOnSurface,
    onSurfaceVariant: isDark ? Flare.darkOnSurfaceVariant : Flare.lightOnSurfaceVariant,
    outline: isDark ? Flare.darkOutline : Flare.lightOutline,
    outlineVariant: isDark ? Flare.darkOutlineVariant : Flare.lightOutlineVariant,
    surfaceTint: Colors.transparent,
  );
}

/// Knightly's component styles on Android: rounder cards and bolder buttons and navigation.
ThemeData applyFlareComponentThemes(ThemeData theme) {
  final scheme = theme.colorScheme;
  const buttonShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14.0))),
  );
  const buttonText = WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 15));
  const buttonSize = WidgetStatePropertyAll(Size(64, 48));
  return theme.copyWith(
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: Flare.radius),
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: buttonShape, textStyle: buttonText, minimumSize: buttonSize),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(shape: buttonShape, textStyle: buttonText, minimumSize: buttonSize),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
  );
}
