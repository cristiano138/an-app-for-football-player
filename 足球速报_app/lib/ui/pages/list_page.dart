import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../models/report.dart';
import '../../services/settings_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'detail_page.dart';

/// 速报列表页：按日期倒序的卡片流
class ListPage extends StatefulWidget {
  final DataRepository repo;
  final VoidCallback onOpenSettings;
  const ListPage({super.key, required this.repo, required this.onOpenSettings});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final scroll = ScrollController();
  bool _showTop = false;
  bool _searching = false;
  String _query = '';

  /// 已读速报的日期集合；未读的卡片在日期前显示绿点
  Set<String> _read = {};

  @override
  void initState() {
    super.initState();
    scroll.addListener(_onScroll);
    _loadRead();
  }

  Future<void> _loadRead() async {
    try {
      final s = await SettingsStore.readDates();
      if (mounted) setState(() => _read = s);
    } catch (_) {}
  }

  @override
  void dispose() {
    scroll.removeListener(_onScroll);
    scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = scroll.hasClients && scroll.offset > 900;
    if (show != _showTop) setState(() => _showTop = show);
  }

  void _openDetail(Report r) {
    // 打开即视为已读：本地立即生效（圆点消失），持久化失败不影响使用
    SettingsStore.markRead(r.date).ignore();
    setState(() => _read.add(r.date));
    Navigator.of(context).push(_SlideFadeRoute(page: DetailPage(report: r, repo: widget.repo)));
  }

  /// 搜索过滤：匹配标题/摘要/日期/任意队名/动态文本（不区分大小写）
  List<Report> _filtered(List<Report> reports) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return reports;
    bool hit(String s) => s.toLowerCase().contains(q);
    return reports.where((r) {
      if (hit(r.date) || hit(r.title) || hit(r.summary)) return true;
      for (final m in r.matches) {
        if (hit(m.home) || hit(m.away) || hit(m.league)) return true;
      }
      for (final m in r.others) {
        if (hit(m.home) || hit(m.away) || hit(m.league)) return true;
      }
      for (final d in [...r.stars, ...r.world, ...r.transfer]) {
        if (hit(d.name) || hit(d.text)) return true;
      }
      for (final g in r.preview) {
        for (final it in g.items) {
          if (hit(it.name) || hit(it.text)) return true;
        }
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Scaffold(
      appBar: GradientAppBar(
        title: '足球速报',
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded,
                color: Colors.white),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                _query = '';
              });
            },
          ),
          IconButton(
            tooltip: '检查更新',
            icon: repo.syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: repo.syncing ? null : () async {
              final msg = await repo.refresh(fromUser: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
      floatingActionButton: AnimatedScale(
        scale: _showTop && !_searching ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: FloatingActionButton.small(
          heroTag: 'backToTop',
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.gr,
          elevation: 2,
          onPressed: () {
            scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            );
          },
          child: const Icon(Icons.arrow_upward_rounded, size: 20),
        ),
      ),
      body: Column(
        children: [
          if (repo.notice.isNotEmpty) _OfflineBanner(notice: repo.notice),
          if (_searching) _searchBar(),
          Expanded(
            child: repo.loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.gr))
                : RefreshIndicator(
                    color: AppColors.gr,
                    backgroundColor: AppColors.card,
                    onRefresh: () => repo.refresh(fromUser: true),
                    // 监听主队变化：设置里改完回到列表，徽标即时生效
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: SettingsStore.favoriteTeamsNotifier,
                      builder: (_, favs, __) => _buildList(favs),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        autofocus: true,
        style: const TextStyle(color: AppColors.tx, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索球队、日期、关键词…',
          hintStyle: const TextStyle(color: AppColors.mu, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.mu),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.mu),
                  onPressed: () => setState(() => _query = ''),
                ),
          filled: true,
          fillColor: AppColors.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  Widget _buildList(List<String> favs) {
    final repo = widget.repo;
    if (repo.reports.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无速报数据\n请下拉重试或在设置中手动导入', textAlign: TextAlign.center, style: TextStyle(color: AppColors.mu, fontSize: 14, height: 1.8))),
        ],
      );
    }
    final latestDate = repo.reports.first.date;
    final shown = _filtered(repo.reports);
    if (shown.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text('没有找到「$_query」相关的速报',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mu, fontSize: 14)),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final r = shown[i];
        return _ReportCard(
          report: r,
          isLatest: r.date == latestDate,
          unread: !_read.contains(r.date),
          favHit: _favHit(r, favs),
          onTap: () => _openDetail(r),
        );
      },
    );
  }

  /// 该期是否涉及主队：返回命中的主队名（空串=不涉及）
  String _favHit(Report r, List<String> teams) {
    for (final t in teams) {
      final name = t.trim();
      if (name.isEmpty) continue;
      for (final m in r.matches) {
        if (m.home.contains(name) || m.away.contains(name)) return name;
      }
      for (final m in r.others) {
        if (m.home.contains(name) || m.away.contains(name)) return name;
      }
    }
    return '';
  }
}

/// 详情页转场：右滑入 + 渐显（300ms，比默认更顺滑）
class _SlideFadeRoute extends PageRouteBuilder {
  _SlideFadeRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );
}

class _OfflineBanner extends StatelessWidget {
  final String notice;
  const _OfflineBanner({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.yelBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 15, color: AppColors.yel),
          const SizedBox(width: 7),
          Expanded(child: Text(notice, style: const TextStyle(color: AppColors.yel, fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// 列表卡片：日期行 + 标题 + 摘要 + 前 3 场比分 + 查看入口
/// 美化：Material+InkWell 水波纹反馈；最新一期带「最新」徽标；未读带绿点；含主队带 ★ 徽标
class _ReportCard extends StatelessWidget {
  final Report report;
  final VoidCallback onTap;
  final bool isLatest;
  final bool unread;
  final String favHit;
  const _ReportCard({
    required this.report,
    required this.onTap,
    this.isLatest = false,
    this.unread = false,
    this.favHit = '',
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.grL,
          highlightColor: AppColors.chip,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLatest ? AppColors.gr.withValues(alpha: 0.45) : AppColors.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (unread) ...[
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: AppColors.gr, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(r.date, style: const TextStyle(color: AppColors.gr, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Text('周${r.weekday}', style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                    if (isLatest) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.gr,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text('最新',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    if (favHit.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.gr.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.gr.withValues(alpha: 0.5)),
                        ),
                        child: Text('★ $favHit',
                            style: const TextStyle(color: AppColors.gr, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const Spacer(),
                    Text('${r.matches.length}场 · ${r.totalGoals}球${r.dynCount > 0 ? ' · 动态${r.dynCount}' : ''}',
                        style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(r.title.isEmpty ? '足球赛事速报' : r.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: unread ? AppColors.tx : AppColors.tx2, fontSize: 16, fontWeight: FontWeight.w800)),
                if (r.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(r.summary, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.tx2, fontSize: 13, height: 1.5)),
                  ),
                if (r.matches.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final m in r.matches.take(3))
                    if (m.home.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(m.home, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                                  style: const TextStyle(color: AppColors.tx2, fontSize: 13)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('${m.scoreHome} - ${m.scoreAway}',
                                  style: const TextStyle(color: AppColors.gr, fontSize: 13, fontWeight: FontWeight.w800)),
                            ),
                            Expanded(
                              child: Text(m.away, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.tx2, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                ],
                const SizedBox(height: 6),
                const Text('查看完整日报 ›', style: TextStyle(color: AppColors.gr, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
