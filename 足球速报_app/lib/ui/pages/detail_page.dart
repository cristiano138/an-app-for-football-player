import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repository.dart';
import '../../models/report.dart';
import '../../services/settings_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/match_card.dart';
import '../widgets/other_scores.dart';
import '../widgets/preview_group.dart';
import '../widgets/refs_section.dart';
import '../widgets/share_card.dart';
import '../widgets/stars_section.dart';
import '../widgets/transfer_section.dart';
import '../widgets/world_section.dart';

/// 当日详情页：hero + 板块（空板块自动隐藏）+ 板块导航条 + 前后日期切换
///
/// 滚动定位实现说明：
/// - body 用懒加载 ListView（SliverChildListDelegate），只构建视口附近的内容块，
///   内容再多滑动也流畅；每个板块标题挂着 GlobalKey 作锚点。
/// - 标签列表由「实际注册了锚点的板块」生成（_buildBody 内同步注册），从根上杜绝有标签没锚点。
/// - 目标板块尚未构建时，_jumpTo 按「块序号占比 × 滚动范围」估算落点逐次逼近，
///   到位后转 Scrollable.ensureVisible 平滑滚动。
class DetailPage extends StatefulWidget {
  final Report report;
  final DataRepository repo;
  const DetailPage({super.key, required this.report, required this.repo});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

/// 导航条上的一个板块标签：label + 数量 + 锚点 GlobalKey + 在内容块列表中的序号
class _TabSec {
  final String label;
  final int count;
  final int index;
  final GlobalKey key;
  const _TabSec(this.label, this.count, this.index, this.key);
}

class _DetailPageState extends State<DetailPage> {
  late Report current;
  final scroll = ScrollController();
  final keys = <String, GlobalKey>{};
  final _shareKey = GlobalKey();
  static const _updateChannel = MethodChannel('com.zqsb.football/update');

  /// 本期实际有内容、已挂锚点的板块（build 时生成，标签栏直接渲染它）
  List<_TabSec> _tabs = [];

  /// 本期内容块总数（懒加载列表的子项数，用于锚点估算定位）
  int _blockCount = 0;

  /// 阅读进度（0~1）。用 ValueNotifier 只刷新进度条本身，
  /// 绝不能在滚动回调里 setState——否则整页所有卡片每帧重建，滑动会卡。
  final _progress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    current = widget.report;
    scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    scroll.removeListener(_onScroll);
    scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// 滚动监听：更新阅读进度（只写 ValueNotifier，不 setState）
  void _onScroll() {
    if (!scroll.hasClients) return;
    final max = scroll.position.maxScrollExtent;
    final p = max <= 0 ? 0.0 : (scroll.offset / max).clamp(0.0, 1.0);
    if ((p - _progress.value).abs() > 0.004 || (p == 0 && _progress.value != 0)) {
      _progress.value = p;
    }
  }

  GlobalKey k(String key) => keys.putIfAbsent(key, GlobalKey.new);

  /// 跳转到板块：目标已构建则平滑滚动；未构建（懒加载下很常见）先估算落点：
  /// 优先用「离目标最近、已构建的锚点」反推平均块高做线性插值（双向收敛），
  /// 没有任何已构建锚点时退化为「块序号占比 × 总滚动范围」。
  /// 每次跳跃都会让目标附近的内容进入构建缓存，估算随之收敛，一般 2~3 跳内到位。
  void _jumpTo(_TabSec tab, {int attempt = 0}) {
    final ctx = tab.key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
      return;
    }
    if (attempt >= 12 || !scroll.hasClients || _blockCount == 0) return;

    // 参考锚点：所有已构建的板块标签里，块序号离目标最近的一个
    _TabSec? ref;
    for (final t in _tabs) {
      if (t.index == tab.index || t.key.currentContext == null) continue;
      if (ref == null || (t.index - tab.index).abs() < (ref.index - tab.index).abs()) {
        ref = t;
      }
    }

    double target;
    if (ref != null) {
      // 参考锚点的文档坐标 = 当前滚动偏移 + 它相对视口顶部的偏移；
      // 块 0 固定是页首 hero（文档坐标 0），故平均块高 = 锚点坐标 / 块序号
      try {
        final ro = ref.key.currentContext!.findRenderObject();
        final scrollable = Scrollable.of(ref.key.currentContext!);
        final viewportRo = scrollable.context.findRenderObject();
        if (ro is RenderBox && ro.attached && viewportRo is RenderBox) {
          final dy = ro.localToGlobal(Offset.zero, ancestor: viewportRo).dy;
          final docY = scroll.offset + dy;
          final perBlock = ref.index <= 0 ? 0.0 : docY / ref.index;
          target = (perBlock * tab.index).clamp(0.0, scroll.position.maxScrollExtent);
        } else {
          target = _fractionTarget(tab.index);
        }
      } catch (_) {
        target = _fractionTarget(tab.index);
      }
    } else {
      target = _fractionTarget(tab.index);
    }

    final before = scroll.position.maxScrollExtent;
    scroll.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tab.key.currentContext != null) {
        _jumpTo(tab); // 已构建：转平滑滚动精调
      } else if (scroll.position.maxScrollExtent > before || ref != null) {
        _jumpTo(tab, attempt: attempt + 1); // 范围仍在增长 / 有参考锚点可内插：继续逼近
      }
    });
  }

  /// 退化估算：按块序号占比 × 当前总滚动范围
  double _fractionTarget(int index) {
    if (!scroll.hasClients || _blockCount == 0) return 0;
    final max = scroll.position.maxScrollExtent;
    return (max * index / _blockCount).clamp(0.0, max);
  }

  void _switchTo(Report r) {
    setState(() {
      current = r;
      // 日期切换后内容整体重建：旧的锚点 key 一律作废，避免 GlobalKey 复用残留
      keys.clear();
      _tabs = [];
      _blockCount = 0;
      _progress.value = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  /// 一键复制本期速报要点（用于粘贴到微信/QQ 分享）
  Future<void> _copyDigest(Report r) async {
    final buf = StringBuffer();
    buf.write('【足球速报 ${r.date}');
    if (r.weekday.isNotEmpty) buf.write(' 周${r.weekday}');
    buf.writeln('】');
    buf.writeln(r.title.isEmpty ? '足球赛事速报' : r.title);
    if (r.matches.isNotEmpty) {
      buf.writeln('—— 重点比分 ——');
      for (final m in r.matches.take(6)) {
        buf.writeln('${m.home} ${m.scoreHome}-${m.scoreAway} ${m.away}');
      }
    }
    try {
      await Clipboard.setData(ClipboardData(text: buf.toString().trim()));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('速报要点已复制，去粘贴分享吧')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
      }
    }
  }

  /// 生成速报分享卡片图片并调起系统分享
  Future<void> _shareCard() async {
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception();
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw Exception();
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}${Platform.pathSeparator}share');
      await dir.create(recursive: true);
      final f = File(
          '${dir.path}${Platform.pathSeparator}football-${current.date}.png');
      await f.writeAsBytes(byteData.buffer.asUint8List());
      await _updateChannel.invokeMethod('shareImage', {'path': f.path});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('生成分享卡片失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = current;
    final all = widget.repo.reports;
    final idx = all.indexWhere((x) => x.date == r.date);
    final newer = (idx > 0 && idx - 1 >= 0) ? all[idx - 1] : null; // 日期更新的
    final older = (idx >= 0 && idx + 1 < all.length) ? all[idx + 1] : null; // 日期更早的
    final favTeams = SettingsStore.favoriteTeamsNotifier.value;

    // 先构建内容（内部同步注册有内容板块的锚点），再据此渲染标签栏
    final body = _buildBody(r, favTeams);

    return Scaffold(
      appBar: GradientAppBar(
        title: '${r.date}${r.weekday.isEmpty ? '' : ' · 周${r.weekday}'}',
        subtitle: r.title.isEmpty ? null : r.title,
        actions: [
          IconButton(
            tooltip: '分享卡片',
            icon: const Icon(Icons.ios_share_rounded, size: 20, color: Colors.white70),
            onPressed: () => _shareCard(),
          ),
          IconButton(
            tooltip: '复制要点',
            icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.white70),
            onPressed: () => _copyDigest(r),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          if (_tabs.isNotEmpty)
            Container(
              width: double.infinity,
              color: AppColors.bg,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in _tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _jumpTo(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.soft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.line2),
                            ),
                            child: Text('${t.label} ${t.count}',
                                style: const TextStyle(color: AppColors.tx2, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // 阅读进度条：只重建这一条 2px 的线，不牵动整页
          // RepaintBoundary 把进度条的高频重绘隔离在自己的图层里，
          // 否则每次更新都会向上传染、拖累整个滚动区域重画（滑动发涩的元凶之一）
          RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, __) => LinearProgressIndicator(
                value: p,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: AppColors.gr,
              ),
            ),
          ),
          Expanded(
            // 性能根修：改用懒加载 ListView。此前 SingleChildScrollView+Column 会一次性
            // 构建整页所有板块，内容一多（十几场重点+几十个前瞻）首帧构建、内存占用
            // 和图层缓存都会随内容膨胀，中低端机上滑动明显卡顿；懒加载只保留视口附近
            // 的内容，滑动开销与总内容量基本无关，内容再多也顺滑。
            // 外层手势：左右快速滑动切换前/后一天（与底部按钮方向一致：左滑→更新的一期）
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300 && newer != null) {
                  _switchTo(newer);
                } else if (v > 300 && older != null) {
                  _switchTo(older);
                }
              },
              child: ListView.custom(
                controller: scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                childrenDelegate: SliverChildListDelegate(
                  body,
                  addRepaintBoundaries: false, // 内容块已自带 RepaintBoundary
                  addAutomaticKeepAlives: false,
                ),
              ),
            ),
          ),
          // 前后日期切换
          Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: older == null ? null : () => _switchTo(older),
                    child: Text(older == null ? '没有更早的速报' : '‹ ${older.date}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: older == null ? AppColors.mu : AppColors.gr, fontSize: 13)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: newer == null ? null : () => _switchTo(newer),
                    child: Text(newer == null ? '已是最新一期' : '${newer.date} ›',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: newer == null ? AppColors.mu : AppColors.gr, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          // 屏幕外的分享卡片：仅用于截图生成图片（Stack 不会被视口裁剪，可完整绘制）
          Positioned(
            left: -2000,
            top: 0,
            child: RepaintBoundary(
              key: _shareKey,
              child: ShareCard(report: r),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建本期全部内容；每加一个有内容的板块，同步往 _tabs 注册标签+锚点（单一事实来源）
  List<Widget> _buildBody(Report r, List<String> favTeams) {
    final w = <Widget>[];
    _tabs = [];

    void reg(String keyId, String label, int count) {
      // w.length 即紧接着要加入的板块标题在内容块列表中的序号（懒加载估算定位用）
      _tabs.add(_TabSec(label, count, w.length, k(keyId)));
    }

    // hero
    w.add(Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.grDk, AppColors.grDk2],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.date}${r.weekday.isEmpty ? '' : ' · 周${r.weekday}'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(r.title.isEmpty ? '足球赛事速报' : r.title,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              _heroStat('${r.matches.length}', '场重点'),
              _heroStat('${r.totalGoals}', '个进球'),
              if (r.others.isNotEmpty) _heroStat('${r.others.length}', '场其他'),
            ],
          ),
        ],
      ),
    ));

    // 覆盖范围
    if (r.coverage.isNotEmpty) {
      w.add(const SizedBox(height: 12));
      w.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Column(
          children: [
            for (final c in r.coverage)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.label.isNotEmpty)
                      SizedBox(
                        width: 64,
                        child: Text(c.label, style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                      ),
                    Expanded(
                      child: InlineText(c.text, style: const TextStyle(color: AppColors.tx2, fontSize: 12.5, height: 1.5)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ));
    }

    // ⚽ 重点场次
    if (r.matches.isNotEmpty) {
      reg('sec-matches', '⚽ 速报', r.matches.length);
      w.add(SectionHeader(key: k('sec-matches'), emoji: '⚽', title: '重点场次', stat: '${r.matches.length} 场 · 逐球记录'));
      for (var i = 0; i < r.matches.length; i++) {
        final m = r.matches[i];
        final fav = _favHit(m, favTeams);
        if (fav.isNotEmpty) {
          w.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 13, color: AppColors.gr),
                const SizedBox(width: 4),
                Text('我的主队 · $fav',
                    style: const TextStyle(color: AppColors.gr, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ));
        }
        w.add(MatchCard(match: m, index: i));
      }
    }

    // 📊 其他完赛比分
    if (r.others.isNotEmpty) {
      reg('sec-others', '📋 比分', r.others.length);
      w.add(SectionHeader(key: k('sec-others'), emoji: '📊', title: '其他完赛比分', stat: '${r.others.length} 场'));
      w.add(OtherScoresSection(items: r.others));
    }

    // 🔔 动态板块：三个子板块共用一个锚点 sec-dyn，挂在第一个非空子板块上
    final dynCount = r.stars.length + r.world.length + r.transfer.length;
    if (dynCount > 0) {
      reg('sec-dyn', '🔔 动态', dynCount);
      final dynKey = k('sec-dyn');
      var anchorUsed = false;
      if (r.stars.isNotEmpty) {
        w.add(SectionHeader(key: dynKey, emoji: '★', title: '球星动态', stat: '${r.stars.length} 条'));
        anchorUsed = true;
        w.add(StarsSection(items: r.stars));
      }
      if (r.world.isNotEmpty) {
        // 第一个非空子板块已占用锚点；后续子板块不重复挂同一 GlobalKey
        w.add(SectionHeader(key: anchorUsed ? null : dynKey, emoji: '⚽', title: '足坛动态', stat: '${r.world.length} 条'));
        anchorUsed = true;
        w.add(WorldSection(items: r.world));
      }
      if (r.transfer.isNotEmpty) {
        w.add(SectionHeader(key: anchorUsed ? null : dynKey, emoji: '⇄', title: '转会速递', stat: '${r.transfer.length} 条'));
        anchorUsed = true;
        w.add(TransferSection(items: r.transfer));
      }
    }

    // 🔮 焦点前瞻（有 preview 按分组；没有退回 schedule）
    if (r.preview.isNotEmpty) {
      final total = r.preview.fold<int>(0, (a, g) => a + g.items.length);
      reg('sec-preview', '📅 前瞻', total);
      w.add(SectionHeader(key: k('sec-preview'), emoji: '🔮', title: '焦点前瞻', stat: '${r.preview.length} 个版块 · $total 场'));
      w.add(PreviewSection(groups: r.preview));
    } else if (r.schedule.isNotEmpty) {
      reg('sec-preview', '📅 前瞻', r.schedule.length);
      w.add(SectionHeader(key: k('sec-preview'), emoji: '📅', title: '赛程预告', stat: '${r.schedule.length} 条'));
      w.add(PreviewSection(groups: const [], schedule: r.schedule));
    }

    // 🔗 来源附录
    if (r.refs.isNotEmpty) {
      reg('sec-refs', '🔗 来源', r.refs.length);
      w.add(SectionHeader(key: k('sec-refs'), emoji: '🔗', title: '来源附录', stat: '${r.refs.length} 组'));
      w.add(RefsSection(groups: r.refs));
    }

    // 兜底：无重点与其他比分但有 md 正文时展示
    if (r.matches.isEmpty && r.others.isEmpty && r.md.isNotEmpty) {
      w.add(const SizedBox(height: 12));
      w.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: SelectableText(r.md, style: const TextStyle(color: AppColors.tx2, fontSize: 13.5, height: 1.6)),
      ));
    }

    // 关键性能优化：每个内容块包一层 RepaintBoundary（独立缓存图层），
    // 配合懒加载列表，滑动时只光栅化视口附近的内容。
    // SizedBox 间隔不画任何东西，无需包。
    _blockCount = w.length;
    return [for (final x in w) x is SizedBox ? x : RepaintBoundary(child: x)];
  }

  /// 比赛是否涉及主队：返回命中的主队名（不命中返回空串）
  String _favHit(Match m, List<String> teams) {
    for (final t in teams) {
      final name = t.trim();
      if (name.isEmpty) continue;
      if (m.home.contains(name) || m.away.contains(name)) return name;
    }
    return '';
  }

  Widget _heroStat(String num, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(num, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

