import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repository.dart';
import '../../services/app_update_service.dart';
import '../../services/notify_service.dart';
import '../../services/settings_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// 设置页：推送开关/时间、数据同步、字体大小、App 更新、手动导入、关于
class SettingsPage extends StatefulWidget {
  final DataRepository repo;
  const SettingsPage({super.key, required this.repo});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifyEnabled = true;
  TimeOfDay24 _time = const TimeOfDay24(
      SettingsStore.defaultNotifyHour, SettingsStore.defaultNotifyMinute);
  double _textScale = 1.0;
  bool _kickoff = false;
  List<String> _favTeams = const [];

  // App 更新相关
  static const _updateChannel = MethodChannel('com.zqsb.football/update');
  final AppUpdateService _updater = AppUpdateService();
  bool _checkingUpdate = false;
  String _versionName = '';
  int _versionCode = 0;
  List<String> _deviceAbis = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await SettingsStore.notifyEnabled();
    final t = await SettingsStore.notifyTime();
    final scale = await SettingsStore.textScaleValue();
    final kickoff = await SettingsStore.kickoffRemindEnabled();
    final favs = await SettingsStore.favoriteTeams();
    // 读本机版本号（原生通道；失败不致命，仅显示留空）
    String vn = '';
    int vc = 0;
    List<String> abis = const [];
    try {
      final m = await _updateChannel
          .invokeMethod('getAppVersionInfo')
          .timeout(const Duration(seconds: 3));
      if (m is Map) {
        vn = (m['versionName'] ?? '').toString();
        vc = (m['versionCode'] is int) ? m['versionCode'] as int : 0;
        if (m['abis'] is List) {
          abis = (m['abis'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _notifyEnabled = enabled;
        _time = t;
        _textScale = scale;
        _kickoff = kickoff;
        _favTeams = favs;
        _versionName = vn;
        _versionCode = vc;
        _deviceAbis = abis;
      });
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ==================== 通知 ====================

  Future<void> _toggleNotify(bool v) async {
    await SettingsStore.setNotifyEnabled(v);
    await NotifyService.instance.applySchedule();
    setState(() => _notifyEnabled = v);
    _toast(v ? '每日推送已开启（${_time.label}）' : '每日推送已关闭');
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time.hour, minute: _time.minute),
      helpText: '选择每日推送时间',
      confirmText: '确定',
      cancelText: '取消',
    );
    if (picked == null) return;
    final t = TimeOfDay24(picked.hour, picked.minute);
    await SettingsStore.setNotifyTime(t);
    await NotifyService.instance.applySchedule();
    setState(() => _time = t);
    _toast('推送时间已改为每天 ${t.label}');
  }

  /// 开球前 30 分钟提醒开关：开启后立即按最新一期赛程排定
  Future<void> _toggleKickoff(bool v) async {
    await SettingsStore.setKickoffRemind(v);
    setState(() => _kickoff = v);
    try {
      final latest = widget.repo.reports.isEmpty ? null : widget.repo.reports.first;
      if (v) {
        await NotifyService.instance.applyKickoffReminders(latest);
        _toast('开球提醒已开启（赛前 30 分钟）');
      } else {
        await NotifyService.instance.cancelKickoffReminders();
        _toast('开球提醒已关闭');
      }
    } catch (_) {
      _toast(v ? '设置已保存，提醒将在下次打开 App 时生效' : '开球提醒已关闭');
    }
  }

  // ==================== 我的主队 ====================

  Future<void> _pickFavoriteTeams() async {
    final ctrl = TextEditingController(text: _favTeams.join('，'));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('我的主队',
            style: TextStyle(color: AppColors.tx, fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入你支持的球队名（如：皇马、阿森纳），\n多个用逗号或空格隔开，速报中将高亮显示。',
                style: TextStyle(color: AppColors.mu, fontSize: 12.5, height: 1.6)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.tx, fontSize: 14),
              decoration: InputDecoration(
                hintText: '如：皇马，阿森纳',
                hintStyle: const TextStyle(color: AppColors.mu, fontSize: 13),
                filled: true,
                fillColor: AppColors.soft,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.mu)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.gr, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    // 按常见分隔符拆分，去重去空，最多 5 支
    final parts = ctrl.text
        .split(RegExp(r'[,，、;；\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .take(5)
        .toList();
    await SettingsStore.setFavoriteTeams(parts);
    setState(() => _favTeams = parts);
    _toast(parts.isEmpty ? '已清空主队' : '已保存主队：${parts.join('、')}');
  }

  // ==================== 数据同步 / 导入 ====================

  Future<void> _syncData() async {
    _toast('正在同步数据…');
    final msg = await widget.repo.refresh(fromUser: true);
    _toast(msg);
  }

  Future<void> _importFile() async {
    try {
      const typeGroup = XTypeGroup(label: 'data.js', extensions: ['js', 'txt']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final raw = await file.readAsString();
      final msg = await widget.repo.importRaw(raw);
      _toast(msg);
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  // ==================== 字体大小 ====================

  Future<void> _pickTextScale() async {
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.card,
        title: const Text('字体大小', style: TextStyle(color: AppColors.tx, fontSize: 17, fontWeight: FontWeight.w700)),
        children: [
          RadioGroup<double>(
            groupValue: _textScale,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              children: [
                for (final e in SettingsStore.textScaleOptions.entries)
                  RadioListTile<double>(
                    value: e.value,
                    activeColor: AppColors.gr,
                    title: Text(e.key, style: const TextStyle(color: AppColors.tx, fontSize: 15)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == _textScale) return;
    await SettingsStore.setTextScale(picked);
    setState(() => _textScale = picked);
    _toast('字体大小已调整');
  }

  // ==================== App 手动更新 ====================

  Future<void> _checkAppUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      // 每次检查前先清掉上次下载的临时 apk
      await _updater.cleanTemp();
      final outcome = await _updater.checkUpdate(localCode: _versionCode);
      if (!mounted) return;
      if (outcome.networkError) {
        final retry = await _showRetryableDialog('网络连接失败，请检查网络后重试');
        if (retry == true) {
          if (mounted) setState(() => _checkingUpdate = false);
          _checkAppUpdate();
          return;
        }
        return;
      }
      final info = outcome.info;
      if (info == null) {
        // 把当前版本号一并说出来，避免「看不到自己装的是哪一版」
        _toast(_versionName.isEmpty
            ? '已是最新版本'
            : '已是最新版本（v$_versionName，版本号 $_versionCode）');
        return;
      }
      // 强制更新：本地 versionCode 低于远端 minVersionCode 时不给「以后再说」
      final force = needForceUpdate(minVersionCode: info.minVersionCode, localCode: _versionCode);
      final go = await _showUpdateConfirmDialog(info, force: force);
      if (go == true) {
        await _downloadAndInstall(info);
      }
    } catch (_) {
      _toast('检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// 有新版：弹窗展示版本号 + 说明 →「以后再说」/「立即下载」
  /// [force] 强制更新：点外部无法关闭，只有「立即下载」一个按钮
  Future<bool?> _showUpdateConfirmDialog(UpdateInfo info, {bool force = false}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('发现新版本 ${info.version}',
            style: const TextStyle(color: AppColors.tx, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 ${_versionName.isEmpty ? _versionLabelFallback() : _versionName}（$_versionCode）',
                style: const TextStyle(color: AppColors.mu, fontSize: 13)),
            const SizedBox(height: 10),
            if (info.notes.isNotEmpty)
              Text(info.notes,
                  style: const TextStyle(color: AppColors.tx2, fontSize: 14, height: 1.5)),
          ],
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('以后再说', style: TextStyle(color: AppColors.mu)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.gr, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即下载'),
          ),
        ],
        ),
      ),
    );
  }

  String _versionLabelFallback() {
    // 通道不可用时的兜底显示（正常安装包都能读到）；不要编造版本号误导用户
    return _versionCode > 0 ? '版本号 $_versionCode' : '未知';
  }

  /// 下载：进度弹窗（百分比 + 进度条，可取消）→ 完成后走安装
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    final prog = ValueNotifier<(int, int?)>((0, null));
    var cancelled = false;

    unawaited(showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<(int, int?)>(
        valueListenable: prog,
        builder: (ctx, v, _) {
          final (received, total) = v;
          final hasTotal = total != null && total > 0;
          final mbR = (received / 1048576).toStringAsFixed(1);
          final mbT = hasTotal ? (total / 1048576).toStringAsFixed(1) : '?';
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('正在下载 ${info.version}',
                style: const TextStyle(color: AppColors.tx, fontSize: 17, fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTotal
                      ? '${(received / total * 100).toStringAsFixed(0)}%　$mbR / $mbT MB'
                      : '已下载 $mbR MB',
                  style: const TextStyle(color: AppColors.tx2, fontSize: 13),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: hasTotal ? received / total : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                  backgroundColor: AppColors.soft,
                  color: AppColors.gr,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(ctx);
                },
                child: const Text('取消', style: TextStyle(color: AppColors.mu)),
              ),
            ],
          );
        },
      ),
    ));

    try {
      final path = await _updater.downloadApk(
        info,
        // arm64 机型优先下载小体积专属包（约 20MB），其余用通用包
        downloadUrl: pickApkUrl(
          universalUrl: info.apkUrl,
          arm64Url: info.apkUrlArm64,
          deviceAbis: _deviceAbis,
        ),
        onProgress: (received, total) => prog.value = (received, total),
        isCancelled: () => cancelled,
      );
      if (cancelled) return; // 用户已取消：进度弹窗已被取消按钮自己关闭，不再 pop
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // 关进度弹窗
      await _installApk(path);
    } catch (e) {
      // 取消路径：弹窗已被取消按钮关闭，不能再 pop（否则会误关页面）
      if (!cancelled && mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 失败路径：关进度弹窗
      }
      if (isDownloadCancelled(e)) return;
      final retry = await _showRetryableDialog(downloadErrorMessage(e));
      if (retry == true && mounted) {
        _downloadAndInstall(info);
      }
    }
  }

  /// 安装：Android 8+ 先检查「安装未知应用」授权，未授权跳设置，回来后继续
  Future<void> _installApk(String path) async {
    try {
      var can = false;
      try {
        can = await _updateChannel.invokeMethod('canInstallUnknown') as bool;
      } catch (_) {}
      if (!can) {
        try {
          await _updateChannel.invokeMethod('openUnknownSourceSettings');
        } catch (_) {
          _toast('无法打开授权页面，请重试');
          return;
        }
        if (!mounted) return;
        final cont = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('需要安装权限',
                style: TextStyle(color: AppColors.tx, fontSize: 17, fontWeight: FontWeight.w800)),
            content: const Text(
              '已跳转到系统授权页面。\n请打开「允许安装未知应用」的开关，然后回到这里点「继续安装」。',
              style: TextStyle(color: AppColors.tx2, fontSize: 14, height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消', style: TextStyle(color: AppColors.mu)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.gr, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续安装'),
              ),
            ],
          ),
        );
        if (cont != true) return;
        try {
          can = await _updateChannel.invokeMethod('canInstallUnknown') as bool;
        } catch (_) {}
        if (!can) {
          _toast('尚未授权安装，已取消');
          return;
        }
      }
      await _updateChannel.invokeMethod('installApk', {'path': path});
      _toast('已交给系统安装，请在弹出的界面确认');
    } catch (_) {
      _toast('安装失败，请重新下载');
    }
  }

  /// 可重试错误弹窗：返回 true 表示用户点了重试
  Future<bool?> _showRetryableDialog(String msg) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text(msg, style: const TextStyle(color: AppColors.tx2, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.mu)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.gr, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  String get _versionLabel {
    if (_versionName.isEmpty) return '…';
    return _versionCode > 0 ? '$_versionName ($_versionCode)' : _versionName;
  }

  /// 「关于 → 版本」显示真实版本号（原来写死成「足球速报」，看不出装的是哪一版）
  String get _versionText {
    if (_versionName.isEmpty) return '未获取到（重启 App 再试）';
    return _versionCode > 0 ? 'v$_versionName（版本号 $_versionCode）' : 'v$_versionName';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: '设置',
        subtitle: _versionName.isEmpty ? '足球速报' : '足球速报 v$_versionName',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionTitle('通知'),
          _card(
            Column(
              children: [
                SwitchListTile(
                  title: const Text('每日推送', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('每天定时提醒查看当日速报', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  value: _notifyEnabled,
                  onChanged: _toggleNotify,
                ),
                const Divider(height: 1, color: AppColors.line),
                ListTile(
                  title: const Text('推送时间', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('默认每天 08:00', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  trailing: Text(_time.label, style: const TextStyle(color: AppColors.gr, fontSize: 16, fontWeight: FontWeight.w800)),
                  onTap: _notifyEnabled ? _pickTime : null,
                ),
                const Divider(height: 1, color: AppColors.line),
                SwitchListTile(
                  title: const Text('开球提醒', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('当天比赛开球前 30 分钟提醒（按最新一期赛程）', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  value: _kickoff,
                  activeThumbColor: AppColors.gr,
                  onChanged: _toggleKickoff,
                ),
              ],
            ),
          ),
          _sectionTitle('个性化'),
          _card(
            Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.star_rounded, color: AppColors.ora),
                  title: const Text('我的主队', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _favTeams.isEmpty ? '设置你支持的球队，速报中将高亮显示' : _favTeams.join('、'),
                    style: const TextStyle(color: AppColors.mu, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.mu),
                  onTap: _pickFavoriteTeams,
                ),
              ],
            ),
          ),
          _sectionTitle('显示'),
          _card(
            Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.format_size_rounded, color: AppColors.pur),
                  title: const Text('字体大小', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('全局生效，适合不同阅读习惯', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  trailing: Text(SettingsStore.scaleLabel(_textScale),
                      style: const TextStyle(color: AppColors.gr, fontSize: 14, fontWeight: FontWeight.w700)),
                  onTap: _pickTextScale,
                ),
              ],
            ),
          ),
          _sectionTitle('数据'),
          _card(
            Column(
              children: [
                ListTile(
                  leading: _checkingUpdate || widget.repo.syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gr))
                      : const Icon(Icons.sync, color: AppColors.gr),
                  title: const Text('立即同步数据', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: Text(_lastSyncText(), style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                  onTap: _syncData,
                ),
                const Divider(height: 1, color: AppColors.line),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined, color: AppColors.blu),
                  title: const Text('手动导入 data.js', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('极端情况下从文件导入速报数据', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  onTap: _importFile,
                ),
              ],
            ),
          ),
          _sectionTitle('关于'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: _checkingUpdate
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gr))
                      : const Icon(Icons.system_update_outlined, color: AppColors.ora),
                  title: const Text('检查 App 更新', style: TextStyle(color: AppColors.tx, fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: Text('当前版本 $_versionLabel', style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                  onTap: _checkAppUpdate,
                ),
                const Divider(height: 1, color: AppColors.line),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: AppColors.mu),
                  title: const Text('版本', style: TextStyle(color: AppColors.tx, fontSize: 15)),
                  trailing: Text(
                    _versionText,
                    style: const TextStyle(color: AppColors.tx2, fontSize: 14),
                  ),
                ),
                const Divider(height: 1, color: AppColors.line),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('数据源', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                      SizedBox(height: 3),
                      Text('每天 07:10 自动生成并发布最新速报', style: TextStyle(color: AppColors.tx2, fontSize: 13)),
                      SizedBox(height: 10),
                      Text('离线可用', style: TextStyle(color: AppColors.mu, fontSize: 12)),
                      SizedBox(height: 3),
                      Text('内置最近数据，断网也能浏览上次更新内容', style: TextStyle(color: AppColors.tx2, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lastSyncText() {
    final s = widget.repo.lastSync;
    if (s == null) return '从未同步（当前：${widget.repo.source}）';
    final h = s.hour.toString().padLeft(2, '0');
    final m = s.minute.toString().padLeft(2, '0');
    return '上次同步 ${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')} $h:$m · 当前来源：${widget.repo.source}';
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
        child: Text(t, style: const TextStyle(color: AppColors.mu, fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );
}
