import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';
import 'dyn_list.dart';

/// 足坛动态（⚽ 蓝色系标签）
class WorldSection extends StatelessWidget {
  final List<DynItem> items;
  const WorldSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DynListSection(items: items, color: AppColors.blu, fallbackIcon: '⚽');
  }
}
