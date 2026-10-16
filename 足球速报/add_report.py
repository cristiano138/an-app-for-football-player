# -*- coding: utf-8 -*-
"""把定时任务生成的足球速报 md 解析成结构化数据，供「足球速报」App 使用。

用法：
  python add_report.py                 # 扫描 E:\\workbuddy\\定时任务 下的 足球速报-*.md 全部导入
  python add_report.py <md路径> ...    # 只导入指定文件

输出 E:\\workbuddy\\足球速报\\report-data.js（window.REPORTS = [...]），同日期覆盖，按日期倒序。
解析依赖 md 的结构：# 标题（含日期与周X）、## 一/二/三 三个大节、### 每场重点比赛、
块内以 **小节名** 独占行分隔（进球全记录 / 其他重大事件 / 赛前采访 / 赛后采访 / 来源）。
解析失败时会退化为只保留 md 原文，App 端会自动用 Markdown 兜底渲染。
"""
import glob
import json
import os
import re
import sys

PROJ = r"E:\workbuddy\定时球报\足球速报"
TASKS = r"E:\workbuddy\定时球报"

GOAL_HEAD = re.compile(r"^-\s+\*\*(.+?)\*\*\s*(.*)$")
TIME_HEAD = re.compile(r"^(\d+(?:\+\d+)?)'")
ASSIST_RE = re.compile(r"[（(](助攻|无助攻|乌龙)[：:]?\s*(.*?)[）)]\s*$")
SUB_TITLE = re.compile(r"^\*\*(.+?)\*\*$")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
URL_LINE = re.compile(r"^(.*?)[：:]\s*(https?://\S+)\s*$")
SPEAKER_RE = re.compile(r"^-\s+(.{2,45}?)[：:]\s*(.+)$")
VS_RE = re.compile(r"^(.+?)\s+(\d+)\s*[-–—:：]\s*(\d+)\s+(.+)$")
EV_LABEL = re.compile(r"\*\*(.+?)\*\*\s*[：:]?")
COV_LABEL = re.compile(r"^\*\*(.+?)\*\*\s*[：:]?\s*(.*)$")


def unbold(s):
    return re.sub(r"\*\*(.+?)\*\*", r"\1", s)


def parse_goal(line):
    m = GOAL_HEAD.match(line)
    if not m:
        return None
    head, desc = m.group(1), m.group(2)
    desc = re.sub(r"^[—–\-]+", "", desc).strip()
    tm = TIME_HEAD.match(head)
    time = tm.group(1) + "'" if tm else ""
    core = head[tm.end():].strip() if tm else head
    assist_type, assist = "", ""
    am = ASSIST_RE.search(core)
    if am:
        assist_type = am.group(1)
        assist = am.group(2).strip()
        core = core[:am.start()].strip()
    team, scorer = "", core
    parts = core.split(None, 1)
    if len(parts) == 2:
        team, scorer = parts[0], parts[1]
    return {"time": time, "team": team, "scorer": scorer,
            "assistType": assist_type, "assist": assist, "desc": desc}


def parse_event(line):
    """把一行重大事件拆成 [{label, text}]，一行里可能有多个 **标签**：内容。"""
    s = line.lstrip("- ").strip()
    if "**" not in s:
        return [{"label": "", "text": unbold(s)}]
    ms = list(EV_LABEL.finditer(s))
    out = []
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(s)
        txt = unbold(s[m.end():end].strip())
        if re.fullmatch(r"[。.、\s]*", txt):
            txt = ""
        out.append({"label": m.group(1), "text": txt})
    return out


def parse_quote(line):
    m = SPEAKER_RE.match(line)
    if not m:
        return {"speaker": "", "quote": unbold(line.lstrip("- ").strip())}
    return {"speaker": unbold(m.group(1)).strip(), "quote": unbold(m.group(2)).strip()}


def parse_links(text):
    return [{"name": n.strip(), "url": u.strip()} for n, u in LINK_RE.findall(text)]


def split_subs(body):
    subs, cur, venue = {}, "head", ""
    subs[cur] = []
    for ln in body:
        s = ln.strip()
        if not s or s.startswith("---"):
            continue
        st = SUB_TITLE.match(s)
        if st:
            cur = st.group(1)
            subs[cur] = []
            continue
        if s.startswith("**来源**"):
            cur = "来源"
            subs[cur] = []
            rest = s.split("**", 2)[-1].lstrip("：:").strip()
            if rest:
                subs[cur].append(rest)
            continue
        if cur == "head" and s.startswith("（"):
            venue = s.strip("（）")
            continue
        subs[cur].append(s)
    return subs, venue


def parse_match(raw_title, body):
    subs, venue = split_subs(body)
    league, home, away, sh, sa = "", "", "", "", ""
    title = unbold(raw_title)
    title = re.sub(r"^\d+[\.、]\s*", "", title)
    if "·" in title:
        league, vs = title.split("·", 1)
        league, vs = league.strip(), vs.strip()
    else:
        vs = title
    vm = VS_RE.match(vs)
    if vm:
        home, sh, sa, away = vm.group(1), vm.group(2), vm.group(3), vm.group(4)
    goals = [g for g in (parse_goal(x) for x in subs.get("进球全记录", [])) if g]
    events = []
    for x in subs.get("其他重大事件", []):
        events += parse_event(x)
    pre = [parse_quote(x) for x in subs.get("赛前采访", []) if x.startswith("-")]
    post = [parse_quote(x) for x in subs.get("赛后采访", []) if x.startswith("-")]
    sources = []
    for x in subs.get("来源", []):
        sources += parse_links(x)
    return {"league": league, "home": home, "away": away, "scoreHome": sh, "scoreAway": sa,
            "venue": venue, "goals": goals, "events": events,
            "pre": pre, "post": post, "sources": sources}


def parse_md(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    base = os.path.basename(path)
    dm = re.search(r"(\d{4}-\d{2}-\d{2})", base) or re.search(r"(\d{4}-\d{2}-\d{2})", text)
    date = dm.group(1) if dm else ""
    wm = re.search(r"#.*?（周(.)）", text)
    weekday = wm.group(1) if wm else ""

    coverage, sections, cur = [], {}, None
    for ln in text.split("\n"):
        if ln.startswith("## "):
            cur = ln[3:].strip()
            sections[cur] = []
        elif cur is not None:
            sections[cur].append(ln)
        elif ln.startswith("> "):
            c = ln[2:].strip()
            cm = COV_LABEL.match(c)
            coverage.append({"label": cm.group(1), "text": unbold(cm.group(2))} if cm
                            else {"label": "", "text": unbold(c)})

    def sec(prefix):
        for k in sections:
            if k.strip().startswith(prefix):
                return sections[k]
        return []

    matches, cur_m = [], None
    for ln in sec("一"):
        if ln.startswith("### "):
            cur_m = [ln[4:].strip(), []]
            matches.append(cur_m)
        elif cur_m is not None:
            cur_m[1].append(ln)
    match_list = [parse_match(t, b) for t, b in matches]

    others = [parse_other(x) for x in sec("二") if x.strip().startswith("-")]
    stars = parse_bullets(sec("三"))
    world = parse_bullets(sec("四"))
    transfer = parse_bullets(sec("五"))
    sec6 = sec("六")
    preview = parse_preview(sec6)          # 新版：分版块的焦点前瞻
    schedule = parse_bullets(sec6)         # 旧版：扁平的赛程预告（向后兼容）
    refs, cur_g = [], None
    for ln in sec("七") or sec("三"):
        s = ln.strip()
        if not s:
            continue
        st = SUB_TITLE.match(s)
        if st:
            cur_g = {"group": st.group(1), "links": []}
            refs.append(cur_g)
            continue
        if not s.startswith("-"):
            continue
        item = s.lstrip("- ").strip()
        if cur_g is None:
            cur_g = {"group": "", "links": []}
            refs.append(cur_g)
        links = parse_links(item)
        if links:
            cur_g["links"] += links
        else:
            um = URL_LINE.match(item)
            if um:
                cur_g["links"].append({"name": um.group(1).strip(), "url": um.group(2).strip()})
            else:
                cur_g["links"].append({"name": unbold(item), "url": ""})

    title = match_list[0]["home"] + " " + match_list[0]["scoreHome"] + "-" + \
        match_list[0]["scoreAway"] + " " + match_list[0]["away"] if match_list else "足球赛事速报"
    tags = []
    for m in match_list:
        if m["home"]:
            tags.append(m["home"] + " " + m["scoreHome"] + "-" + m["scoreAway"] + " " + m["away"])
    summary = ""
    for c in coverage:
        if "覆盖范围" in c["label"]:
            summary = c["text"]
            break
    if len(summary) > 80:
        summary = summary[:78] + "…"

    return {"date": date, "weekday": weekday, "title": title, "summary": summary,
            "tags": tags, "coverage": coverage, "matches": match_list,
            "others": others, "stars": stars, "world": world,
            "transfer": transfer, "preview": preview, "schedule": schedule,
            "refs": refs, "md": text}


DASH_RE = re.compile(r"[—–\-]{1,2}")


def parse_item(line):
    """通用条目解析：`- **名字**（补充）**标签**：内容` 或 `- **标签**：内容`。

    返回 {name, tag, text}：
      name = 加粗的人名/球队名（可为空）
      tag  = 第二个加粗标记（板块标签，如「转会」「伤停」，可为空）
      text = 去掉标记后的正文
    """
    s = unbold(line.lstrip("- ").strip())
    # 先按 ** 分段，保住加粗信息
    raw = line.lstrip("- ").strip()
    bolds = re.findall(r"\*\*(.+?)\*\*", raw)
    # 正文 = 去掉所有 ** 后的内容，再剥掉开头的冒号/破折号
    body = unbold(raw)
    for b in bolds:
        body = body.replace(b, "", 1)
    body = body.lstrip("：:—–- \u3000").strip()
    # 剥掉正文开头残留的「（俱乐部/国家队）：」前缀，避免正文里重复显示
    body = re.sub(r"^[（(][^）)]*[）)]\s*[：:]?\s*", "", body).strip()
    name = bolds[0].strip() if bolds else ""
    tag = bolds[1].strip() if len(bolds) > 1 else ""
    return {"name": name, "tag": tag, "text": body}


def parse_bullets(lines):
    return [parse_item(x) for x in lines if x.strip().startswith("-")]


def parse_preview(lines):
    """六、焦点前瞻：按 ### 分成若干版块，每条是一个预告。

    md 形态：
        ### 6.1 焦点之战
        - **10-08 03:00 · 欧冠**：皇家马德里 vs 曼城
          - **看点**：xxx
          - **近况**：xxx
          - **交锋**：xxx
          - **伤停**：xxx

    返回 [{group, items:[{name, tag, text, detail:[{name,tag,text}]}]}]
    """
    groups, cur = [], None
    for ln in lines:
        s = ln.rstrip()
        st = s.strip()
        if not st or st.startswith("---"):
            continue
        if st.startswith("###"):
            cur = {"group": re.sub(r"^#+\s*", "", st).strip(), "items": []}
            groups.append(cur)
            continue
        if not st.startswith("-"):
            continue
        if cur is None:
            cur = {"group": "", "items": []}
            groups.append(cur)
        indent = len(s) - len(s.lstrip())
        if indent >= 2:
            # 缩进条目 = 上一条预告的详情字段
            if cur["items"]:
                cur["items"][-1].setdefault("detail", []).append(parse_item(st))
            continue
        it = parse_item(st)
        it["detail"] = []
        cur["items"].append(it)
    return [g for g in groups if g["items"]]


def parse_other(line):
    """其他完赛比分：欧国联 B2组 北爱尔兰 0:0 格鲁吉亚（备注）"""
    raw = unbold(line.lstrip("- ").strip())
    league, rest = "", raw
    if "组 " in raw:
        i = raw.index("组 ") + 1
        league, rest = raw[:i].strip(), raw[i + 1:].strip()
    note = ""
    if "（" in rest and rest.endswith("）"):
        j = rest.index("（")
        note, rest = rest[j + 1:-1], rest[:j].strip()
    vm = re.match(r"^(.+?)\s+(\d+)\s*[:：]\s*(\d+)\s+(.+)$", rest)
    if vm:
        return {"league": league, "home": vm.group(1), "scoreHome": vm.group(2),
                "scoreAway": vm.group(3), "away": vm.group(4), "note": note}
    return {"league": league, "home": rest, "scoreHome": "", "scoreAway": "",
            "away": "", "note": note}


def load_existing():
    p = os.path.join(PROJ, "report-data.js")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            t = f.read()
        m = re.search(r"window\.REPORTS\s*=\s*(\[.*\]);?\s*$", t, re.S)
        if m:
            try:
                return json.loads(m.group(1))
            except Exception as e:
                print("warn: parse existing report-data.js failed:", e)
    return []


def main():
    paths = sys.argv[1:]
    if not paths:
        paths = sorted(glob.glob(os.path.join(TASKS, "足球速报-*.md")))
    if not paths:
        print("no md found")
        return
    by_date = {r["date"]: r for r in load_existing()}
    for p in paths:
        r = parse_md(p)
        if not r["date"]:
            print("skip (no date):", p)
            continue
        by_date[r["date"]] = r
        pv = sum(len(g["items"]) for g in r.get("preview", []))
        print("imported: %s | %s | %d场重点 %d球 %d条其他比分 | 球星%d 足坛%d 转会%d | 前瞻%d版块%d场 | %d组来源"
              % (r["date"], r["title"], len(r["matches"]),
                 sum(len(m["goals"]) for m in r["matches"]), len(r["others"]),
                 len(r.get("stars", [])), len(r.get("world", [])),
                 len(r.get("transfer", [])),
                 len(r.get("preview", [])), pv, len(r["refs"])))
    lst = sorted(by_date.values(), key=lambda x: x["date"], reverse=True)
    out = "window.REPORTS = " + json.dumps(lst, ensure_ascii=False, indent=1) + ";\n"
    # 主文件 report-data.js；同时写一份旧名 data.js，
    # 供设备里还缓存着旧版 index.html（引用 data.js）的浏览器读取，避免读到空数据
    for name in ("report-data.js", "data.js"):
        with open(os.path.join(PROJ, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(out)
    print("total reports:", len(lst))


if __name__ == "__main__":
    main()
