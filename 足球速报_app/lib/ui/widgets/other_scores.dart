import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';

/// 其他完赛比分：联赛 + 主队 比分 客队（胜方高亮）+ 备注
class OtherScoresSection extends StatelessWidget {
  final List<OtherMatch> items;
  const OtherScoresSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [for (final o in items) _OtherRow(o)],
      ),
    );
  }
}

class _OtherRow extends StatelessWidget {
  final OtherMatch o;
  const _OtherRow(this.o);

  @override
  Widget build(BuildContext context) {
    final win = o.winSide;
    Color nameColor(int side) => win == side ? AppColors.grLt : AppColors.tx2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (o.league.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(5)),
                  child: Text(o.league, style: const TextStyle(color: AppColors.mu, fontSize: 11)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                // 长队名允许换行（最多 2 行），不再因省略号丢字
                child: Text(o.home, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: TextStyle(color: nameColor(1), fontSize: 14, fontWeight: win == 1 ? FontWeight.w800 : FontWeight.w500, height: 1.25)),
              ),
              const SizedBox(width: 8),
              Text('${o.scoreHome} : ${o.scoreAway}',
                  style: const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(o.away, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nameColor(2), fontSize: 14, fontWeight: win == 2 ? FontWeight.w800 : FontWeight.w500, height: 1.25)),
              ),
            ],
          ),
          if (o.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(o.note, style: const TextStyle(color: AppColors.mu, fontSize: 12, height: 1.45)),
            ),
        ],
      ),
    );
  }
}
