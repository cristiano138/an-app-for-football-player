import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

/// 渐变绿头部（与网页版 header 一致：135deg #14805D → #0A4E3A）
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  const GradientAppBar({super.key, required this.title, this.subtitle, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
      actions: actions,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.grDk, AppColors.grDk2],
          ),
        ),
      ),
    );
  }
}

/// 小圆角标签（动态条目的 tag 等）
class TagChip extends StatelessWidget {
  final String text;
  final Color color;
  const TagChip(this.text, {super.key, this.color = AppColors.gr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// 通用浅色小胶囊（venue 片段、时间等）
class SoftChip extends StatelessWidget {
  final String text;
  final Color? fg;
  final Color? bg;
  const SoftChip(this.text, {super.key, this.fg, this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? AppColors.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: fg ?? AppColors.tx2, fontSize: 12)),
    );
  }
}

/// 板块标题：左侧强调条 + emoji + 标题 + 右侧统计
class SectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String? stat;
  const SectionHeader({super.key, required this.emoji, required this.title, this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.gr, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 4),
          Text(title, style: const TextStyle(color: AppColors.tx, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (stat != null) Text(stat!, style: const TextStyle(color: AppColors.mu, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 小节标题（卡片内）：前置细条 + 标题 + 右侧数量
class BlockHeader extends StatelessWidget {
  final String title;
  final String? count;
  const BlockHeader(this.title, {super.key, this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 3, height: 12, decoration: BoxDecoration(color: AppColors.gr, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Text(title, style: const TextStyle(color: AppColors.tx, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: AppColors.grL, borderRadius: BorderRadius.circular(9)),
              child: Text(count!, style: const TextStyle(color: AppColors.gr, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// 行内轻量 markdown：支持 **加粗**、*斜体*、[文字](链接)，链接可点击
class InlineText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  const InlineText(this.text, {super.key, this.style, this.maxLines});

  static final _tokenRe = RegExp(r'(\*\*[^*]+\*\*|\*[^*\n]+\*|\[[^\]]+\]\([^)]+\))');

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(color: AppColors.tx, fontSize: 14, height: 1.55);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in _tokenRe.allMatches(text)) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(text: tok.substring(2, tok.length - 2), style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (tok.startsWith('*')) {
        spans.add(TextSpan(text: tok.substring(1, tok.length - 1), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else {
        final linkRe = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
        final lm = linkRe.firstMatch(tok);
        final label = lm?.group(1) ?? tok;
        final url = lm?.group(2) ?? '';
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: url.isEmpty ? null : () => _open(url),
            child: Text(label,
                style: base.copyWith(color: AppColors.blu, decoration: TextDecoration.underline)),
          ),
        ));
      }
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}

/// 外部链接统一入口
Future<void> openExternal(String url) async => InlineText._open(url);
