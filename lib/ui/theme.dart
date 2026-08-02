import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Seed used when the platform offers no wallpaper palette.
///
/// The logo's navy, so an Android 11 device still looks like this app rather than
/// like default Flutter blue.
const seedColor = Color(0xFF2D2361);

/// Corner radii, borrowed from the budget app's shape scale.
///
/// Three sizes and no more. Its whole look comes from using one radius per role
/// consistently — rows, then cards, then sheets — rather than picking a number
/// per widget.
abstract final class Shapes {
  /// Rows inside a card: comments, channel entries.
  static const row = 12.0;

  /// Cards that sit on the background — a post.
  static const card = 15.0;

  /// Bottom sheets, and anything that meets the screen edge.
  static const sheet = 20.0;

  /// Fully round: avatars, chips, icon buttons.
  static const pill = 100.0;
}

/// Blends white in — a tint that stays in the same hue family.
///
/// Not `withOpacity`: a translucent colour picks up whatever is behind it, which
/// on a scrolling feed is a different answer every frame.
Color lightenPastel(Color color, {double amount = 0.1}) =>
    Color.alphaBlend(Colors.white.withValues(alpha: amount), color);

/// Blends black in.
Color darkenPastel(Color color, {double amount = 0.1}) =>
    Color.alphaBlend(Colors.black.withValues(alpha: amount), color);

/// Softens a colour *away* from the current background.
///
/// Lightens in a light theme, darkens in a dark one, so one call site produces a
/// surface that reads as recessed in both. This is the trick behind the budget
/// app's tinted containers, and the reason they never need a border.
Color dynamicPastel(
  BuildContext context,
  Color color, {
  double amount = 0.1,
  bool inverse = false,
  double? amountLight,
  double? amountDark,
}) {
  final light = (amountLight ?? amount).clamp(0.0, 1.0);
  final dark = (amountDark ?? amount).clamp(0.0, 1.0);
  final isLight = Theme.of(context).brightness == Brightness.light;

  if (inverse) {
    return isLight ? darkenPastel(color, amount: dark)
                   : lightenPastel(color, amount: light);
  }
  return isLight ? lightenPastel(color, amount: light)
                 : darkenPastel(color, amount: dark);
}

/// The tinted surface a post card or sheet sits on.
Color containerColor(BuildContext context) => dynamicPastel(
      context,
      Theme.of(context).colorScheme.secondaryContainer,
      amountLight: 0.6,
      amountDark: 0.3,
    );

/// Builds the app theme from a wallpaper-derived scheme when one exists.
///
/// `dynamic_color` returns null below Android 12, so the seeded fallback is the
/// normal path on plenty of devices, not an error case.
///
/// The dynamic schemes are passed through `harmonized()` — without it, a wallpaper
/// palette and the seeded accents can clash badly, since they were never designed
/// against each other.
ThemeData buildTheme({
  required ColorScheme? dynamicScheme,
  required Brightness brightness,
}) {
  final scheme = dynamicScheme?.harmonized() ??
      ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,

    // The budget app's tap feel, applied once here instead of per-widget.
    // `constantTurbulenceSeedSplashFactory` fixes the sparkle's random seed, so
    // the same control ripples identically every time — the varying default
    // reads as a rendering glitch on a control you tap repeatedly, like a like
    // button.
    splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,

    // Flat surfaces: this is a feed, and elevation shadows on every card turn a
    // scrolling list into a field of drop shadows. Separation comes from the
    // tinted container colour instead.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Shapes.card),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    // Plain surface, not a tinted band. The title now sits on the same colour as
    // the page, so the top of the app reads as one sheet rather than a coloured
    // header stacked on a feed.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    // Pill chips with no outline — the budget app leans on fill alone to show
    // selection, which is quieter next to a wall of post text.
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide.none,
    ),
    // M3 progress indicators, and a refresh indicator that matches the scheme
    // instead of the default blue.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor:
          WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Shapes.sheet)),
      ),
      // Dimmer than Material's default: the sheet's own tint is subtle, and a
      // pale scrim leaves it competing with the feed behind it.
      modalBarrierColor: Colors.black.withValues(alpha: 0.5),
    ),
  );
}
