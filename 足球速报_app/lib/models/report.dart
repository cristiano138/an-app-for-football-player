/// 数据模型：与网页版 report-data.js 的 schema 一一对应（见 内容规范.md 第 86-114 行）。
/// 解析全程容错：字段缺失/类型不对都退回空值，绝不抛异常导致页面崩溃。
library;

class Report {
  final String date;
  final String weekday;
  final String title;
  final String summary;
  final List<String> tags;
  final List<Coverage> coverage;
  final List<Match> matches;
  final List<OtherMatch> others;
  final List<DynItem> stars;
  final List<DynItem> world;
  final List<DynItem> transfer;
  final List<DynItem> schedule;
  final List<PreviewGroup> preview;
  final List<RefGroup> refs;
  final String md;

  const Report({
    required this.date,
    this.weekday = '',
    this.title = '',
    this.summary = '',
    this.tags = const [],
    this.coverage = const [],
    this.matches = const [],
    this.others = const [],
    this.stars = const [],
    this.world = const [],
    this.transfer = const [],
    this.schedule = const [],
    this.preview = const [],
    this.refs = const [],
    this.md = '',
  });

  factory Report.fromJson(dynamic json) {
    final m = _asMap(json);
    return Report(
      date: _str(m['date']),
      weekday: _str(m['weekday']),
      title: _str(m['title']),
      summary: _str(m['summary']),
      tags: _asList(m['tags']).map((e) => _str(e)).where((e) => e.isNotEmpty).toList(),
      coverage: _asList(m['coverage']).map(Coverage.fromJson).toList(),
      matches: _asList(m['matches']).map(Match.fromJson).toList(),
      others: _asList(m['others']).map(OtherMatch.fromJson).toList(),
      stars: _asList(m['stars']).map(DynItem.fromJson).toList(),
      world: _asList(m['world']).map(DynItem.fromJson).toList(),
      transfer: _asList(m['transfer']).map(DynItem.fromJson).toList(),
      schedule: _asList(m['schedule']).map(DynItem.fromJson).toList(),
      preview: _asList(m['preview'])
          .map(PreviewGroup.fromJson)
          .where((g) => g.items.isNotEmpty)
          .toList(),
      refs: _asList(m['refs'])
          .map(RefGroup.fromJson)
          .where((g) => g.links.isNotEmpty)
          .toList(),
      md: _str(m['md']),
    );
  }

  /// 首页卡片/详情页用到的统计
  int get totalGoals {
    var n = 0;
    for (final m in matches) {
      n += m.goals.length;
    }
    return n;
  }

  int get dynCount {
    final pvn = preview.fold<int>(0, (a, g) => a + g.items.length);
    return stars.length + world.length + transfer.length + (pvn > 0 ? pvn : schedule.length);
  }

  /// 用于新旧数据比较（日期新者优先，其次条数多者）
  bool isNewerThan(Report? other) {
    if (other == null || other.date.isEmpty) return true;
    if (date.isEmpty) return false;
    if (date != other.date) return date.compareTo(other.date) > 0;
    return true;
  }
}

class Coverage {
  final String label;
  final String text;
  const Coverage({this.label = '', this.text = ''});

  factory Coverage.fromJson(dynamic json) {
    if (json is String) return Coverage(text: json);
    final m = _asMap(json);
    return Coverage(label: _str(m['label']), text: _str(m['text']));
  }
}

class Goal {
  final String time;
  final String team;
  final String scorer;
  final String assistType;
  final String assist;
  final String desc;
  const Goal({
    this.time = '',
    this.team = '',
    this.scorer = '',
    this.assistType = '',
    this.assist = '',
    this.desc = '',
  });

  factory Goal.fromJson(dynamic json) {
    final m = _asMap(json);
    return Goal(
      time: _str(m['time']),
      team: _str(m['team']),
      scorer: _str(m['scorer']),
      assistType: _str(m['assistType']),
      assist: _str(m['assist']),
      desc: _str(m['desc']),
    );
  }
}

class MatchEvent {
  final String label;
  final String text;
  const MatchEvent({this.label = '', this.text = ''});

  factory MatchEvent.fromJson(dynamic json) {
    if (json is String) return MatchEvent(text: json);
    final m = _asMap(json);
    return MatchEvent(label: _str(m['label']), text: _str(m['text']));
  }
}

class Quote {
  final String speaker;
  final String quote;
  const Quote({this.speaker = '', this.quote = ''});

  factory Quote.fromJson(dynamic json) {
    if (json is String) return Quote(quote: json);
    final m = _asMap(json);
    return Quote(speaker: _str(m['speaker']), quote: _str(m['quote']));
  }
}

class SourceLink {
  final String name;
  final String url;
  const SourceLink({this.name = '', this.url = ''});

  factory SourceLink.fromJson(dynamic json) {
    if (json is String) return SourceLink(name: json);
    final m = _asMap(json);
    return SourceLink(name: _str(m['name']), url: _str(m['url']));
  }
}

class Match {
  final String league;
  final String home;
  final String away;
  final String scoreHome;
  final String scoreAway;
  final String venue;
  final List<Goal> goals;
  final List<MatchEvent> events;
  final List<Quote> pre;
  final List<Quote> post;
  final List<SourceLink> sources;
  const Match({
    this.league = '',
    this.home = '',
    this.away = '',
    this.scoreHome = '',
    this.scoreAway = '',
    this.venue = '',
    this.goals = const [],
    this.events = const [],
    this.pre = const [],
    this.post = const [],
    this.sources = const [],
  });

  factory Match.fromJson(dynamic json) {
    final m = _asMap(json);
    return Match(
      league: _str(m['league']),
      home: _str(m['home']),
      away: _str(m['away']),
      scoreHome: _str(m['scoreHome']),
      scoreAway: _str(m['scoreAway']),
      venue: _str(m['venue']),
      goals: _asList(m['goals']).map(Goal.fromJson).toList(),
      events: _asList(m['events']).map(MatchEvent.fromJson).toList(),
      pre: _asList(m['pre']).map(Quote.fromJson).toList(),
      post: _asList(m['post']).map(Quote.fromJson).toList(),
      sources: _asList(m['sources']).map(SourceLink.fromJson).toList(),
    );
  }

  /// 1=主胜 2=客胜 0=平
  int get winSide {
    final h = int.tryParse(scoreHome);
    final a = int.tryParse(scoreAway);
    if (h == null || a == null) return 0;
    if (h > a) return 1;
    if (h < a) return 2;
    return 0;
  }
}

class OtherMatch {
  final String league;
  final String home;
  final String away;
  final String scoreHome;
  final String scoreAway;
  final String note;
  const OtherMatch({
    this.league = '',
    this.home = '',
    this.away = '',
    this.scoreHome = '',
    this.scoreAway = '',
    this.note = '',
  });

  factory OtherMatch.fromJson(dynamic json) {
    if (json is String) return OtherMatch(home: json);
    final m = _asMap(json);
    return OtherMatch(
      league: _str(m['league']),
      home: _str(m['home']),
      away: _str(m['away']),
      scoreHome: _str(m['scoreHome']),
      scoreAway: _str(m['scoreAway']),
      note: _str(m['note']),
    );
  }

  int get winSide {
    final h = int.tryParse(scoreHome);
    final a = int.tryParse(scoreAway);
    if (h == null || a == null) return 0;
    if (h > a) return 1;
    if (h < a) return 2;
    return 0;
  }
}

class DynItem {
  final String name;
  final String tag;
  final String text;
  const DynItem({this.name = '', this.tag = '', this.text = ''});

  factory DynItem.fromJson(dynamic json) {
    if (json is String) return DynItem(text: json);
    final m = _asMap(json);
    return DynItem(name: _str(m['name']), tag: _str(m['tag']), text: _str(m['text']));
  }
}

class DetailRow {
  final String name;
  final String tag;
  final String text;
  const DetailRow({this.name = '', this.tag = '', this.text = ''});

  factory DetailRow.fromJson(dynamic json) {
    if (json is String) return DetailRow(text: json);
    final m = _asMap(json);
    return DetailRow(name: _str(m['name']), tag: _str(m['tag']), text: _str(m['text']));
  }
}

class PreviewItem {
  final String name;
  final String tag;
  final String text;
  final List<DetailRow> detail;
  const PreviewItem({this.name = '', this.tag = '', this.text = '', this.detail = const []});

  factory PreviewItem.fromJson(dynamic json) {
    final m = _asMap(json);
    return PreviewItem(
      name: _str(m['name']),
      tag: _str(m['tag']),
      text: _str(m['text']),
      detail: _asList(m['detail']).map(DetailRow.fromJson).toList(),
    );
  }

  /// name 形如 `03:30 · 英超`，拆成时间与赛事
  String get timePart {
    final i = name.indexOf('·');
    if (i > 0) return name.substring(0, i).trim();
    return '';
  }

  String get leaguePart {
    final i = name.indexOf('·');
    if (i > 0) return name.substring(i + 1).trim();
    return name;
  }
}

class PreviewGroup {
  final String group;
  final List<PreviewItem> items;
  const PreviewGroup({this.group = '', this.items = const []});

  factory PreviewGroup.fromJson(dynamic json) {
    final m = _asMap(json);
    return PreviewGroup(
      group: _str(m['group']),
      items: _asList(m['items']).map(PreviewItem.fromJson).toList(),
    );
  }
}

class RefLink {
  final String name;
  final String url;
  const RefLink({this.name = '', this.url = ''});

  factory RefLink.fromJson(dynamic json) {
    if (json is String) return RefLink(name: json);
    final m = _asMap(json);
    return RefLink(name: _str(m['name']), url: _str(m['url']));
  }
}

class RefGroup {
  final String group;
  final List<RefLink> links;
  const RefGroup({this.group = '', this.links = const []});

  factory RefGroup.fromJson(dynamic json) {
    final m = _asMap(json);
    return RefGroup(
      group: _str(m['group']),
      links: _asList(m['links']).map(RefLink.fromJson).toList(),
    );
  }
}

// ---------- 工具 ----------

Map<String, dynamic> _asMap(dynamic json) =>
    json is Map<String, dynamic> ? json : <String, dynamic>{};

List<dynamic> _asList(dynamic json) => json is List ? json : const [];

String _str(dynamic v) => v == null ? '' : v.toString();
