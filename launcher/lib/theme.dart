import 'package:flutter/material.dart';

/// 设计令牌 —— 对齐参考项目 LanzhuToolNX 的 `globals.css`。
///
/// 那套设计的要点：
/// - 浅色为主：背景淡蓝灰、卡片近白、主色是低饱和柔粉（hsl(4 85% 77%)）
/// - 深色可切：背景 hsl(220 20% 10%)、卡片 hsl(220 17% 14%)
/// - 圆角 12（xl 16），阴影很轻、分多层
/// - 背景是「左上蓝光 + 右上紫光 + 竖向渐变」的径向叠加
/// - 字体走 Microsoft YaHei UI，等宽走 Cascadia Mono / Consolas
///
/// Flutter 这边没有 CSS 变量，所以用 [AppColors] 承载同一组令牌，
/// 再由 [buildTheme] 映射成 ColorScheme。
class AppColors {
  const AppColors._({
    required this.background,
    required this.foreground,
    required this.card,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.onAccent,
    required this.destructive,
    required this.onDestructive,
    required this.success,
    required this.border,
    required this.input,
    required this.ring,
    required this.glowA,
    required this.glowB,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color onAccent;
  final Color destructive;
  final Color onDestructive;
  final Color success;
  final Color border;
  final Color input;
  final Color ring;

  /// 背景左上 / 右上的两团光。
  final Color glowA;
  final Color glowB;

  bool get isDark => background.computeLuminance() < 0.2;

  static const light = AppColors._(
    background: Color(0xFFF0F4F8),
    foreground: Color(0xFF22292F),
    card: Color(0xFFFCFDFE),
    primary: Color(0xFFF7A29C),
    onPrimary: Color(0xFF1E2429),
    secondary: Color(0xFFE4EBF1),
    onSecondary: Color(0xFF333D45),
    muted: Color(0xFFE9EEF3),
    mutedForeground: Color(0xFF667079),
    accent: Color(0xFFDCE7F2),
    onAccent: Color(0xFF333D45),
    destructive: Color(0xFFE24A4A),
    onDestructive: Color(0xFFF7FAFC),
    success: Color(0xFF1E9E6A),
    border: Color(0xFFC9D4DE),
    input: Color(0xFFC9D4DE),
    ring: Color(0xFFE4695E),
    glowA: Color(0xE6D6E8F7),
    glowB: Color(0xBFEDE4F7),
  );

  static const dark = AppColors._(
    background: Color(0xFF14171D),
    foreground: Color(0xFFE5EAEF),
    card: Color(0xF01C2028),
    primary: Color(0xFFF58C8C),
    onPrimary: Color(0xFF1E2429),
    secondary: Color(0xFF2B3139),
    onSecondary: Color(0xFFE1E7EC),
    muted: Color(0xFF262C34),
    mutedForeground: Color(0xFF9BA5B0),
    accent: Color(0xFF313841),
    onAccent: Color(0xFFE5EAEF),
    destructive: Color(0xFFD25C5C),
    onDestructive: Color(0xFFFFFFFF),
    success: Color(0xFF4FC48B),
    border: Color(0xFF3A424C),
    input: Color(0xFF3E4650),
    ring: Color(0xFFF58C8C),
    glowA: Color(0x8C24405E),
    glowB: Color(0x731F3A4D),
  );
}

/// 统一圆角：参考项目 --radius 0.75rem，lg=12 / xl=16。
class AppRadius {
  const AppRadius._();
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
}

class AppFonts {
  const AppFonts._();
  static const String sans = 'Microsoft YaHei UI';
  static const String mono = 'Cascadia Mono';
}

ThemeData buildTheme(AppColors c) {
  final scheme = ColorScheme(
    brightness: c.isDark ? Brightness.dark : Brightness.light,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    error: c.destructive,
    onError: c.onDestructive,
    surface: c.card,
    onSurface: c.foreground,
    surfaceContainerHighest: c.muted,
    outline: c.border,
    outlineVariant: c.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    fontFamily: AppFonts.sans,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: c.foreground,
      displayColor: c.foreground,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: c.border.withValues(alpha: 0.7)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.foreground,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.foreground,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(fontFamily: AppFonts.sans, fontSize: 13.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.mutedForeground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.mutedForeground),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.isDark ? c.muted : Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(color: c.mutedForeground, fontSize: 13),
      hintStyle: TextStyle(color: c.mutedForeground.withValues(alpha: 0.75)),
      helperStyle: TextStyle(color: c.mutedForeground, fontSize: 11.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: c.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: c.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: c.ring, width: 1.4),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.isDark ? c.card : c.card.withValues(alpha: 0.82),
      indicatorColor: c.primary.withValues(alpha: 0.22),
      selectedIconTheme: IconThemeData(color: c.isDark ? c.primary : c.foreground),
      unselectedIconTheme: IconThemeData(color: c.mutedForeground),
      selectedLabelTextStyle: TextStyle(
        color: c.foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: c.mutedForeground,
        fontSize: 12,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      indicatorColor: c.primary.withValues(alpha: 0.22),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11.5, color: c.foreground),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.isDark ? c.secondary : c.foreground,
      contentTextStyle: TextStyle(color: c.isDark ? c.foreground : c.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.muted,
      selectedColor: c.primary.withValues(alpha: 0.28),
      side: BorderSide(color: c.border),
      labelStyle: TextStyle(fontSize: 12, color: c.foreground),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.isDark ? c.secondary : c.foreground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: TextStyle(
        fontSize: 11.5,
        color: c.isDark ? c.foreground : c.card,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.border),
      radius: const Radius.circular(999),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}

/// 复刻参考项目的 `--backdrop`：左上蓝光 + 右上紫光 + 竖向渐变。
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.colors, required this.child});

  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.isDark
              ? const [Color(0xFF171B22), Color(0xFF10141A)]
              : const [Color(0xFFF5F8FB), Color(0xFFEDF1F6)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -160,
            top: -200,
            child: _Glow(color: colors.glowA, size: 620),
          ),
          Positioned(
            right: -180,
            top: -220,
            child: _Glow(color: colors.glowB, size: 640),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}
