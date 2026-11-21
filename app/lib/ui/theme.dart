import 'package:material_ui/material_ui.dart';

/// Design tokens of the Kovetz design system (see docs/design/stitch).
/// The interface font is bundled, so no network is needed to draw text.
const interfaceFont = 'Manrope';

/// Colours outside the Material scheme: process feedback only.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;

  static const light = StatusColors(
    success: Color(0xFF2E6F4E),
    successContainer: Color(0xFFD3EFE0),
    onSuccessContainer: Color(0xFF0E3B25),
    warningContainer: Color(0xFFF7E5CC),
    onWarningContainer: Color(0xFF472A06),
  );

  static const dark = StatusColors(
    success: Color(0xFF8FD3B0),
    successContainer: Color(0xFF1E4F3D),
    onSuccessContainer: Color(0xFFC8FCE3),
    warningContainer: Color(0xFF4A3818),
    onWarningContainer: Color(0xFFF7E5CC),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Spacing and shape scale.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const section = 32.0;
  static const pageMargin = 20.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF376754),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD3E7DC),
  onPrimaryContainer: Color(0xFF112E22),
  secondary: Color(0xFF506259),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE1F6EA),
  onSecondaryContainer: Color(0xFF1E332A),
  tertiary: Color(0xFF693837),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFEDEB),
  onTertiaryContainer: Color(0xFF350F0F),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF7F7F3),
  onSurface: Color(0xFF191C1B),
  surfaceDim: Color(0xFFE2E3DE),
  surfaceBright: Color(0xFFFCFDF9),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF1F2ED),
  surfaceContainer: Color(0xFFEBECE7),
  surfaceContainerHigh: Color(0xFFE4E6E0),
  surfaceContainerHighest: Color(0xFFDDDFD9),
  onSurfaceVariant: Color(0xFF454D48),
  outline: Color(0xFF717974),
  outlineVariant: Color(0xFFC8D0CA),
  inverseSurface: Color(0xFF2E312F),
  onInverseSurface: Color(0xFFF0F1EE),
  inversePrimary: Color(0xFF9FD1BA),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9FD1BA),
  onPrimary: Color(0xFF003828),
  primaryContainer: Color(0xFF1E4F3D),
  onPrimaryContainer: Color(0xFFC8FCE3),
  secondary: Color(0xFFB7CBC0),
  onSecondary: Color(0xFF22342C),
  secondaryContainer: Color(0xFF384B42),
  onSecondaryContainer: Color(0xFFE1F6EA),
  tertiary: Color(0xFFFBB5B2),
  onTertiary: Color(0xFF4F2322),
  tertiaryContainer: Color(0xFF6A3937),
  onTertiaryContainer: Color(0xFFFFEDEB),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF121513),
  onSurface: Color(0xFFE4E6E2),
  surfaceDim: Color(0xFF0E110F),
  surfaceBright: Color(0xFF343835),
  surfaceContainerLowest: Color(0xFF0C0F0D),
  surfaceContainerLow: Color(0xFF191D1A),
  surfaceContainer: Color(0xFF1F2421),
  surfaceContainerHigh: Color(0xFF292E2B),
  surfaceContainerHighest: Color(0xFF333835),
  onSurfaceVariant: Color(0xFFBFC8C2),
  outline: Color(0xFF8A938D),
  outlineVariant: Color(0xFF3D4640),
  inverseSurface: Color(0xFFE4E6E2),
  onInverseSurface: Color(0xFF2E312F),
  inversePrimary: Color(0xFF376754),
);

TextStyle _style(
  double size,
  FontWeight weight,
  double height, [
  double spacing = 0,
]) => TextStyle(
  fontFamily: interfaceFont,
  fontSize: size,
  fontWeight: weight,
  height: height / size,
  letterSpacing: spacing,
);

/// Type scale from the design system, mapped onto Material text roles.
final _textTheme = TextTheme(
  displayLarge: _style(32, FontWeight.w700, 38, -0.5),
  displayMedium: _style(28, FontWeight.w700, 34, -0.4),
  headlineLarge: _style(24, FontWeight.w700, 30, -0.3),
  headlineMedium: _style(20, FontWeight.w600, 26, -0.2),
  titleLarge: _style(18, FontWeight.w600, 24),
  titleMedium: _style(16, FontWeight.w600, 22),
  titleSmall: _style(15, FontWeight.w600, 20, 0.1),
  bodyLarge: _style(16, FontWeight.w400, 24),
  bodyMedium: _style(14, FontWeight.w400, 20, 0.1),
  bodySmall: _style(12, FontWeight.w400, 16, 0.2),
  labelLarge: _style(15, FontWeight.w600, 20, 0.1),
  labelMedium: _style(13, FontWeight.w600, 18, 0.2),
  labelSmall: _style(11, FontWeight.w600, 14, 0.3),
);

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
  final text = _textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
    fontFamily: interfaceFont,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: interfaceFont,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [
      brightness == Brightness.dark ? StatusColors.dark : StatusColors.light,
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      labelStyle: text.labelMedium,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
  );
}
