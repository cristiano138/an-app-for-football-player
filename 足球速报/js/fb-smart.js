/* ============================================================================
 * 足球速报 · 智能层  (js/fb-smart.js)
 * ----------------------------------------------------------------------------
 * 提供两项能力：
 *   ① 本地检索 —— 把全部历史速报摊平成文档块，建倒排索引，支持球队 / 球员 /
 *      联赛 / 事件 / 日期的检索。纯前端、零依赖、零成本、断网可用。
 *   ② AI 问答 —— LLM 路由器：模型只负责「理解问题」，法规式地约束它只能引用
 *      检索到的真实片段，答案必须带日期出处，材料没有就直说没有。
 *
 * 设计原则（与「出海合规雷达」同一套思路）：
 *   模型 = 理解 + 归纳    确定性代码 = 检索 + 校核
 *   模型无权新增事实，所有结论都能追溯到某一期速报的原文。
 * ========================================================================== */
(function () {
  'use strict';

  /* ==========================================================================
   * 0. 基础配置
   * ======================================================================== */

  var DEF_BASE = 'https://api.deepseek.com/v1';
  var DEF_MODEL = 'deepseek-flash';
  var CFG_KEY = 'fb_ai_cfg';          // API 配置存 localStorage，绝不写进代码
  var HISTORY_KEY = 'fb_ai_history';  // 最近几条提问（仅本地）

  function cfg() {
    try { return JSON.parse(localStorage.getItem(CFG_KEY) || '{}') || {}; } catch (e) { return {}; }
  }
  function saveCfg(o) {
    try { localStorage.setItem(CFG_KEY, JSON.stringify(o)); } catch (e) {}
  }
  function apiBase() { return (cfg().base || DEF_BASE).replace(/\/+$/, ''); }
  function apiModel() { return cfg().model || DEF_MODEL; }
  function hasKey() { return !!(cfg().key && cfg().key.length > 8); }

  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

  /* 页面间传参用的小工具 */
  function qs(name) {
    var m = location.hash.match(new RegExp('[?&]' + name + '=([^&]*)'));
    return m ? decodeURIComponent(m[1]) : '';
  }

  /* ==========================================================================
   * 1. 把日报摊平为文档块
   *    一个文档块 = 检索的最小单位（一场比赛 / 一条动态 / 一段覆盖说明）
   * ======================================================================== */

  var DOCS = [];        // 全部文档块
  var MIN_DATE = '', MAX_DATE = '';

  /* 实体词典：从语料里自动抽出球队 / 球员 / 联赛名。
     比手写别名表靠谱得多 —— 语料里出现过什么，"问 姆巴佩怎么样了" 就能切出「姆巴佩」。 */
  var ENT = {};         // 小写 → 原始写法
  var ENT_ARR = [];     // [{low, name}]，按长度降序，用于最长匹配

  function addEnt(name) {
    if (!name) return;
    name = String(name).trim();
    if (name.length < 2) return;
    if (/^[\d\s\-–—·:：/、,，.。()（）]+$/.test(name)) return;
    var k = name.toLowerCase();
    if (!ENT[k] || ENT[k].length < name.length) ENT[k] = name;
  }
  function buildEntIndex() {
    ENT_ARR = Object.keys(ENT).map(function (k) { return { low: k, name: ENT[k] }; })
      .sort(function (a, b) { return b.low.length - a.low.length; });
  }

  function pushDoc(date, weekday, sect, sectName, title, text, sub) {
    text = String(text || '').replace(/\s+/g, ' ').trim();
    if (!text && !title) return;
    DOCS.push({
      id: DOCS.length,
      date: date,
      weekday: weekday,
      sect: sect,           // matches / others / stars / world / transfer / schedule / preview / coverage
      sectName: sectName,
      title: String(title || '').replace(/\s+/g, ' ').trim(),
      text: text,
      sub: sub || '',
      terms: null           // 延迟分词
    });
  }

  function flatten(reports) {
    DOCS = [];
    reports.forEach(function (r) {
      var d = r.date, w = r.weekday || '';

      /* 覆盖说明：统计窗口、必收球队核对、去重说明 —— 问"这期收了哪些比赛"时有用 */
      (r.coverage || []).forEach(function (c) {
        pushDoc(d, w, 'coverage', '覆盖说明', c.label || '覆盖说明', c.text, '');
      });

      /* 重点场次：一场一个文档块 */
      (r.matches || []).forEach(function (m, i) {
        /* 顺手把实体喂进词典 */
        addEnt(m.home); addEnt(m.away); addEnt(m.league);
        (m.goals || []).forEach(function (g) {
          addEnt(g.scorer);
          if (g.assist && g.assistType === '助攻') addEnt(g.assist);
          addEnt(g.team);
        });
        var title = (m.home || '') + ' ' + (m.scoreHome || '') + '-' + (m.scoreAway || '') + ' ' + (m.away || '');
        var buf = [];
        if (m.league) buf.push('赛事：' + m.league);
        if (m.venue) buf.push(m.venue);
        (m.goals || []).forEach(function (g) {
          buf.push('第' + g.time + ' ' + (g.team || '') + ' ' + (g.scorer || '') +
            (g.assist && g.assistType !== '无助攻' ? '（助攻 ' + g.assist + '）' : '') +
            '：' + (g.desc || ''));
        });
        (m.events || []).forEach(function (e) { buf.push('【' + (e.label || '事件') + '】' + (e.text || '')); });
        (m.pre || []).forEach(function (q) { buf.push('赛前 ' + (q.speaker || '') + '：' + (q.quote || '')); });
        (m.post || []).forEach(function (q) { buf.push('赛后 ' + (q.speaker || '') + '：' + (q.quote || '')); });
        pushDoc(d, w, 'matches', '重点场次', title, buf.join(' '), m.league || '');
      });

      /* 其他完赛比分 */
      (r.others || []).forEach(function (o) {
        var title = (o.home || '') + ' ' + (o.scoreHome || '') + '-' + (o.scoreAway || '') + ' ' + (o.away || '');
        pushDoc(d, w, 'others', '其他比分', title, (o.league || '') + ' ' + (o.note || ''), o.league || '');
      });

      /* 动态类：球星 / 足坛 / 转会 / 前瞻，都是 {name, tag, text} */
      [['stars', '球星动态'], ['world', '足坛动态'], ['transfer', '转会速递'], ['schedule', '焦点前瞻']]
        .forEach(function (pair) {
          (r[pair[0]] || []).forEach(function (it) {
            if (pair[0] === 'stars' || pair[0] === 'transfer') addEnt(it.name);
            var title = (it.name || '') + (it.tag ? ' · ' + it.tag : '');
            pushDoc(d, w, pair[0], pair[1], title, it.text || '', it.tag || '');
          });
        });

      /* 焦点前瞻（带分组和看点明细） */
      (r.preview || []).forEach(function (g, gi) {
        (g.items || []).forEach(function (it, ii) {
          var buf = [it.text || ''];
          (it.detail || []).forEach(function (dt) {
            if (dt && dt.text) buf.push('【' + (dt.name || '') + '】' + dt.text);
          });
          pushDoc(d, w, 'preview', '焦点前瞻',
            (it.name || '') + ' ' + (it.text || '') + (it.tag ? ' · ' + it.tag : ''),
            buf.join(' '), g.group || '');
        });
      });
    });

    if (reports.length) {
      var dates = reports.map(function (r) { return r.date; }).sort();
      MIN_DATE = dates[0];
      MAX_DATE = dates[dates.length - 1];
    }
    buildEntIndex();
  }

  /* ==========================================================================
   * 2. 分词 + 倒排索引
   *    中文没有空格，用「二元组(bigram)」切分：巴塞罗那 → 巴塞 / 塞罗 / 罗那
   *    英文数字按单词切。这是搜索领域最常用的免词典方案。
   * ======================================================================== */

  var STOP = {};
  ('的 了 是 在 有 和 与 及 等 吗 呢 吧 啊 我 你 他 她 它 这 那 什么 哪些 哪个 怎么 如何 为什么 为什 怎样 多少 多久 几个 哪里 请 帮 帮我 找 查 一下 给 说 讲 告诉 介绍 关于 相关 情况 有没有 没有 是不 是的 可以 能否 以及 还有 都 也 就 很 更 最 一个 这周 上周 本周 今天 昨天 明天 前天 最近 近期 现在 目前 这些 那些 他们 我们 你们 以及 或者 还是')
    .split(' ').forEach(function (w) { if (w) STOP[w] = 1; });

  var CJK_RUN = /[\u4e00-\u9fa5]+/g;
  var LATIN = /[a-z0-9]{2,}/g;

  function tokenize(text) {
    var t = String(text || '');
    var lower = t.toLowerCase();
    var out = [];
    var m;
    LATIN.lastIndex = 0;
    while ((m = LATIN.exec(lower))) out.push(m[0]);
    var runs = t.match(CJK_RUN) || [];
    for (var i = 0; i < runs.length; i++) {
      var run = runs[i];
      if (run.length === 1) { out.push(run); continue; }
      for (var j = 0; j < run.length - 1; j++) {
        var g = run.substr(j, 2);
        if (!STOP[g]) out.push(g);
      }
    }
    return out;
  }

  var INDEX = null;   // { post: {token: {docId: tf}}, df: {token: n}, avgLen, N }

  function buildIndex() {
    var post = {}, df = {}, totalLen = 0;
    DOCS.forEach(function (doc) {
      var toks = tokenize(doc.title + ' ' + doc.title + ' ' + doc.sub + ' ' + doc.text); // 标题加权=出现两次
      doc.terms = toks;
      totalLen += toks.length;
      var seen = {}, tf = {};
      toks.forEach(function (t) { tf[t] = (tf[t] || 0) + 1; });
      Object.keys(tf).forEach(function (t) {
        (post[t] = post[t] || {})[doc.id] = tf[t];
        if (!seen[t]) { df[t] = (df[t] || 0) + 1; seen[t] = 1; }
      });
    });
    INDEX = { post: post, df: df, N: DOCS.length || 1, avgLen: (totalLen / (DOCS.length || 1)) || 1 };
  }

  /* ==========================================================================
   * 3. 查询解析：别名归一 + 日期区间 + 关键词抽取
   * ======================================================================== */

  /* 常见简称 → 官方名。用户打「巴萨」，语料里写「巴塞罗那」，必须能对上。 */
  var ALIAS = {
    '巴萨': '巴塞罗那', '皇马': '皇家马德里', '马竞': '马德里竞技', '国米': '国际米兰',
    'ac米兰': 'AC米兰', '米兰': 'AC米兰', '尤文': '尤文图斯', '拜仁': '拜仁慕尼黑',
    '多特': '多特蒙德', '巴黎': '巴黎圣日耳曼', '大巴黎': '巴黎圣日耳曼', '曼联': '曼联',
    '曼城': '曼城', '热刺': '热刺', '枪手': '阿森纳', '蓝军': '切尔西', '红军': '利物浦',
    '马赛': '马赛', '罗马': '罗马', '那不勒斯': '那不勒斯', '亚特兰大': '亚特兰大',
    '本菲卡': '本菲卡', '波尔图': '波尔图', '阿贾克斯': '阿贾克斯', '里昂': '里昂',
    '申花': '上海申花', '海港': '上海海港', '国安': '北京国安', '泰山': '山东泰山',
    '总裁': 'C罗', 'c罗': 'C罗', '梅西': '梅西', '姆总': '姆巴佩', '哈兰德': '哈兰德',
    '贝林': '贝林厄姆', '小熊': '维尼修斯', '凯恩': '凯恩', '魔笛': '莫德里奇'
  };
  var ASPECT_WORDS = {
    '比分': '比分', '赛果': '比分', '结果': '比分', '几比几': '比分', '赢': '比分', '输': '比分',
    '进球': '进球', '破门': '进球', '助攻': '进球', '帽子戏法': '进球',
    '伤病': '伤病', '受伤': '伤病', '伤停': '伤病', '复出': '伤病',
    '转会': '转会', '加盟': '转会', '续约': '转会', '签约': '转会',
    '奖项': '奖项', '金球': '奖项', '评奖': '奖项',
    '赛程': '赛程', '前瞻': '赛程', '下一场': '赛程', '什么时候': '赛程'
  };

  function pad(n) { return n < 10 ? '0' + n : '' + n; }
  function iso(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function shift(days) { var d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + days); return d; }

  /* 把「昨天 / 上周 / 最近」这类相对时间换算成具体日期区间 */
  function parseDateRange(q) {
    var s = String(q || '');
    var from = null, to = null;

    /* 明确写出的 2026-10-15 / 10-15 / 10月15日 */
    var m = s.match(/(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})/);
    if (m) { from = m[1] + '-' + pad(+m[2]) + '-' + pad(+m[3]); to = from; }
    else {
      m = s.match(/(?:^|[^\d])(\d{1,2})[-/月](\d{1,2})(?:日|号)?/);
      if (m) {
        var y = new Date().getFullYear();
        from = y + '-' + pad(+m[1]) + '-' + pad(+m[2]);
        to = from;
      }
    }
    if (from) return { from: from, to: to };

    if (/前天/.test(s)) { return { from: iso(shift(-2)), to: iso(shift(-2)) }; }
    if (/昨天|昨日/.test(s)) { return { from: iso(shift(-1)), to: iso(shift(-1)) }; }
    if (/今天|今日|刚刚|最新/.test(s)) { return { from: iso(shift(0)), to: iso(shift(0)) }; }
    if (/上周|上个星期|上一周/.test(s)) {
      var wd = (new Date().getDay() + 6) % 7;               // 周一=0
      var lastMon = shift(-wd - 7);
      return { from: iso(lastMon), to: iso(new Date(lastMon.getTime() + 6 * 86400000)) };
    }
    if (/本周|这周|这个星期/.test(s)) {
      var wd2 = (new Date().getDay() + 6) % 7;
      return { from: iso(shift(-wd2)), to: iso(shift(0)) };
    }
    if (/最近|近期|这几天|前几天|最近几天/.test(s)) { return { from: iso(shift(-7)), to: iso(shift(0)) }; }
    return { from: null, to: null };
  }

  /* 从问题里抽关键词：去停用词 + 简称补全 + 抽事件词 */
  function extractKeywords(q) {
    var s = String(q || '');
    var kws = [];

    /* 去除疑问句式和日期词，剩下的实词才拿去检索 */
    s = s.replace(/(20\d{2})[-/年]\d{1,2}[-/月]\d{1,2}/g, ' ')
         .replace(/\d{1,2}[-/月]\d{1,2}(日|号)?/g, ' ')
         .replace(/今天|昨天|昨日|前天|明天|本周|上周|这周|最近|近期|现在|目前|这几天|前几天|最新|刚刚/g, ' ');

    /* 先按标点和空格切成短语，再逐段匹配实体词典 */
    var segs = s.split(/[\s,，。！？!?、；;:：()（）"“”'‘’\[\]【】]+/).filter(Boolean);
    segs.forEach(function (seg) {
      var low = seg.toLowerCase();
      var hitEntity = false;

      /* 1) 实体词典最长匹配：语料里出现过的球队 / 球员 / 联赛 */
      for (var i = 0; i < ENT_ARR.length; i++) {
        var e = ENT_ARR[i];
        if (low.indexOf(e.low) >= 0) { kws.push(e.name); hitEntity = true; }
      }

      /* 2) 手写别名表：处理语料里没出现过的简称（巴萨 / 国米 / 大巴黎…） */
      Object.keys(ALIAS).forEach(function (a) {
        if (low.indexOf(a) >= 0) { kws.push(ALIAS[a]); hitEntity = true; }
      });

      /* 3) 事件词：查"伤病／转会"这类横切需求时，事件词本身就是关键词 */
      Object.keys(ASPECT_WORDS).forEach(function (w) {
        if (seg.indexOf(w) >= 0) { kws.push(w); hitEntity = true; }
      });

      /* 4) 没匹配到实体的短词组（≤6 字）本身就是不错的关键词；长句子丢弃，避免噪声 */
      if (!hitEntity) {
        var cleaned = seg.replace(/(哪些|什么|怎么|如何|为什么|有没有|请|帮我|查一下|找一下|告诉我|介绍一下|关于|相关|情况|消息|新闻)/g, '');
        if (cleaned.length >= 2 && cleaned.length <= 6) kws.push(cleaned);
      }
    });

    /* 单个中文实词作补充（如"梅西"被切散时） */
    var runs = s.match(CJK_RUN) || [];
    runs.forEach(function (r) {
      if (r.length >= 2 && r.length <= 6 && !ALIAS[r] && !STOP[r]) {
        for (var i = 0; i < r.length - 1; i++) kws.push(r.substr(i, 2));
      }
    });

    /* 去重 + 去掉纯停用词 */
    var seen = {}, out = [];
    kws.forEach(function (k) {
      k = k.trim();
      if (!k || STOP[k] || seen[k]) return;
      seen[k] = 1; out.push(k);
    });
    return out.slice(0, 12);
  }

  /* 判断某个词是不是"有信息量"的（长度>=2 且不是疑问词） */
  function meaningful(term) { return term && term.length >= 2 && !STOP[term]; }

  /* ==========================================================================
   * 4. 检索打分（BM25 精简版）
   * ======================================================================== */

  /* 问题在问「赛果」还是「前瞻」？决定优先推已完赛还是未开打的内容。
     不区分的话，"尤文那场谁进的球" 会被还没开打的前瞻抢走第一名。 */
  var W_SCORE = /比分|赛果|结果|几比几|进球|破门|谁进|进[了球]|帽子戏法|赢|输|战胜|击败|完赛|战报|复盘/;
  var W_PREVIEW = /前瞻|赛程|下一场|下一轮|什么时候|即将|开球时间|对阵|看点/;

  function search(query, opt) {
    opt = opt || {};
    if (!INDEX) buildIndex();

    var kws = opt.keywords && opt.keywords.length ? opt.keywords : extractKeywords(query);
    var dr = (opt.from || opt.to) ? { from: opt.from || null, to: opt.to || null } : parseDateRange(query);

    /* 意图判断必须看「用户原话」，不能看关键词串 ——
       AI 路径传进来的是 ["巴塞罗那"]，"比分" 这类意图词会丢失 */
    var qs0 = String(opt.raw || query || '') + ' ' + kws.join(' ');
    var askScore = W_SCORE.test(qs0);
    var askPreview = !askScore && W_PREVIEW.test(qs0);

    /* 查询词 → 分词（含别名展开后的词） */
    var qTerms = [];
    kws.forEach(function (k) {
      if (meaningful(k)) {
        tokenize(k).forEach(function (t) { qTerms.push(t); });
        if (/[\u4e00-\u9fa5]{2,}/.test(k)) qTerms.push(k);   // 整词也参与精确加权
      }
    });
    if (!qTerms.length) {
      /* 关键词全是停用词 → 退化为用整句分词 */
      qTerms = tokenize(String(query || '').replace(/[?？。！!，,]/g, ' '));
    }
    if (!qTerms.length) return { hits: [], range: dr, keywords: kws, empty: true };

    var post = INDEX.post, df = INDEX.df, N = INDEX.N, avg = INDEX.avgLen;
    var k1 = 1.2, b = 0.62;
    var scores = {};

    qTerms.forEach(function (t) {
      var p = post[t]; if (!p) return;
      var idf = Math.log(1 + (N - (df[t] || 1) + 0.5) / ((df[t] || 1) + 0.5));
      Object.keys(p).forEach(function (id) {
        var tf = p[id];
        var doc = DOCS[id];
        var len = doc.terms ? doc.terms.length : 1;
        var s = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * len / avg));
        scores[id] = (scores[id] || 0) + s;
      });
    });

    var arr = Object.keys(scores).map(function (id) {
      var doc = DOCS[id];
      var sc = scores[id];
      /* 标题里逐字命中 → 强加权（"巴塞罗那"完整出现在标题里，这条多半就是用户要的） */
      kws.forEach(function (k) {
        if (k.length >= 2 && doc.title.indexOf(k) >= 0) sc *= 2.1;
      });
      /* 时间衰减：越新越靠前，但不至于淹没老新闻 */
      var age = (new Date(MAX_DATE) - new Date(doc.date)) / 86400000;
      sc *= (1 + 0.5 / (1 + Math.max(0, age)));
      /* 日期区间过滤 */
      if (dr.from && doc.date < dr.from) sc *= 0.06;
      if (dr.to && doc.date > dr.to) sc *= 0.06;
      /* 板块偏好 */
      if (opt.sect && doc.sect === opt.sect) sc *= 1.6;
      /* 意图偏好：问赛果就压前瞻，问前瞻就压赛果 */
      if (askScore) {
        if (doc.sect === 'matches') sc *= 2.4;
        else if (doc.sect === 'others') sc *= 2.0;
        else if (doc.sect === 'preview' || doc.sect === 'schedule') sc *= 0.4;
      } else if (askPreview) {
        if (doc.sect === 'preview' || doc.sect === 'schedule') sc *= 2.0;
        else if (doc.sect === 'matches') sc *= 0.7;
      }
      return { doc: doc, score: sc };
    });

    arr.sort(function (a, b2) { return b2.score - a.score; });
    return { hits: arr.slice(0, opt.limit || 30), range: dr, keywords: kws };
  }

  /* 命中片段：取第一个命中词附近的上下文，并把命中词包成 <mark> */
  function snippet(doc, kws, width) {
    width = width || 100;
    var text = doc.text || '';
    var pos = -1, hit = '';
    for (var i = 0; i < kws.length; i++) {
      var k = kws[i];
      if (!meaningful(k)) continue;
      var p = text.indexOf(k);
      if (p < 0) p = doc.title.indexOf(k) >= 0 ? 0 : -1;
      if (p >= 0) { pos = p; hit = k; break; }
    }
    var out;
    if (pos < 0) {
      out = text.slice(0, width * 2);
    } else {
      var start = Math.max(0, pos - 30);
      out = (start > 0 ? '…' : '') + text.slice(start, start + width * 2) + (start + width * 2 < text.length ? '…' : '');
    }
    var safe = esc(out);
    kws.forEach(function (k) {
      if (!meaningful(k) || k.length < 2) return;
      safe = safe.split(esc(k)).join('<mark>' + esc(k) + '</mark>');
    });
    return safe;
  }

  /* ==========================================================================
   * 5. LLM 路由器
   *    第 1 跳：问题 → 结构化意图（模型只做理解）
   *    第 2 跳：真实片段 → 归纳成回答（模型只做归纳，禁止补充）
   *    API 不可用时，整体降级为「纯本地检索」，绝不白屏。
   * ======================================================================== */

  function chat(messages, opt) {
    opt = opt || {};
    if (!hasKey()) return Promise.reject(new Error('NO_KEY'));
    var c = cfg();
    return fetch(apiBase() + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + c.key },
      body: JSON.stringify({
        model: apiModel(),
        messages: messages,
        max_tokens: opt.max_tokens || 1600,
        temperature: opt.temperature == null ? 0.2 : opt.temperature,
        stream: false
      })
    }).then(function (r) {
      if (!r.ok) {
        return r.text().then(function (t) {
          var msg = 'HTTP ' + r.status;
          try { var j = JSON.parse(t); if (j.error && j.error.message) msg += '：' + j.error.message; } catch (e) {}
          throw new Error(msg);
        });
      }
      return r.json();
    }).then(function (j) {
      var ch = (j.choices && j.choices[0]) || {};
      var m = ch.message || {};
      var text = (m.content || '').trim();
      /* 推理模型把 token 花在思考上时 content 会是空的，这里明确报错，让上层降级 */
      if (!text) {
        if (ch.finish_reason === 'length') throw new Error('模型输出被截断（max_tokens 不足）');
        throw new Error('模型返回了空内容');
      }
      return text;
    });
  }

  function today() { var d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }

  /* 注意：这段提示词里带日期范围，必须在索引建好之后才生成，
     否则会拼出空日期（模块加载时 MIN_DATE 还是空字符串）。 */
  function routeSys() {
    /* "上周" 的真实区间（周一~周日），写进示例里给模型做参照 */
    var wd = (new Date().getDay() + 6) % 7;
    var lastMon = iso(shift(-wd - 7));
    var lastSun = iso(new Date(shift(-wd - 7).getTime() + 6 * 86400000));
    return '你是「足球速报」的查询解析器，不是聊天助手。请把用户的问题解析成 JSON。\n' +
      '【数据库范围】速报只收录 ' + MIN_DATE + ' 至 ' + MAX_DATE + ' 的足球内容，' +
      '包含：重点场次（比分/进球/红黄牌/var/积分）、其他完赛比分、球星动态、足坛动态、转会速递、焦点前瞻。\n' +
      '【只输出 JSON，不要解释，不要 markdown 代码块】字段如下：\n' +
      '  action: "search"（需要查速报数据）｜"chat"（打招呼、闲聊，与数据无关）｜"reject"（问题超出足球速报范围）\n' +
      '  keywords: 字符串数组。从问题里抽出的检索词（球队、球员、联赛、事件），去掉疑问词。\n' +
      '            简称必须补成语料里的写法：巴萨→巴塞罗那，皇马→皇家马德里，国米→国际米兰，尤文→尤文图斯，拜仁→拜仁慕尼黑，大巴黎→巴黎圣日耳曼，马竞→马德里竞技。\n' +
      '  date_from / date_to: "YYYY-MM-DD" 或 null。用户说"昨天/上周/最近/这两天"时，必须换算成具体日期。\n' +
      '            今天是 ' + today() + '；"上周"指 ' + lastMon + '（周一）至 ' + lastSun + '（周日）；"最近一周"指从今天往前推 7 天。\n' +
      '            没有提到时间就只能填 null，不要自己假设时间范围。\n' +
      '  aspect: "比分"｜"进球"｜"伤病"｜"转会"｜"奖项"｜"赛程"｜"采访"｜"综合"\n' +
      '  question_type: "统计"（问次数、几场、多少）｜"事实"（问某件事）｜"汇总"（问整体情况）\n\n' +
      '示例：\n' +
      '问"巴萨最近怎么样？" → {"action":"search","keywords":["巴塞罗那"],"date_from":null,"date_to":null,"aspect":"综合","question_type":"汇总"}\n' +
      '问"上周有哪些伤病消息" → {"action":"search","keywords":["伤病"],"date_from":"' + lastMon + '","date_to":"' + lastSun + '","aspect":"伤病","question_type":"汇总"}\n' +
      '问"你好" → {"action":"chat","keywords":[],"date_from":null,"date_to":null,"aspect":"综合","question_type":"事实"}\n' +
      '问"帮我写一首诗" → {"action":"reject","keywords":[],"date_from":null,"date_to":null,"aspect":"综合","question_type":"事实"}';
  }

  function parseJSON(t) {
    if (!t) return null;
    var s = t.replace(/```json/gi, '').replace(/```/g, '').trim();
    var i = s.indexOf('{'), j = s.lastIndexOf('}');
    if (i < 0 || j <= i) return null;
    try { return JSON.parse(s.slice(i, j + 1)); } catch (e) { return null; }
  }

  var ANSWER_SYS =
    '你是「足球速报」的问答助手。用户问题会先由检索程序查库，下面给你的【材料】就是检索到的全部相关内容。\n' +
    '硬规则（必须遵守）：\n' +
    '1. 只能使用【材料】里出现的事实。绝对不要补充材料之外的知识，哪怕是常识。\n' +
    '2. 每条结论后面用括号标注出处日期，例如（10-15）。\n' +
    '3. 材料里找不到的，直接写"速报里没有相关记录"，不要推测、不要编造。\n' +
    '4. 简体中文，可以用短列表，总长不超过 250 字。不要输出 markdown 标题，不要复述规则。\n' +
    '5. 如果材料之间时间不一致，以日期新的为准并说明。';

  /* 把检索结果压缩成给模型看的材料（控制 token：每条截断） */
  function buildContext(hits, limit) {
    var out = [], used = 0;
    for (var i = 0; i < hits.length && i < (limit || 8); i++) {
      var d = hits[i].doc;
      var body = (d.title ? d.title + ' —— ' : '') + d.text;
      if (body.length > 900) body = body.slice(0, 900) + '…';
      out.push('[' + d.date + '][ ' + d.sectName + ' ] ' + body);
      used += body.length;
      if (used > 7000) break;
    }
    return out.join('\n\n');
  }

  /* 本地兜底：不花 token 也能回答的常见情况 */
  var HELLO = /^(你好|您好|hi|hello|嗨|在吗|哈喽|早上好|晚上好|下午好)[!！。~～]*$/i;

  /**
   * 主流程：提问 → 路由 → 检索 → 归纳
   * onStage(text) 用于给界面反馈当前进度
   */
  function ask(question, onStage) {
    var stage = onStage || function () {};
    var q = String(question || '').trim();
    if (!q) return Promise.reject(new Error('请输入问题'));

    var result = { question: q, mode: 'local', intent: null, hits: [], answer: '', notice: '', error: '' };

    /* --- 没有一个 API key：直接降级为本地检索，不报错 --- */
    if (!hasKey()) {
      var local0 = search(q, { limit: 12 });
      result.mode = 'local';
      result.hits = local0.hits;
      result.notice = '未配置 API key，已用本地检索回答（结果不经过 AI 归纳）。';
      return Promise.resolve(result);
    }

    /* --- 打招呼这类不需要查库的，本地直接回，省一次调用 --- */
    if (HELLO.test(q)) {
      result.mode = 'chat';
      result.answer = '你好！我是足球速报的问答助手。你可以问我：\n· 巴萨最近几场比分如何？\n· 上周有哪些伤病消息？\n· 金球奖相关的动态有哪些？\n我的回答全部来自已发布的速报原文，并会标注日期。';
      return Promise.resolve(result);
    }

    /* --- 第 1 跳：路由（模型只做理解） --- */
    stage('正在理解问题…');
    return chat([
      { role: 'system', content: routeSys() },
      { role: 'user', content: q }
    ], { max_tokens: 1200, temperature: 0 })
      .then(function (t) { return parseJSON(t); })
      .catch(function (e) {
        result.error = e.message === 'NO_KEY' ? '' : ('路由模型不可用（' + e.message + '），已改为本地检索。');
        return null;
      })
      .then(function (intent) {
        /* 路由失败的降级：把整句当关键词做本地检索 */
        if (!intent || !intent.action) {
          var lf = search(q, { limit: 20 });
          result.mode = 'local';
          result.hits = lf.hits;
          result.notice = result.error || '模型没返回可解析的意图，已改为本地检索。';
          return result;
        }
        result.intent = intent;

        if (intent.action === 'chat') {
          result.mode = 'chat';
          result.answer = '这个问题不用查速报～你可以问我具体的内容，比如「皇马最近比分」「上周有什么伤病消息」「金秋奖相关动态」。我只会依据速报原文回答，并标注日期。';
          return result;
        }
        if (intent.action === 'reject') {
          result.mode = 'reject';
          result.answer = '这个问题超出了足球速报的范围。我的数据只有 ' + MIN_DATE + ' 至 ' + MAX_DATE +
            ' 的赛事速报（比分、进球、球星动态、转会、前瞻）。换个和这段时间足球相关的问题试试？';
          return result;
        }

        /* --- 第 2 步：本地检索（确定性代码，0 token） --- */
        stage('正在检索速报数据库…');
        var kws = (intent.keywords || []).filter(Boolean);
        var sr = search(kws.length ? kws.join(' ') : q, {
          keywords: kws.length ? kws : extractKeywords(q),
          from: intent.date_from || null,
          to: intent.date_to || null,
          raw: q,
          limit: 24
        });
        result.keywords = sr.keywords;
        result.range = sr.range;

        /* 检索为空：不必再花一次调用，直接如实告知 */
        if (!sr.hits.length) {
          result.mode = 'local';
          result.hits = [];
          result.notice = '速报里没有检索到相关记录。';
          return result;
        }
        result.hits = sr.hits;

        /* --- 第 3 步：把真实片段喂给模型归纳 --- */
        stage('正在依据原文归纳答案…');
        var ctx = buildContext(sr.hits, 8);
        return chat([
          { role: 'system', content: ANSWER_SYS },
          { role: 'user', content: '【用户问题】' + q + '\n\n【材料】\n' + ctx }
        ], { max_tokens: 2400, temperature: 0.3 })
          .then(function (ans) {
            result.mode = 'ai';
            result.answer = ans;
            return result;
          })
          .catch(function (e) {
            result.mode = 'local';
            result.notice = 'AI 归纳不可用（' + e.message + '），下面是检索到的原文片段。';
            return result;
          });
      });
  }

  /* ==========================================================================
   * 6. 界面：搜索页
   * ======================================================================== */

  var lastQuery = '';

  var QUICK = ['巴塞罗那', '皇家马德里', 'C罗', '梅西', '伤病', '转会', '金球', '尤文图斯'];

  function smartEntryBar() {
    return '<div class="sm-entry">' +
      '<button class="sm-b" onclick="FBSmart.go(\'search\')"><span class="ic">🔍</span>' +
      '<span class="tx"><b>搜索速报</b><i>按球队 / 球员 / 事件查</i></span><span class="go">›</span></button>' +
      '<button class="sm-b ai" onclick="FBSmart.go(\'ask\')"><span class="ic">🤖</span>' +
      '<span class="tx"><b>问 AI</b><i>答案带日期出处</i></span><span class="go">›</span></button>' +
      '</div>';
  }

  function go(where) { location.hash = '#/' + where; }

  function renderSearch(preset) {
    var listEl = document.getElementById('list'), detailEl = document.getElementById('detail');
    detailEl.style.display = 'none'; listEl.style.display = '';
    document.getElementById('back').style.display = 'none';
    document.body.classList.remove('detail-open');
    document.getElementById('tabbar').classList.remove('show');
    document.getElementById('title').textContent = '搜索速报';
    document.getElementById('sub').textContent = DOCS.length + ' 条记录';
    document.getElementById('foot').textContent = '检索在本机完成，不联网、不消耗任何额度';

    var q = preset != null ? preset : qs('q');
    lastQuery = q;

    listEl.innerHTML =
      '<div class="sm-search">' +
        '<div class="sm-box"><span class="mg">🔍</span>' +
          '<input id="smq" type="search" placeholder="搜球队、球员、事件，如：巴萨 / 梅西 / 伤病" value="' + esc(q) + '" autocomplete="off">' +
          (q ? '<button class="clr" onclick="FBSmart.clearSearch()">×</button>' : '') +
        '</div>' +
        '<div class="sm-quick">' + QUICK.map(function (k) {
          return '<button onclick="FBSmart.quick(\'' + k + '\')">' + esc(k) + '</button>';
        }).join('') + '</div>' +
      '</div>' +
      '<div id="smres"></div>';

    var input = document.getElementById('smq');
    var timer = null;
    input.addEventListener('input', function () {
      clearTimeout(timer);
      timer = setTimeout(function () { runSearch(input.value); }, 180);
    });
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') { clearTimeout(timer); runSearch(input.value); input.blur(); } });

    runSearch(q);
  }

  function clearSearch() {
    var i = document.getElementById('smq');
    if (i) { i.value = ''; i.focus(); }
    runSearch('');
  }

  function quick(k) {
    var i = document.getElementById('smq');
    if (i) i.value = k;
    runSearch(k);
  }

  function runSearch(q) {
    var box = document.getElementById('smres');
    if (!box) return;
    lastQuery = q;
    if (!String(q).trim()) {
      box.innerHTML = '<div class="sm-empty">输入关键词开始搜索<br><span>支持：球队（巴萨）、球员（C罗）、事件（伤病／转会／金球奖）、日期（10-15）</span></div>';
      return;
    }
    var r = search(q, { limit: 40 });
    if (!r.hits.length) {
      box.innerHTML = '<div class="sm-empty">没找到「' + esc(q) + '」相关的记录<br><span>换个说法试试，比如用球队全称、球员姓氏，或去掉修饰词</span></div>';
      return;
    }
    var range = (r.range.from || r.range.to) ?
      '<div class="sm-range">已按日期过滤：' + esc(r.range.from || '…') + ' ~ ' + esc(r.range.to || '…') + '</div>' : '';

    /* 按日期分组展示，更有"速报"的感觉 */
    var groups = {}, order = [];
    r.hits.forEach(function (h) {
      var d = h.doc.date;
      if (!groups[d]) { groups[d] = []; order.push(d); }
      groups[d].push(h);
    });

    var h = range + '<div class="sm-count">命中 <b>' + r.hits.length + '</b> 条' +
      (r.keywords && r.keywords.length ? ' · 关键词：' + esc(r.keywords.slice(0, 5).join('、')) : '') + '</div>';

    order.forEach(function (d) {
      h += '<div class="sm-day"><div class="sm-dh">' + esc(d) + '</div>';
      groups[d].slice(0, 12).forEach(function (hit) {
        var doc = hit.doc;
        h += '<div class="sm-hit" onclick="FBSmart.jump(\'' + esc(doc.date) + '\',\'' + esc(doc.sect) + '\')">' +
          '<div class="sm-ht"><span class="tag">' + esc(doc.sectName) + '</span>' +
          '<span class="ti">' + esc(doc.title || doc.text.slice(0, 40)) + '</span></div>' +
          (doc.text ? '<div class="sm-hp">' + snippet(doc, r.keywords, 90) + '</div>' : '') +
          '</div>';
      });
      h += '</div>';
    });
    box.innerHTML = h;
  }

  /* 点搜索结果 → 打开该期日报，并跳到命中板块 */
  function jump(date, sect) {
    if (typeof openReport === 'function') openReport(date);
    var anchor = ({ matches: 'matches', others: 'others', preview: 'preview', coverage: 'matches' })[sect] || 'dyn';
    setTimeout(function () {
      if (typeof jumpTo === 'function') jumpTo(anchor);
    }, 320);
  }

  /* ==========================================================================
   * 7. 界面：提问页
   * ======================================================================== */

  var SAMPLE_Q = ['巴萨最近几场比分如何？', '上周有哪些伤病消息？', 'C罗现在进了多少球？', '有哪些转会已经敲定了？'];
  var convo = [];   // 本次会话的问答记录

  function renderAsk() {
    var listEl = document.getElementById('list'), detailEl = document.getElementById('detail');
    detailEl.style.display = 'none'; listEl.style.display = '';
    document.getElementById('back').style.display = 'none';
    document.body.classList.remove('detail-open');
    document.getElementById('tabbar').classList.remove('show');
    document.getElementById('title').textContent = '问 AI';
    document.getElementById('sub').textContent = '';
    document.getElementById('foot').textContent = 'AI 只依据速报原文回答，每条结论都标注来源日期';

    var c = cfg();
    var status = hasKey()
      ? '<div class="ai-status ok"><span class="d"></span>' +
        '<span class="msg">已接入 <b>' + esc(apiModel()) + '</b></span>' +
        '<button onclick="FBSmart.openSettings()">设置</button></div>'
      : '<div class="ai-status warn"><span class="d"></span>' +
        '<span class="msg">未配置 API key。<b>搜索功能照常可用</b>，提问需先填入你自己的 key</span>' +
        '<button onclick="FBSmart.openSettings()">去配置</button></div>';

    listEl.innerHTML =
      status +
      '<div id="aiSettings" class="ai-set" style="display:none">' +
        '<label>API Key <span>只存在你这台设备的浏览器里，不会上传、不会写进代码</span></label>' +
        '<input id="aiKey" type="password" placeholder="sk-..." value="' + esc(c.key || '') + '">' +
        '<label>接口地址 <span>默认 DeepSeek 官方</span></label>' +
        '<input id="aiBase" type="text" placeholder="' + DEF_BASE + '" value="' + esc(c.base || '') + '">' +
        '<label>模型 <span>deepseek-flash 更快更省，deepseek-v4-pro 更强</span></label>' +
        '<input id="aiModel" type="text" placeholder="' + DEF_MODEL + '" value="' + esc(c.model || '') + '">' +
        '<div class="ai-set-btns">' +
          '<button class="ok" onclick="FBSmart.saveSettings()">保存</button>' +
          '<button onclick="FBSmart.testKey()">测试连接</button>' +
          '<button class="del" onclick="FBSmart.clearKey()">清除</button>' +
        '</div>' +
        '<div id="aiTest" class="ai-test"></div>' +
      '</div>' +
      '<div class="ai-convo" id="aiConvo"></div>' +
      '<div class="ai-samples" id="aiSamples"></div>' +
      '<div class="ai-ask">' +
        '<input id="aiq" type="text" placeholder="用大白话问，例如：皇马最近赢了吗？" autocomplete="off">' +
        '<button id="aibtn" onclick="FBSmart.submit()">提问</button>' +
      '</div>';

    renderSamples();
    renderConvo();
    var i = document.getElementById('aiq');
    i.addEventListener('keydown', function (e) { if (e.key === 'Enter') submit(); });
  }

  function renderSamples() {
    var el = document.getElementById('aiSamples');
    if (!el) return;
    if (convo.length) { el.innerHTML = ''; return; }
    el.innerHTML = '<div class="ai-ttl">试试这样问</div>' + SAMPLE_Q.map(function (s) {
      return '<button onclick="FBSmart.fill(\'' + esc(s.replace(/'/g, '')) + '\')">' + esc(s) + '</button>';
    }).join('');
  }

  function fill(s) {
    var i = document.getElementById('aiq');
    if (i) { i.value = s; i.focus(); }
  }

  function renderConvo() {
    var el = document.getElementById('aiConvo');
    if (!el) return;
    if (!convo.length) {
      el.innerHTML = '<div class="ai-hello">' +
        '<div class="t">🤖 问我任何关于速报的问题</div>' +
        '<div class="s">我的数据是 ' + MIN_DATE + ' 至 ' + MAX_DATE + ' 的 ' + DOCS.length + ' 条速报记录。' +
        '回答时会先在本机检索原文，再交给模型归纳 —— <b>材料里没有的，我会直接说没有</b>，不会编。</div>' +
        '</div>';
      return;
    }
    var h = '';
    convo.forEach(function (m) {
      h += '<div class="ai-q">' + esc(m.question) + '</div>';
      if (m.loading) { h += '<div class="ai-a loading"><span class="spin"></span>' + esc(m.stage || '处理中…') + '</div>'; return; }
      h += '<div class="ai-a">';
      if (m.answer) h += '<div class="txt">' + esc(m.answer).replace(/\n/g, '<br>') + '</div>';

      /* 意图展示：让用户看到"路由器"把问题解析成了什么 */
      if (m.intent && m.mode === 'ai') {
        var kk = (m.intent.keywords || []).join('、') || '—';
        h += '<div class="route">' +
          '<span>意图 <b>' + esc(m.intent.aspect || '综合') + '</b></span>' +
          '<span>关键词 <b>' + esc(kk) + '</b></span>' +
          (m.intent.date_from ? '<span>时间 <b>' + esc(m.intent.date_from) + (m.intent.date_to && m.intent.date_to !== m.intent.date_from ? ' ~ ' + esc(m.intent.date_to) : '') + '</b></span>' : '') +
          '<span>依据 <b>' + (m.hits ? m.hits.length : 0) + ' 条原文</b></span>' +
          '</div>';
      }
      if (m.notice) h += '<div class="notice">' + esc(m.notice) + '</div>';

      /* 命中的原文片段，默认折叠 —— 用户可自行核对答案有没有依据 */
      if (m.hits && m.hits.length) {
        h += '<details class="evi"><summary>查看依据的 ' + m.hits.length + ' 条原文</summary><div class="evibody">';
        m.hits.slice(0, 8).forEach(function (hit) {
          h += '<div class="evi-item" onclick="FBSmart.jump(\'' + esc(hit.doc.date) + '\',\'' + esc(hit.doc.sect) + '\')">' +
            '<span class="dt">' + esc(hit.doc.date) + '</span>' +
            '<span class="sn">' + esc(hit.doc.sectName) + '</span>' +
            '<span class="tx">' + esc((hit.doc.title || hit.doc.text).slice(0, 60)) + '</span></div>';
        });
        h += '</div></details>';
      }
      h += '</div>';
    });
    el.innerHTML = h;
  }

  function submit() {
    var i = document.getElementById('aiq');
    var btn = document.getElementById('aibtn');
    var q = i ? i.value.trim() : '';
    if (!q) return;
    i.value = '';
    if (btn) btn.disabled = true;

    var msg = { question: q, loading: true, stage: '准备中…' };
    convo.push(msg);
    renderSamples();
    renderConvo();
    scrollConvo();

    ask(q, function (stage) {
      msg.stage = stage;
      renderConvo();
      scrollConvo();
    }).then(function (res) {
      msg.loading = false;
      msg.mode = res.mode;
      msg.answer = res.answer;
      msg.intent = res.intent || null;
      msg.hits = res.hits || [];
      msg.notice = res.notice || '';
    }).catch(function (e) {
      msg.loading = false;
      msg.notice = '出错了：' + e.message;
      msg.hits = [];
    }).then(function () {
      if (btn) btn.disabled = false;
      renderConvo();
      scrollConvo();
    });
  }

  function scrollConvo() {
    setTimeout(function () {
      var el = document.getElementById('aiConvo');
      if (el && el.lastElementChild) el.lastElementChild.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }, 60);
  }

  /* -------- 设置面板 -------- */
  function openSettings() {
    var el = document.getElementById('aiSettings');
    if (!el) return;
    el.style.display = el.style.display === 'none' ? '' : 'none';
  }
  function saveSettings() {
    var k = (document.getElementById('aiKey').value || '').trim();
    var b = (document.getElementById('aiBase').value || '').trim();
    var m = (document.getElementById('aiModel').value || '').trim();
    if (!k) { alert('请先填 API Key'); return; }
    saveCfg({ key: k, base: b || DEF_BASE, model: m || DEF_MODEL });
    renderAsk();
    var st = document.getElementById('aiTest');
    if (st) { st.textContent = '已保存 ✓'; st.className = 'ai-test ok'; }
  }
  function clearKey() {
    if (!confirm('确定要清除本机保存的 API key 吗？清除后提问功能会停用，搜索不受影响。')) return;
    saveCfg({});
    renderAsk();
  }
  function testKey() {
    var st = document.getElementById('aiTest');
    var k = (document.getElementById('aiKey').value || '').trim();
    if (!k) { if (st) { st.textContent = '请先填 API Key'; st.className = 'ai-test bad'; } return; }
    /* 先存后测，保证用用户刚填的值 */
    saveCfg({
      key: k,
      base: (document.getElementById('aiBase').value || '').trim() || DEF_BASE,
      model: (document.getElementById('aiModel').value || '').trim() || DEF_MODEL
    });
    if (st) { st.textContent = '测试中…'; st.className = 'ai-test'; }
    chat([{ role: 'user', content: '回复两个字：通了' }], { max_tokens: 600 }).then(function () {
      if (st) { st.textContent = '连接成功 ✓ 模型可用'; st.className = 'ai-test ok'; }
      renderAsk();
      var t = document.getElementById('aiTest');
      if (t) { t.textContent = '连接成功 ✓ 模型可用'; t.className = 'ai-test ok'; }
    }).catch(function (e) {
      if (st) { st.textContent = '失败：' + e.message; st.className = 'ai-test bad'; }
    });
  }

  /* ==========================================================================
   * 8. 对外接口 + 路由接管
   * ======================================================================== */

  var API = {
    build: function (reports) { flatten(reports); buildIndex(); },
    search: search,
    ask: ask,
    go: go,
    renderSearch: renderSearch,
    renderAsk: renderAsk,
    runSearch: runSearch,
    quick: quick,
    clearSearch: clearSearch,
    jump: jump,
    submit: submit,
    fill: fill,
    openSettings: openSettings,
    saveSettings: saveSettings,
    clearKey: clearKey,
    testKey: testKey,
    entryBar: smartEntryBar,
    hasKey: hasKey,
    stats: function () { return { docs: DOCS.length, min: MIN_DATE, max: MAX_DATE }; }
  };
  window.FBSmart = API;

  /* 等主脚本把 REPORTS 规整好之后再建索引 */
  function boot() {
    var reports = (typeof REPORTS !== 'undefined' && REPORTS) ? REPORTS : (window.REPORTS || []);
    API.build(reports);

    /* 顶部 header 是 sticky 的，高度随刘海屏/字号变化 ——
       量出真实高度写进 CSS 变量，搜索框才不会被 header 盖住 */
    function syncHead() {
      var hd = document.querySelector('header');
      if (hd && hd.offsetHeight) {
        document.documentElement.style.setProperty('--sm-hd', hd.offsetHeight + 'px');
      }
    }
    syncHead();
    window.addEventListener('resize', syncHead);
    window.addEventListener('hashchange', function () { setTimeout(syncHead, 60); });

    /* 接管 hash 路由：新增 #/search 与 #/ask 两个页面 */
    if (typeof window.route === 'function') {
      var base = window.route;
      window.route = function () {
        var h = location.hash;
        if (h.indexOf('#/search') === 0) return renderSearch();
        if (h.indexOf('#/ask') === 0) return renderAsk();
        return base.apply(this, arguments);
      };
      /* 首屏可能就是搜索页 / 提问页（直接分享链接进来），补一次路由 */
      if (location.hash.indexOf('#/search') === 0 || location.hash.indexOf('#/ask') === 0) {
        window.route();
      }
    }

    /* 主脚本渲染列表时本文件还没加载，入口条没进去 —— 在首页补渲染一次 */
    var h0 = location.hash;
    if (h0.indexOf('#/r/') !== 0 && h0.indexOf('#/search') !== 0 && h0.indexOf('#/ask') !== 0) {
      if (typeof renderList === 'function') renderList();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
