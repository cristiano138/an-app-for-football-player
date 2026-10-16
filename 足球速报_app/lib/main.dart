import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/repository.dart';
import 'services/notify_service.dart';
import 'services/settings_store.dart';
import 'theme/app_theme.dart';
import 'ui/pages/list_page.dart';
import 'ui/pages/settings_page.dart';

void main() {
  runApp(const FootballApp());
}

class FootballApp extends StatelessWidget {
  const FootballApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '足球速报',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 全局字体大小（设置页可调）
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: SettingsStore.textScaleNotifier,
        builder: (context, scale, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final repo = DataRepository();
  String _lastRemindDate = '';

  @override
  void initState() {
    super.initState();
    // 初始化数据（内置/缓存秒开 → 异步拉远端）、每日推送与字体设置
    // .ignore()：初始化失败（如插件异常）不应导致崩溃，静默降级
    repo.init().ignore();
    NotifyService.instance.applySchedule().ignore();
    SettingsStore.textScaleValue().ignore();
    SettingsStore.loadFavoriteTeams().ignore();
    // 数据每次变化（首帧/远端刷新）后：排开球提醒 + 让每日推送带上最新标题
    repo.addListener(_onRepoChanged);
  }

  void _onRepoChanged() {
    final latest = repo.reports.isEmpty ? null : repo.reports.first;
    if (latest == null || latest.date == _lastRemindDate) return;
    _lastRemindDate = latest.date;
    NotifyService.instance.applyKickoffReminders(latest).ignore();
    NotifyService.instance.applySchedule(briefTitle: latest.title).ignore();
  }

  @override
  void dispose() {
    repo.removeListener(_onRepoChanged);
    repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        return ListPage(
          repo: repo,
          onOpenSettings: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsPage(repo: repo)),
            );
          },
        );
      },
    );
  }
}
