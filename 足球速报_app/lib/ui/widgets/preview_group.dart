import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';

/// 焦点前瞻：有 preview 时按 group 分组渲染（4 个子版块轮换配色）；
/// 没有 preview 时退回 schedule 扁平列表（向后兼容旧数据）。
class PreviewSection extends StatelessWidget {
  final List<PreviewGroup> groups;
  final List<DynItem> schedule;
  const PreviewSection({super.key, this.groups = const [], this.schedule = const []});

  static const _groupColors = [AppColors.gr, AppColors.blu, AppColors.pur, AppColors.ora];

  @override
  Widget build(BuildContext context) {
    // 旧数据降级：schedule 扁平列表
    if (groups.isEmpty) {
      return Column(
        children: [
          for (final it in schedule)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (it.name.isNotEmpty || it.tag.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          // 允许换行：前瞻条目名（如「皇家马德里 vs 巴塞罗那」）不再截断
                          child: Text(it.name, maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
                        ),
                        if (it.tag.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Text(it.tag, style: const TextStyle(color: AppColors.gr, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  if (it.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(it.text, style: const TextStyle(color: AppColors.tx2, fontSize: 13.5, height: 1.5)),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        for (var gi = 0; gi < groups.length; gi++) _groupCard(groups[gi], _groupColors[gi % 4]),
      ],
    );
  }

  Widget _groupCard(PreviewGroup g, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分组标题条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(width: 4, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(g.group.isEmpty ? '前瞻' : g.group,
                      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                Text('${g.items.length} 场', style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (final it in g.items) _PreviewItemView(it, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewItemView extends StatelessWidget {
  final PreviewItem it;
  final Color color;
  const _PreviewItemView(this.it, {this.color = AppColors.gr});

  @override
  Widget build(BuildContext context) {
    // 是否为「赛程型」条目（有时间/有看点明细）：正文是对阵名，用标题样式；
    // 否则是「球星看点」等叙事条目：正文是普通段落。
    final matchLike = it.timePart.isNotEmpty || it.detail.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 首行：时间胶囊 + 联赛/人名 + 标签 —— 全部完整显示，不截断
          if (it.name.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (it.timePart.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(it.timePart,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(it.leaguePart,
                      style: const TextStyle(color: AppColors.tx, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35)),
                ),
                if (it.tag.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(it.tag,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          // 正文：完整换行显示，任何长度都不再省略
          if (it.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: it.name.isNotEmpty ? 3 : 0),
              child: Text(it.text,
                  style: matchLike
                      ? const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w700, height: 1.4)
                      : const TextStyle(color: AppColors.tx2, fontSize: 13, height: 1.55)),
            ),
          for (final d in it.detail)
            if (d.name.isNotEmpty || d.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.name.isNotEmpty)
                      SizedBox(
                        width: 52,
                        child: Text(d.name, style: const TextStyle(color: AppColors.mu, fontSize: 12)),
                      ),
                    Expanded(
                      child: Text(d.text, style: const TextStyle(color: AppColors.tx2, fontSize: 12.5, height: 1.5)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
