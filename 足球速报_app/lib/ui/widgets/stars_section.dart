import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';
import 'dyn_list.dart';

/// 球星动态（★ 黄色系标签）
class StarsSection extends StatelessWidget {
  final List<DynItem> items;
  const StarsSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DynListSection(items: items, color: AppColors.yel, fallbackIcon: '★');
  }
}
