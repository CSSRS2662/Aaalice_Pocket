import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/font_provider.dart';
import 'pocket_accent.dart';
import 'presets/pocket_theme.dart';

/// 主题明暗偏好：浅色、深色或跟随系统。
enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// 持久化值；未知或缺失时回到跟随系统。
  static AppThemeMode fromStorage(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppThemeMode.system;
  }
}

/// 应用主题管理器：只保留一套浅色与深色配色，强调色可由用户选择。
class AppTheme {
  AppTheme._();

  /// 最近使用的主题，按使用顺序淘汰，避免反复切换自定义颜色时无限增长。
  static final Map<(Brightness, PocketAccent), ThemeData> _cache = {};
  static const int _cacheLimit = 8;

  /// 西文与数字的字体：随应用打包，所有界面统一使用。
  ///
  /// 用户在设置里选的字体排在它的回退列表首位，所以中文等 Manrope 没有
  /// 的字形仍然用用户选的字体，再往后才是系统字体。
  static const String latinFontFamily = 'Manrope';

  /// [style] 改为西文优先：字体族为 Manrope，[fallbackFamily] 排在回退首位。
  static TextStyle? latinFirst(TextStyle? style, String? fallbackFamily) {
    if (style == null) return null;
    return style.copyWith(
      fontFamily: latinFontFamily,
      fontFamilyFallback: [
        if (fallbackFamily != null && fallbackFamily != latinFontFamily)
          fallbackFamily,
        for (final family in style.fontFamilyFallback ?? const <String>[])
          if (family != fallbackFamily && family != latinFontFamily) family,
      ],
    );
  }

  static TextTheme _latinFirstTheme(TextTheme theme, String? fallbackFamily) {
    TextStyle? apply(TextStyle? style) => latinFirst(style, fallbackFamily);
    return theme.copyWith(
      displayLarge: apply(theme.displayLarge),
      displayMedium: apply(theme.displayMedium),
      displaySmall: apply(theme.displaySmall),
      headlineLarge: apply(theme.headlineLarge),
      headlineMedium: apply(theme.headlineMedium),
      headlineSmall: apply(theme.headlineSmall),
      titleLarge: apply(theme.titleLarge),
      titleMedium: apply(theme.titleMedium),
      titleSmall: apply(theme.titleSmall),
      bodyLarge: apply(theme.bodyLarge),
      bodyMedium: apply(theme.bodyMedium),
      bodySmall: apply(theme.bodySmall),
      labelLarge: apply(theme.labelLarge),
      labelMedium: apply(theme.labelMedium),
      labelSmall: apply(theme.labelSmall),
    );
  }

  /// 获取指定明暗的主题
  ///
  /// [fontConfig] 为 null 或系统默认时，保留主题原生字体；
  /// 有值时用用户选择覆盖主题字体。[accent] 决定 primary 系角色。
  static ThemeData getTheme(
    Brightness brightness, {
    FontConfig? fontConfig,
    PocketAccent accent = PocketAccent.fallback,
  }) {
    final key = (brightness, accent);
    final baseTheme =
        _cache.remove(key) ?? PocketTheme.build(brightness, accent);
    _cache[key] = baseTheme;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }

    // 使用主题原生字体
    if (fontConfig == null || fontConfig.fontFamily.isEmpty) {
      return baseTheme.copyWith(
        tooltipTheme: _buildTooltipTheme(baseTheme, null),
      );
    }

    // 应用用户选择的字体
    return _applyFontConfig(baseTheme, fontConfig);
  }

  /// 应用字体配置到主题
  static ThemeData _applyFontConfig(
    ThemeData baseTheme,
    FontConfig fontConfig,
  ) {
    final result = switch (fontConfig.source) {
      FontSource.google => _buildGoogleFontTheme(
        baseTheme,
        fontConfig.fontFamily,
      ),
      FontSource.system => (
        baseTheme.textTheme.apply(fontFamily: fontConfig.fontFamily),
        baseTheme.primaryTextTheme.apply(fontFamily: fontConfig.fontFamily),
        fontConfig.fontFamily,
      ),
    };

    if (result == null) {
      return baseTheme.copyWith(
        tooltipTheme: _buildTooltipTheme(baseTheme, null),
      );
    }

    // 用户字体退到回退列表首位，西文与数字统一用 Manrope。
    final (userTextTheme, userPrimaryTextTheme, userFontFamily) = result;
    final textTheme = _latinFirstTheme(userTextTheme, userFontFamily);
    final primaryTextTheme = _latinFirstTheme(
      userPrimaryTextTheme,
      userFontFamily,
    );

    return baseTheme.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      tooltipTheme: _buildTooltipTheme(baseTheme, userFontFamily),
      chipTheme: _applyFontToChipTheme(baseTheme.chipTheme, textTheme),
    );
  }

  /// 把用户字体同步到 Chip 的标签样式。
  ///
  /// Chip 对 `labelStyle` / `secondaryLabelStyle` 是"有则取之"而非合并：
  /// 主题一旦设了这两项，就不会再回退到 `textTheme.labelLarge`，
  /// 因此仅更新 textTheme 不足以让 Chip 跟随用户选择的字体。
  static ChipThemeData _applyFontToChipTheme(
    ChipThemeData chipTheme,
    TextTheme textTheme,
  ) {
    final label = textTheme.labelLarge;
    final fontFamily = label?.fontFamily;
    if (fontFamily == null) return chipTheme;
    return chipTheme.copyWith(
      labelStyle: chipTheme.labelStyle?.copyWith(
        fontFamily: fontFamily,
        fontFamilyFallback: label?.fontFamilyFallback,
      ),
      secondaryLabelStyle: chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: fontFamily,
        fontFamilyFallback: label?.fontFamilyFallback,
      ),
    );
  }

  /// 构建 Google Font 主题，返回 null 如果字体无效
  static (TextTheme textTheme, TextTheme primaryTextTheme, String? fontFamily)?
  _buildGoogleFontTheme(ThemeData baseTheme, String fontName) {
    try {
      final fontFamily = GoogleFonts.getFont(fontName).fontFamily;
      return (
        _applyGoogleFont(baseTheme.textTheme, fontName),
        _applyGoogleFont(baseTheme.primaryTextTheme, fontName),
        fontFamily,
      );
    } catch (e) {
      return null;
    }
  }

  /// 使用 Google Font 应用到 TextTheme
  static TextTheme _applyGoogleFont(TextTheme base, String fontName) {
    final fontFamily = GoogleFonts.getFont(fontName).fontFamily;

    TextStyle? applyFont(TextStyle? style) =>
        style?.copyWith(fontFamily: fontFamily);

    return base.copyWith(
      displayLarge: applyFont(base.displayLarge),
      displayMedium: applyFont(base.displayMedium),
      displaySmall: applyFont(base.displaySmall),
      headlineLarge: applyFont(base.headlineLarge),
      headlineMedium: applyFont(base.headlineMedium),
      headlineSmall: applyFont(base.headlineSmall),
      titleLarge: applyFont(base.titleLarge),
      titleMedium: applyFont(base.titleMedium),
      titleSmall: applyFont(base.titleSmall),
      bodyLarge: applyFont(base.bodyLarge),
      bodyMedium: applyFont(base.bodyMedium),
      bodySmall: applyFont(base.bodySmall),
      labelLarge: applyFont(base.labelLarge),
      labelMedium: applyFont(base.labelMedium),
      labelSmall: applyFont(base.labelSmall),
    );
  }

  /// 保留主题预设的浮层样式，仅同步用户字体。
  static TooltipThemeData _buildTooltipTheme(
    ThemeData baseTheme,
    String? fontFamily,
  ) {
    final tooltipTheme = baseTheme.tooltipTheme;
    final style = tooltipTheme.textStyle ?? baseTheme.textTheme.bodySmall;
    return tooltipTheme.copyWith(
      textStyle: fontFamily == null ? style : latinFirst(style, fontFamily),
      padding:
          tooltipTheme.padding ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration:
          tooltipTheme.waitDuration ?? const Duration(milliseconds: 500),
    );
  }
}
