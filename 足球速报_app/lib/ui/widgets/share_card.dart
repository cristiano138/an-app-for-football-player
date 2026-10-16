import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';

/// 速报分享卡片（供截图生成图片分享到微信/QQ）
/// 布局固定宽度 360、按内容自适应高度；由详情页放在屏幕外用 RepaintBoundary 截图。
class ShareCard extends StatelessWidget {
  final Report report;
  const ShareCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== 头部：品牌 + 日期 + 标题 =====
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.grDk, AppColors.grDk2],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('⚽', style: TextStyle(fontSize: 15)),
                    SizedBox(width: 6),
                    Text('足球速报',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('${r.date}${r.weekday.isEmpty ? '' : ' · 周${r.weekday}'}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 8),
                Text(r.title.isEmpty ? '足球赛事速报' : r.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
              ],
            ),
          ),
          // ===== 比分区 =====
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('—— 重点比分 ——',
                    style: TextStyle(color: AppColors.mu, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                if (r.matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      r.summary.isEmpty ? '本期暂无重点比赛' : r.summary,
                      maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.tx2, fontSize: 14, height: 1.6),
                    ),
                  )
                else
                  for (final m in r.matches.take(6))
                    if (m.home.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(m.home,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: AppColors.tx, fontSize: 15)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.grDk,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('${m.scoreHome} - ${m.scoreAway}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                              ),
                            ),
                            Expanded(
                              child: Text(m.away,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.tx, fontSize: 15)),
                            ),
                          ],
                        ),
                      ),
                if (r.matches.length > 6)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('……更多场次见 App',
                        style: TextStyle(color: AppColors.mu, fontSize: 12)),
                  ),
              ],
            ),
          ),
          // ===== 底部 =====
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: const Row(
              children: [
                Icon(Icons.sports_soccer, size: 14, color: AppColors.gr),
                SizedBox(width: 6),
                Expanded(
                  child: Text('来自「足球速报」App · 每天早上速览绿茵',
                      style: TextStyle(color: AppColors.mu, fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
