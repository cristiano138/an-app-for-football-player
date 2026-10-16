import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// 来源附录：按组折叠，第一组默认展开，链接可点击
class RefsSection extends StatelessWidget {
  final List<RefGroup> groups;
  const RefsSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < groups.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                initiallyExpanded: i == 0,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(groups[i].group.isEmpty ? '来源' : groups[i].group,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('${groups[i].links.length} 条', style: const TextStyle(color: AppColors.mu, fontSize: 11)),
                  ],
                ),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in groups[i].links)
                        if (l.url.isNotEmpty)
                          GestureDetector(
                            onTap: () => openExternal(l.url),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 7),
                                    child: Icon(Icons.link, size: 13, color: AppColors.blu),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(l.name.isEmpty ? l.url : l.name,
                                        style: const TextStyle(color: AppColors.blu, fontSize: 13, height: 1.45)),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(l.name, style: const TextStyle(color: AppColors.tx2, fontSize: 13)),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
