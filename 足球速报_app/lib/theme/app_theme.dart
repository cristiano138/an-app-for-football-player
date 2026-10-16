import 'package:flutter/material.dart';

/// 配色常量：与网页版 index.html :root 完全对应（#0D100F 深色主题）
class AppColors {
  static const bg = Color(0xFF0D100F);       // 主背景
  static const card = Color(0xFF171B1A);     // 卡片
  static const tx = Color(0xFFE9EDEC);       // 主文字
  static const tx2 = Color(0xFFC2C9C6);      // 次文字
  static const mu = Color(0xFF8B9490);       // 弱文字
  static const line = Color(0x17FFFFFF);     // rgba(255,255,255,.09)
  static const line2 = Color(0xFF2C3230);
  static const soft = Color(0xFF1E2322);     // 内嵌浅块
  static const soft2 = Color(0xFF262C2A);
  static const chip = Color(0x12FFFFFF);     // rgba(255,255,255,.07)

  static const gr = Color(0xFF35C08F);       // 主强调绿
  static const grLt = Color(0xFF4ADE9F);
  static const grL = Color(0x2435C08F);      // rgba(53,192,143,.14)
  static const grDk = Color(0xFF14805D);     // 头部渐变起
  static const grDk2 = Color(0xFF0A4E3A);    // 头部渐变止

  static const numBg = Color(0xFFE7ECEA);    // 记分牌浅底
  static const numTx = Color(0xFF0B5D46);    // 记分牌数字
  static const numTxDim = Color(0xFF3A4A45); // 记分牌非胜方

  static const red = Color(0xFFFF6B5B);
  static const yel = Color(0xFFE9B94B);
  static const pur = Color(0xFFA78BFA);
  static const ora = Color(0xFFF2893E);
  static const sla = Color(0xFF8FA3B0);
  static const blu = Color(0xFF63AEFA);

  static const redBg = Color(0x24FF6B5B);
  static const yelBg = Color(0x24E9B94B);
  static const purBg = Color(0x24A78BFA);
  static const oraBg = Color(0x24F2893E);
  static const slaBg = Color(0x248FA3B0);
  static const bluBg = Color(0x2463AEFA);
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gr,
        secondary: AppColors.grLt,
        surface: AppColors.card,
        onSurface: AppColors.tx,
      ),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerColor: AppColors.line,
      splashColor: AppColors.grL,
      highlightColor: AppColors.chip,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.soft2,
        contentTextStyle: const TextStyle(color: AppColors.tx, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.grDk2 : AppColors.mu),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.gr : AppColors.line2),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.card,
        dialBackgroundColor: AppColors.soft,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: AppColors.card,
        collapsedBackgroundColor: AppColors.card,
        iconColor: AppColors.mu,
        collapsedIconColor: AppColors.mu,
        textColor: AppColors.tx,
        collapsedTextColor: AppColors.tx,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.tx),
        bodyMedium: TextStyle(color: AppColors.tx),
        bodySmall: TextStyle(color: AppColors.mu),
      ),
    );
  }
}
