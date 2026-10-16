import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// 重点场次卡片：记分牌 + 进球时间轴 + 进球全记录 + 事件 + 赛前赛后 + 来源
class MatchCard extends StatelessWidget {
  final Match match;
  final int index;
  const MatchCard({super.key, required this.match, required this.index});

  @override
  Widget build(BuildContext context) {
    final m = match;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 序号 + 联赛
          Row(
            children: [
              Container(
                width: 22, height: 22, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.grL, borderRadius: BorderRadius.circular(6)),
                child: Text('${index + 1}', style: const TextStyle(color: AppColors.gr, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              if (m.league.isNotEmpty) Text(m.league, style: const TextStyle(color: AppColors.tx2, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          _scoreboard(m),
          if (m.venue.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: m.venue
                  .split(RegExp(r'[；;]'))
                  .map((c) => c.trim())
                  .where((c) => c.isNotEmpty)
                  .map((c) => SoftChip(c))
                  .toList(),
            ),
          ],
          if (m.goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            _GoalTimeline(m),
          ],
          if (m.goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BlockHeader('进球全记录', count: '${m.goals.length} 球'),
                  for (final g in m.goals) _GoalRow(g: g, home: m.home, away: m.away),
                ],
              ),
            ),
          ],
          if (m.events.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BlockHeader('其他重大事件'),
                  for (final e in m.events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.label.isNotEmpty) ...[
                            TagChip(e.label, color: _eventColor(e.label)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: InlineText(e.text.isEmpty ? '—' : e.text, style: const TextStyle(color: AppColors.tx2, fontSize: 13, height: 1.5))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (m.pre.isNotEmpty || m.post.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BlockHeader('赛前 / 赛后声音'),
                  for (final q in m.pre) _QuoteBox(quote: q, post: false),
                  if (m.pre.isNotEmpty && m.post.isNotEmpty) const SizedBox(height: 8),
                  for (final q in m.post) _QuoteBox(quote: q, post: true),
                ],
              ),
            ),
          ],
          if (m.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BlockHeader('本场来源'),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      for (final s in m.sources)
                        if (s.url.isNotEmpty)
                          GestureDetector(
                            onTap: () => openExternal(s.url),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.bluBg, borderRadius: BorderRadius.circular(6)),
                              child: Text(s.name.isEmpty ? s.url : s.name,
                                  style: const TextStyle(color: AppColors.blu, fontSize: 12)),
                            ),
                          )
                        else
                          SoftChip(s.name),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 浅色记分牌（还原网页版 .score 的真实记分牌质感）
  Widget _scoreboard(Match m) {
    final win = m.winSide; // 1 主 2 客 0 平
    Color nameColor(int side) => win == side ? AppColors.numTx : AppColors.numTxDim;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(color: AppColors.numBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(m.home, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nameColor(1), fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('主队', style: TextStyle(color: AppColors.mu, fontSize: 10)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('${m.scoreHome} - ${m.scoreAway}',
                style: const TextStyle(color: AppColors.numTx, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(m.away, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nameColor(2), fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('客队', style: TextStyle(color: AppColors.mu, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _eventColor(String label) {
    if (RegExp(r'红牌|罚下').hasMatch(label)) return AppColors.red;
    if (RegExp(r'黄牌').hasMatch(label)) return AppColors.yel;
    if (RegExp(r'点球').hasMatch(label)) return AppColors.pur;
    if (RegExp(r'争议|VAR|判罚|越位').hasMatch(label)) return AppColors.ora;
    if (RegExp(r'数据|统计').hasMatch(label)) return AppColors.sla;
    if (RegExp(r'备注|纪录|机会').hasMatch(label)) return AppColors.gr;
    return AppColors.blu;
  }
}

/// 进球行：时间 | 队伍点 | 射手 | 助攻徽标，下行过程描述
class _GoalRow extends StatelessWidget {
  final Goal g;
  final String home;
  final String away;
  const _GoalRow({required this.g, required this.home, required this.away});

  bool get isHome => home.isNotEmpty && g.team.startsWith(home);

  Color get teamColor => isHome ? AppColors.gr : AppColors.blu;

  @override
  Widget build(BuildContext context) {
    Widget? badge;
    if (g.assistType == '助攻') {
      badge = TagChip('助攻 · ${g.assist.isEmpty ? '未记录' : g.assist}', color: AppColors.yel);
    } else if (g.assistType == '无助攻') {
      badge = TagChip('无助攻', color: AppColors.sla);
    } else if (g.assistType == '乌龙') {
      badge = TagChip('乌龙球${g.assist.isEmpty ? '' : ' · ${g.assist}'}', color: AppColors.ora);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主行：时间 + 队伍点 + 射手/队名（名字不限行，长球员名不再截断）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(5)),
                  child: Text(g.time, style: const TextStyle(color: AppColors.tx2, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 7),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: teamColor, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.scorer, style: const TextStyle(color: AppColors.tx, fontSize: 13, fontWeight: FontWeight.w700, height: 1.35)),
                    if (g.team.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(g.team, style: const TextStyle(color: AppColors.mu, fontSize: 12, height: 1.3)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 徽标（助攻/乌龙等）单独一行，避免挤压名字
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: badge,
            ),
          if (g.desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 3),
              child: InlineText(g.desc, style: const TextStyle(color: AppColors.mu, fontSize: 12.5, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

/// 进球时间分布轴：主队在上、客队在下的左右布局点线图
class _GoalTimeline extends StatelessWidget {
  final Match m;
  const _GoalTimeline(this.m);

  // 移植网页版 layoutPcts：按分钟定位并自动避让重叠
  List<double> _layout(List<int> mins) {
    final n = mins.length;
    if (n == 0) return [];
    const lo = 3.0, hi = 97.0, gap = 10.0;
    final scale = <int>[...mins, 90].reduce((a, b) => a > b ? a : b);
    final p = [for (final v in mins) lo + (hi - lo) * v / (scale == 0 ? 1 : scale)];
    for (var i = 1; i < n; i++) {
      if (p[i] < p[i - 1] + gap) p[i] = p[i - 1] + gap;
    }
    if (p[n - 1] > hi) {
      p[n - 1] = hi;
      for (var i = n - 2; i >= 0; i--) {
        if (p[i] > p[i + 1] - gap) p[i] = p[i + 1] - gap;
      }
    }
    for (var i = 0; i < n; i++) {
      if (p[i] < lo) p[i] = lo;
    }
    return p;
  }

  int _minute(String time) {
    final s = time.replaceAll("'", '');
    final m = RegExp(r'^(\d+)(?:\+(\d+))?').firstMatch(s);
    if (m == null) return 0;
    final base = int.tryParse(m.group(1)!) ?? 0;
    final extra = int.tryParse(m.group(2) ?? '') ?? 0;
    return base + extra;
  }

  @override
  Widget build(BuildContext context) {
    final homeGoals = <Goal>[];
    final awayGoals = <Goal>[];
    for (final g in m.goals) {
      if (m.home.isNotEmpty && g.team.startsWith(m.home)) {
        homeGoals.add(g);
      } else {
        awayGoals.add(g);
      }
    }
    homeGoals.sort((a, b) => _minute(a.time).compareTo(_minute(b.time)));
    awayGoals.sort((a, b) => _minute(a.time).compareTo(_minute(b.time)));
    final hp = _layout([for (final g in homeGoals) _minute(g.time)]);
    final ap = _layout([for (final g in awayGoals) _minute(g.time)]);

    return LayoutBuilder(builder: (context, box) {
      Widget row(List<Goal> gs, List<double> ps, Color color, bool up) {
        return SizedBox(
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < gs.length; i++)
                Positioned(
                  left: box.maxWidth * ps[i] / 100 - 14,
                  top: up ? 4 : 10,
                  child: SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        if (up) ...[
                          Text(gs[i].time, maxLines: 1, textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.mu, fontSize: 9)),
                          const SizedBox(height: 1),
                        ],
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        if (!up) ...[
                          const SizedBox(height: 1),
                          Text(gs[i].time, maxLines: 1, textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.mu, fontSize: 9)),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.gr, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Expanded(child: Text(m.home, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.tx2, fontSize: 12))),
                Text(m.away, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.tx2, fontSize: 12)),
                const SizedBox(width: 5),
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.blu, shape: BoxShape.circle)),
              ],
            ),
            row(homeGoals, hp, AppColors.gr, true),
            Container(height: 1, color: AppColors.line2, margin: const EdgeInsets.symmetric(vertical: 2)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text("0'", style: TextStyle(color: AppColors.mu, fontSize: 9)), Text("90'", style: TextStyle(color: AppColors.mu, fontSize: 9))],
              ),
            ),
            row(awayGoals, ap, AppColors.blu, false),
          ],
        ),
      );
    });
  }
}

/// 赛前/赛后采访气泡
class _QuoteBox extends StatelessWidget {
  final Quote quote;
  final bool post;
  const _QuoteBox({required this.quote, required this.post});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: post ? AppColors.bluBg : AppColors.grL,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TagChip(post ? '赛后' : '赛前', color: post ? AppColors.blu : AppColors.gr),
                if (quote.speaker.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Expanded(child: Text(quote.speaker, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.tx, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3))),
                ],
              ],
            ),
            if (quote.quote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: InlineText(quote.quote, style: const TextStyle(color: AppColors.tx2, fontSize: 13, height: 1.55)),
              ),
          ],
        ),
      ),
    );
  }
}
