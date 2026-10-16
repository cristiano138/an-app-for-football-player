import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../theme/app_theme.dart';
import 'dyn_list.dart';

/// 转会速递（⇄ 紫色系标签）
class TransferSection extends StatelessWidget {
  final List<DynItem> items;
  const TransferSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DynListSection(items: items, color: AppColors.pur, fallbackIcon: '⇄');
  }
}
