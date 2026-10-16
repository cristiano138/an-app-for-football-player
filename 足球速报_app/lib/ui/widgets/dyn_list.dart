import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';

/// [{name,tag,text}] 通用动态列表：球星动态 / 足坛动态 / 转会速递 / 赛程预告共用。
/// 每个板块用不同强调色（对应网页版 .itag 的颜色区分）。
class DynListSection extends StatelessWidget {
  final List<DynItem> items;
  final Color color;
  final String fallbackIcon;
  const DynListSection({super.key, required this.items, required this.color, this.fallbackIcon = '⚽'});

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
        children: [for (final it in items) _DynRow(item: it, color: color, fallbackIcon: fallbackIcon)],
      ),
    );
  }
}

class _DynRow extends StatelessWidget {
  final DynItem item;
  final Color color;
  final String fallbackIcon;
  const _DynRow({required this.item, required this.color, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final initial = item.name.isNotEmpty ? item.name.characters.first : fallbackIcon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
            child: Text(initial, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.name.isNotEmpty || item.tag.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        // 名字允许换行（最多 3 行）：长球员名如「克里斯蒂亚诺·罗纳尔多」不再被截断
                        child: Text(item.name, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
                      ),
                      if (item.tag.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Text(item.tag,
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                if (item.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(item.text, style: const TextStyle(color: AppColors.tx2, fontSize: 13.5, height: 1.55)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
