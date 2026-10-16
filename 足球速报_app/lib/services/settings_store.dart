import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置存储：推送开关、推送时间、字体大小
class SettingsStore {
  /// 每日推送默认时间（提示词要求：默认 08:00，写成可调常量）
  static const int defaultNotifyHour = 8;
  static const int defaultNotifyMinute = 0;

  /// 字体大小档位：全局文字缩放（MaterialApp.builder 里通过 MediaQuery 应用）
  static final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.0);
  static const Map<String, double> textScaleOptions = {
    '小': 0.88,
    '标准': 1.0,
    '大': 1.15,
  };

  static String scaleLabel(double v) =>
      textScaleOptions.entries.firstWhere((e) => e.value == v, orElse: () => const MapEntry('标准', 1.0)).key;

  static Future<double> textScaleValue() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble('text_scale') ?? 1.0;
    textScaleNotifier.value = v;
    return v;
  }

  static Future<void> setTextScale(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('text_scale', v);
    textScaleNotifier.value = v;
  }

  static Future<bool> notifyEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('notify_enabled') ?? true;
  }

  static Future<void> setNotifyEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notify_enabled', v);
  }

  static Future<TimeOfDay24> notifyTime() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDay24(
      p.getInt('notify_hour') ?? defaultNotifyHour,
      p.getInt('notify_minute') ?? defaultNotifyMinute,
    );
  }

  static Future<void> setNotifyTime(TimeOfDay24 t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('notify_hour', t.hour);
    await p.setInt('notify_minute', t.minute);
  }

  /// 已读速报日期集合（如 2026-10-10），用于列表页未读圆点
  static Future<Set<String>> readDates() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList('read_dates') ?? const []).toSet();
  }

  /// 标记某期已读（返回是否新加入，重复标记无操作）
  static Future<void> markRead(String date) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList('read_dates') ?? const []).toSet();
    if (s.add(date)) {
      await p.setStringList('read_dates', s.toList());
    }
  }

  /// 我的主队：名称列表（如 ['皇马','阿森纳']），速报里出现时高亮
  static Future<List<String>> favoriteTeams() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList('favorite_teams') ?? const [];
  }

  static Future<void> setFavoriteTeams(List<String> teams) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favorite_teams', teams);
    favoriteTeamsNotifier.value = List.unmodifiable(teams);
  }

  /// 内存态：主队变更即时生效（列表/详情页监听刷新）
  static final ValueNotifier<List<String>> favoriteTeamsNotifier =
      ValueNotifier<List<String>>(const []);

  static Future<void> loadFavoriteTeams() async {
    favoriteTeamsNotifier.value = List.unmodifiable(await favoriteTeams());
  }

  /// 开球前提醒开关（默认关：避免打扰）
  static Future<bool> kickoffRemindEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('kickoff_remind') ?? false;
  }

  static Future<void> setKickoffRemind(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('kickoff_remind', v);
  }
}

class TimeOfDay24 {
  final int hour;
  final int minute;
  const TimeOfDay24(this.hour, this.minute);

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
