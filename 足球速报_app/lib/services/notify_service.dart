import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/report.dart';
import 'settings_store.dart';

/// 每日本地推送通知（时间可在设置页调整）+ 当日比赛开球前提醒。
class NotifyService {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  static const _channelId = 'daily_brief';
  static const _channelName = '每日速报';
  static const _notifyId = 1001;
  static const _kickoffChannelId = 'kickoff';
  static const _kickoffChannelName = '开球提醒';

  /// 已排定的开球提醒 id（重排前先逐个取消）
  final Set<int> _kickoffIds = {};

  Future<void> _ensureInit() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _inited = true;
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 应用启动时调用：按当前设置（重）排每日通知
  /// [briefTitle] 当日速报标题（数据就绪后再次调用可让推送带上标题）
  Future<void> applySchedule({String? briefTitle}) async {
    final enabled = await SettingsStore.notifyEnabled();
    await _ensureInit();
    if (!enabled) {
      await _plugin.cancel(_notifyId);
      return;
    }
    final granted = await _requestPermission();
    final t = await SettingsStore.notifyTime();

    // 精确闹钟失败时退回非精确模式
    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    try {
      await _scheduleDaily(t.hour, t.minute, scheduleMode, briefTitle);
    } catch (_) {
      scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
      await _scheduleDaily(t.hour, t.minute, scheduleMode, briefTitle);
    }
    debugPrint('每日推送已排定 ${t.label} (exact=${scheduleMode == AndroidScheduleMode.exactAllowWhileIdle}, granted=$granted)');
  }

  Future<void> _scheduleDaily(int hour, int minute, AndroidScheduleMode mode, String? briefTitle) async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final body = (briefTitle == null || briefTitle.isEmpty)
        ? '今日速报已更新，点击查看最新赛况'
        : briefTitle;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '每天定时推送当日足球速报',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
    );
    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      _notifyId,
      '⚽ 足球速报',
      body,
      scheduled,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // 每天重复
    );
  }

  // ==================== 开球提醒 ====================

  /// 按当日速报的赛程（preview 优先，退回 schedule）排定开球前 30 分钟提醒。
  /// 只排今天尚未开赛的场次；开关关闭或无赛程时静默清空。
  Future<void> applyKickoffReminders(Report? report) async {
    await _ensureInit();
    await _cancelKickoffReminders();
    if (report == null) return;
    final enabled = await SettingsStore.kickoffRemindEnabled();
    if (!enabled) return;
    final granted = await _requestPermission();
    if (!granted) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    final now = tz.TZDateTime.now(tz.local);

    final games = _todayGames(report);
    for (final g in games) {
      final kick = tz.TZDateTime(tz.local, now.year, now.month, now.day, g.hour, g.minute);
      final remindAt = kick.subtract(const Duration(minutes: 30));
      if (!remindAt.isAfter(now)) continue; // 已过提醒时间，跳过
      final id = _kickoffId(g);
      _kickoffIds.add(id);
      try {
        await _plugin.zonedSchedule(
          id,
          '⚽ ${g.hourStr}:${g.minuteStr} 开球 · ${g.league}',
          '${g.home} vs ${g.away} 将在 30 分钟后开赛',
          remindAt,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _kickoffChannelId,
              _kickoffChannelName,
              channelDescription: '关注的比赛开球前 30 分钟提醒',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {
        // 单条排定失败不影响其余提醒
      }
    }
    debugPrint('开球提醒已排定 ${_kickoffIds.length} 场');
  }

  /// 开关关闭时调用：清空全部已排提醒
  Future<void> cancelKickoffReminders() async {
    await _ensureInit();
    await _cancelKickoffReminders();
  }

  Future<void> _cancelKickoffReminders() async {
    for (final id in _kickoffIds) {
      try {
        await _plugin.cancel(id);
      } catch (_) {}
    }
    _kickoffIds.clear();
  }

  int _kickoffId(_Game g) => ('kickoff:${g.hourStr}:${g.minuteStr}:${g.home}:${g.away}').hashCode & 0x7fffffff;

  /// 从速报解析今日赛程：preview（name 形如 `03:30 · 英超`，text 形如 `A vs B`）优先
  List<_Game> _todayGames(Report r) {
    final out = <_Game>[];
    final items = <(String, String)>[];
    if (r.preview.isNotEmpty) {
      for (final g in r.preview) {
        for (final it in g.items) {
          items.add((it.timePart, '${it.text}·${it.leaguePart}'));
        }
      }
    } else {
      for (final s in r.schedule) {
        items.add(('', s.text));
      }
    }
    for (final (time, raw) in items) {
      final g = _parseGame(time, raw);
      if (g != null) out.add(g);
    }
    return out;
  }

  _Game? _parseGame(String timePart, String raw) {
    // 时间：优先 timePart（HH:MM），否则从文本开头找
    var time = timePart;
    var text = raw.trim();
    if (time.isEmpty) {
      final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(text);
      if (m == null) return null;
      time = text.substring(m.start + 1, m.end);
      text = text.substring(m.end).trim();
    }
    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
    if (hm == null) return null;
    final hour = int.tryParse(hm.group(1)!);
    final minute = int.tryParse(hm.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;

    // 队名：A vs B / A VS B / A 对 B / A - B
    final sep = RegExp(r'\s+(?:vs|VS|Vs|对)\s+');
    final parts = text.split(sep);
    String home = '', away = '', league = '';
    if (parts.length >= 2) {
      home = parts[0].trim();
      away = parts[1].split(RegExp(r'[,，;；\s]')).first.trim();
    } else {
      return null;
    }
    if (home.isEmpty || away.isEmpty) return null;
    // 联赛名（若有）：从文本尾部「·联赛」或 timePart 后缀取
    final li = text.lastIndexOf('·');
    if (li > 0 && li + 1 < text.length) league = text.substring(li + 1).trim();
    if (league.isEmpty) {
      final li2 = timePart.indexOf('·');
      if (li2 > 0) league = timePart.substring(li2 + 1).trim();
    }
    return _Game(
      hour: hour, minute: minute,
      hourStr: hour.toString().padLeft(2, '0'),
      minuteStr: minute.toString().padLeft(2, '0'),
      home: home, away: away, league: league,
    );
  }
}

/// 一场待提醒的比赛
class _Game {
  final int hour;
  final int minute;
  final String hourStr;
  final String minuteStr;
  final String home;
  final String away;
  final String league;
  const _Game({
    required this.hour, required this.minute,
    required this.hourStr, required this.minuteStr,
    required this.home, required this.away,
    this.league = '',
  });
}
